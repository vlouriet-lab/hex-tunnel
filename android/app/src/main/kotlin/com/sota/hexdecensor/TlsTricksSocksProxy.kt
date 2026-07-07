package com.sota.hexdecensor

import android.net.VpnService
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.EOFException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.math.min
import kotlin.random.Random

private data class ClientHelloLayout(
    val handshakeLength: Int,
    val extensionsLengthOffset: Int,
    val extensionsStart: Int,
    val extensionsLength: Int,
    val hasPaddingExtension: Boolean,
    val sniHostOffset: Int?,
    val sniHostLength: Int?,
)

data class TlsTricksOptions(
    val enabled: Boolean,
    val fragmentEnabled: Boolean,
    val fragmentSize: Int,
    val fragmentSleepMs: Int,
    val mixedSniCase: Boolean,
    val paddingEnabled: Boolean,
    val paddingSize: Int,
) {
    companion object {
        fun fromSettingsJson(raw: String?): TlsTricksOptions {
            if (raw.isNullOrBlank()) {
                return TlsTricksOptions(
                    enabled = false,
                    fragmentEnabled = false,
                    fragmentSize = 20,
                    fragmentSleepMs = 4,
                    mixedSniCase = false,
                    paddingEnabled = false,
                    paddingSize = 256,
                )
            }
            val json = JSONObject(raw)
            val fragmentEnabled = json.optBoolean("tlsFragmentEnabled", false)
            val mixedSniCase = json.optBoolean("tlsMixedSniCase", false)
            val paddingEnabled = json.optBoolean("tlsPaddingEnabled", false)
            val fragmentSize = json.optInt("tlsFragmentSize", 20).coerceIn(10, 30)
            val fragmentSleepMs = json.optInt("tlsFragmentSleepMs", 4).coerceIn(2, 8)
            val paddingSize = json.optInt("tlsPaddingSize", 256).coerceIn(1, 1500)
            return TlsTricksOptions(
                enabled = fragmentEnabled || mixedSniCase || paddingEnabled,
                fragmentEnabled = fragmentEnabled,
                fragmentSize = fragmentSize,
                fragmentSleepMs = fragmentSleepMs,
                mixedSniCase = mixedSniCase,
                paddingEnabled = paddingEnabled,
                paddingSize = paddingSize,
            )
        }
    }
}

class TlsTricksSocksProxy(
    private val vpnService: VpnService,
    private val options: TlsTricksOptions,
) {
    companion object {
        private const val TAG = "TlsTricksProxy"
    }

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var acceptJob: Job? = null
    private var serverSocket: ServerSocket? = null

    fun start(): Int {
        if (!options.enabled) {
            throw IllegalStateException("TLS tricks proxy is disabled")
        }
        val socket = ServerSocket(0, 64, InetAddress.getByName("127.0.0.1"))
        serverSocket = socket
        acceptJob = scope.launch {
            while (!socket.isClosed) {
                try {
                    val client = socket.accept()
                    launch { handleClient(client) }
                } catch (_: Exception) {
                    if (!socket.isClosed) {
                        Log.w(TAG, "accept failed")
                    }
                }
            }
        }
        Log.i(TAG, "Started on 127.0.0.1:${socket.localPort} fragment=${options.fragmentEnabled} mixedSni=${options.mixedSniCase} padding=${options.paddingEnabled}")
        return socket.localPort
    }

    fun stop() {
        try {
            serverSocket?.close()
        } catch (_: Exception) {
        }
        acceptJob?.cancel()
        scope.cancel()
    }

    private fun handleClient(client: Socket) {
        client.use { clientSocket ->
            var remote: Socket? = null
            try {
                clientSocket.tcpNoDelay = true
                val input = clientSocket.getInputStream()
                val output = clientSocket.getOutputStream()

                val dest = negotiateSocks5(input, output)
                remote = Socket()
                remote.tcpNoDelay = true
                vpnService.protect(remote)
                remote.connect(InetSocketAddress(dest.first, dest.second), 12_000)

                sendSocks5Success(output)

                val downstream = scope.launch {
                    try {
                        relayRaw(remote.getInputStream(), output)
                    } catch (e: Exception) {
                        // ignore downstream errors (like SocketException: Socket closed)
                    }
                }

                try {
                    relayClientToRemote(input, remote.getOutputStream(), dest.first)
                } catch (e: Exception) {
                    // ignore upstream errors
                }
                downstream.cancel()
            } catch (e: Exception) {
                Log.w(TAG, "Client handling failed", e)
            } finally {
                try {
                    remote?.close()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun negotiateSocks5(input: InputStream, output: OutputStream): Pair<String, Int> {
        val version = readByte(input)
        if (version != 0x05) {
            throw IllegalStateException("Unsupported SOCKS version: $version")
        }
        val nMethods = readByte(input)
        if (nMethods < 0) throw EOFException("SOCKS methods missing")
        repeat(nMethods) { readByte(input) }

        output.write(byteArrayOf(0x05, 0x00))
        output.flush()

        val reqVer = readByte(input)
        val cmd = readByte(input)
        readByte(input) // RSV
        val atyp = readByte(input)

        if (reqVer != 0x05 || cmd != 0x01) {
            throw IllegalStateException("Unsupported SOCKS request")
        }

        val host = when (atyp) {
            0x01 -> {
                val raw = readFully(input, 4)
                "${raw[0].toUByte().toInt()}.${raw[1].toUByte().toInt()}.${raw[2].toUByte().toInt()}.${raw[3].toUByte().toInt()}"
            }
            0x03 -> {
                val len = readByte(input)
                val raw = readFully(input, len)
                String(raw, Charsets.US_ASCII)
            }
            0x04 -> {
                val raw = readFully(input, 16)
                InetAddress.getByAddress(raw).hostAddress
            }
            else -> throw IllegalStateException("Unsupported ATYP: $atyp")
        }

        val portRaw = readFully(input, 2)
        val port = ((portRaw[0].toInt() and 0xFF) shl 8) or (portRaw[1].toInt() and 0xFF)

        return host to port
    }

    private fun sendSocks5Success(output: OutputStream) {
        output.write(
            byteArrayOf(
                0x05,
                0x00,
                0x00,
                0x01,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
                0x00,
            ),
        )
        output.flush()
    }

    private fun relayClientToRemote(input: InputStream, output: OutputStream, destinationHost: String) {
        val buffer = ByteArray(8192)
        var initialProcessed = false
        val initialBuffer = ByteArrayOutputStream()

        while (true) {
            val read = input.read(buffer)
            if (read <= 0) {
                return
            }
            val payload = buffer.copyOf(read)

            if (!initialProcessed) {
                initialBuffer.write(payload)
                val transformed = tryTransformInitialPayload(
                    initialBuffer.toByteArray(),
                    destinationHost,
                )
                if (transformed == null) {
                    if (initialBuffer.size() > 32768) {
                        output.write(initialBuffer.toByteArray())
                        output.flush()
                        initialBuffer.reset()
                        initialProcessed = true
                    }
                    continue
                }

                writeWithTricks(output, transformed)
                initialBuffer.reset()
                initialProcessed = true
            } else {
                output.write(payload)
                output.flush()
            }
        }
    }

    private fun tryTransformInitialPayload(
        payload: ByteArray,
        destinationHost: String,
    ): ByteArray? {
        if (payload.size < 5) {
            return null
        }

        val recordLength = readU16(payload, 3)
        val recordEnd = 5 + recordLength
        if (payload.size < recordEnd) {
            return null
        }

        val firstRecord = payload.copyOfRange(0, recordEnd)
        val transformedFirst = transformFirstTlsRecord(firstRecord, destinationHost)
        if (payload.size == recordEnd) {
            return transformedFirst
        }

        val tail = payload.copyOfRange(recordEnd, payload.size)
        return transformedFirst + tail
    }

    private fun transformFirstTlsRecord(record: ByteArray, destinationHost: String): ByteArray {
        if (record.size < 5) {
            return record
        }
        if (record[0].toInt() and 0xFF != 0x16) {
            return record
        }

        val body = record.copyOfRange(5, record.size)
        if (body.size < 4 || body[0].toInt() and 0xFF != 0x01) {
            return record
        }

        var transformedBody = body
        transformedBody = maybeRewriteSniCase(transformedBody, destinationHost)
        if (options.paddingEnabled) {
            transformedBody = maybeInjectPaddingExtension(transformedBody)
        }

        if (transformedBody.size == body.size && transformedBody.contentEquals(body)) {
            return record
        }

        if (transformedBody.size > 16384) {
            Log.w(TAG, "Skipping TLS transform because record is too large: ${transformedBody.size}")
            return record
        }

        val out = ByteArray(5 + transformedBody.size)
        out[0] = record[0]
        out[1] = record[1]
        out[2] = record[2]
        writeU16(out, 3, transformedBody.size)
        System.arraycopy(transformedBody, 0, out, 5, transformedBody.size)
        return out
    }

    private fun writeWithTricks(output: OutputStream, payload: ByteArray) {
        val basePayload = payload
        if (!options.fragmentEnabled) {
            output.write(basePayload)
            output.flush()
            return
        }

        var offset = 0
        while (offset < basePayload.size) {
            val chunk = min(options.fragmentSize, basePayload.size - offset)
            output.write(basePayload, offset, chunk)
            output.flush()
            offset += chunk
            if (offset < basePayload.size) {
                Thread.sleep(options.fragmentSleepMs.toLong())
            }
        }
    }

    private fun maybeRewriteSniCase(payload: ByteArray, host: String): ByteArray {
        if (!options.mixedSniCase) {
            return payload
        }
        val layout = parseClientHelloLayout(payload) ?: return payload
        val hostOffset = layout.sniHostOffset ?: return payload
        val hostLength = layout.sniHostLength ?: return payload
        if (hostLength <= 0 || hostOffset + hostLength > payload.size) {
            return payload
        }

        val currentHost = String(payload, hostOffset, hostLength, Charsets.US_ASCII)
        if (host.isNotBlank() && !currentHost.equals(host, ignoreCase = true)) {
            return payload
        }

        val copy = payload.copyOf()
        for (j in 0 until hostLength) {
            val idx = hostOffset + j
            val original = copy[idx]
            if (original in 0x61..0x7A || original in 0x41..0x5A) {
                copy[idx] = if (Random.nextBoolean()) {
                    original.uppercaseCharCode().toByte()
                } else {
                    original.lowercaseCharCode().toByte()
                }
            }
        }
        return copy
    }

    private fun maybeInjectPaddingExtension(payload: ByteArray): ByteArray {
        val layout = parseClientHelloLayout(payload) ?: return payload
        if (layout.hasPaddingExtension) {
            return payload
        }

        val requestedPadding = options.paddingSize.coerceIn(1, 1500)
        val additionalHeader = 4
        val maxPayload = 16384
        val maxPadding = maxPayload - payload.size - additionalHeader
        if (maxPadding <= 0) {
            return payload
        }
        val paddingLen = min(requestedPadding, maxPadding)
        val totalAdditional = additionalHeader + paddingLen

        val out = ByteArray(payload.size + totalAdditional)
        val extEnd = layout.extensionsStart + layout.extensionsLength

        System.arraycopy(payload, 0, out, 0, extEnd)
        out[extEnd] = 0x00
        out[extEnd + 1] = 0x15
        writeU16(out, extEnd + 2, paddingLen)
        for (i in 0 until paddingLen) {
            out[extEnd + 4 + i] = 0x00
        }
        System.arraycopy(
            payload,
            extEnd,
            out,
            extEnd + totalAdditional,
            payload.size - extEnd,
        )

        writeU16(
            out,
            layout.extensionsLengthOffset,
            layout.extensionsLength + totalAdditional,
        )
        writeU24(out, 1, layout.handshakeLength + totalAdditional)

        return out
    }

    private fun parseClientHelloLayout(payload: ByteArray): ClientHelloLayout? {
        if (payload.size < 42) {
            return null
        }
        if ((payload[0].toInt() and 0xFF) != 0x01) {
            return null
        }

        val handshakeLen = readU24(payload, 1)
        val handshakeEnd = 4 + handshakeLen
        if (handshakeEnd > payload.size || handshakeLen < 38) {
            return null
        }

        var cursor = 4
        cursor += 2 // client_version
        cursor += 32 // random

        if (cursor >= handshakeEnd) return null
        val sessionIdLen = payload[cursor].toInt() and 0xFF
        cursor += 1 + sessionIdLen
        if (cursor + 2 > handshakeEnd) return null

        val cipherSuitesLen = readU16(payload, cursor)
        cursor += 2 + cipherSuitesLen
        if (cursor >= handshakeEnd) return null

        val compressionMethodsLen = payload[cursor].toInt() and 0xFF
        cursor += 1 + compressionMethodsLen
        if (cursor + 2 > handshakeEnd) return null

        val extensionsLengthOffset = cursor
        val extensionsLen = readU16(payload, cursor)
        cursor += 2
        val extensionsStart = cursor
        val extensionsEnd = extensionsStart + extensionsLen
        if (extensionsEnd > handshakeEnd) {
            return null
        }

        var hasPadding = false
        var sniOffset: Int? = null
        var sniLength: Int? = null

        var extCursor = extensionsStart
        while (extCursor + 4 <= extensionsEnd) {
            val extType = readU16(payload, extCursor)
            val extLen = readU16(payload, extCursor + 2)
            val extDataStart = extCursor + 4
            val extDataEnd = extDataStart + extLen
            if (extDataEnd > extensionsEnd) {
                break
            }

            if (extType == 0x0015) {
                hasPadding = true
            }

            if (extType == 0x0000 && extLen >= 5) {
                val listLen = readU16(payload, extDataStart)
                var nameCursor = extDataStart + 2
                val listEnd = min(extDataStart + 2 + listLen, extDataEnd)
                while (nameCursor + 3 <= listEnd) {
                    val nameType = payload[nameCursor].toInt() and 0xFF
                    val nameLen = readU16(payload, nameCursor + 1)
                    val nameStart = nameCursor + 3
                    val nameEnd = nameStart + nameLen
                    if (nameEnd > listEnd) {
                        break
                    }
                    if (nameType == 0 && sniOffset == null) {
                        sniOffset = nameStart
                        sniLength = nameLen
                        break
                    }
                    nameCursor = nameEnd
                }
            }

            extCursor = extDataEnd
        }

        return ClientHelloLayout(
            handshakeLength = handshakeLen,
            extensionsLengthOffset = extensionsLengthOffset,
            extensionsStart = extensionsStart,
            extensionsLength = extensionsLen,
            hasPaddingExtension = hasPadding,
            sniHostOffset = sniOffset,
            sniHostLength = sniLength,
        )
    }

    private fun relayRaw(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(8192)
        while (true) {
            val read = input.read(buffer)
            if (read <= 0) {
                return
            }
            output.write(buffer, 0, read)
            output.flush()
        }
    }

    private fun readByte(input: InputStream): Int {
        val value = input.read()
        if (value == -1) {
            throw EOFException("Unexpected EOF")
        }
        return value
    }

    private fun readFully(input: InputStream, length: Int): ByteArray {
        val out = ByteArray(length)
        var offset = 0
        while (offset < length) {
            val read = input.read(out, offset, length - offset)
            if (read <= 0) {
                throw EOFException("Unexpected EOF")
            }
            offset += read
        }
        return out
    }

    private fun readU16(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 8) or
            (bytes[offset + 1].toInt() and 0xFF)
    }

    private fun writeU16(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = ((value ushr 8) and 0xFF).toByte()
        bytes[offset + 1] = (value and 0xFF).toByte()
    }

    private fun readU24(bytes: ByteArray, offset: Int): Int {
        return ((bytes[offset].toInt() and 0xFF) shl 16) or
            ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
            (bytes[offset + 2].toInt() and 0xFF)
    }

    private fun writeU24(bytes: ByteArray, offset: Int, value: Int) {
        bytes[offset] = ((value ushr 16) and 0xFF).toByte()
        bytes[offset + 1] = ((value ushr 8) and 0xFF).toByte()
        bytes[offset + 2] = (value and 0xFF).toByte()
    }

    private fun Byte.uppercaseCharCode(): Int {
        val v = this.toInt() and 0xFF
        return if (v in 0x61..0x7A) v - 32 else v
    }

    private fun Byte.lowercaseCharCode(): Int {
        val v = this.toInt() and 0xFF
        return if (v in 0x41..0x5A) v + 32 else v
    }
}
