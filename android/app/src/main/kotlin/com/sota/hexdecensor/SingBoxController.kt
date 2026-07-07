package com.sota.hexdecensor

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.nekohasekai.libbox.CommandServer
import io.nekohasekai.libbox.CommandServerHandler
import io.nekohasekai.libbox.ConnectionOwner
import io.nekohasekai.libbox.InterfaceUpdateListener
import io.nekohasekai.libbox.Libbox
import io.nekohasekai.libbox.LocalDNSTransport
import io.nekohasekai.libbox.NetworkInterface as LibboxNetworkInterface
import io.nekohasekai.libbox.NetworkInterfaceIterator
import io.nekohasekai.libbox.Notification
import io.nekohasekai.libbox.OverrideOptions
import io.nekohasekai.libbox.PlatformInterface
import io.nekohasekai.libbox.SetupOptions
import io.nekohasekai.libbox.StringIterator
import io.nekohasekai.libbox.SystemProxyStatus
import io.nekohasekai.libbox.TunOptions
import io.nekohasekai.libbox.WIFIState
import org.json.JSONObject
import java.net.NetworkInterface as JavaNetworkInterface

/**
 * SingBoxController — wraps the sing-box libbox CommandServer lifecycle.
 *
 * Flow:
 *  1. Libbox.setup() — initialize working paths
 *  2. CommandServer(handler, platformInterface).start() — start gRPC control server
 *  3. commandServer.startOrReloadService(configJson, overrideOptions) — launch VPN
 *  4. commandServer.closeService() / commandServer.close() — stop VPN
 */
class SingBoxController(
    private val vpnService: VpnService,
    private val configJson: String,
    private val tunFd: Int,
    private val onUnderlyingNetworkChanged: ((String?, String?) -> Unit)? = null,
) {
    private enum class ServiceState {
        STOPPED,
        STARTING,
        RUNNING,
        STOPPING
    }

    companion object {
        private const val TAG = "SingBoxController"
        private val setupLock = Any()
        @Volatile
        private var isLibboxInitialized = false

        private fun ensureLibboxSetup(context: Context) {
            synchronized(setupLock) {
                if (isLibboxInitialized) return
                val opts = SetupOptions().apply {
                    setBasePath(context.filesDir.absolutePath)
                    setWorkingPath(context.filesDir.absolutePath + "/singbox")
                    setTempPath(context.cacheDir.absolutePath + "/singbox_tmp")
                    setFixAndroidStack(true)
                    setLogMaxLines(200)
                }
                Libbox.setup(opts)
                isLibboxInitialized = true
            }
        }

        fun getCoreVersion(context: Context): String {
            return try {
                ensureLibboxSetup(context)
                Libbox.version()
            } catch (e: Exception) {
                Log.w(TAG, "Unable to read libbox version", e)
                "unknown"
            }
        }

        fun validateConfig(context: Context, configJson: String) {
            ensureLibboxSetup(context)
            Libbox.checkConfig(configJson)
        }
    }

    private var commandServer: CommandServer? = null
    private val lifecycleLock = Any()
    @Volatile
    private var state = ServiceState.STOPPED

    fun start() {
        synchronized(lifecycleLock) {
            if (state == ServiceState.STARTING || state == ServiceState.RUNNING) {
                Log.w(TAG, "Ignoring start while state=$state")
                return
            }
            state = ServiceState.STARTING
        }

        Log.i(TAG, "Starting sing-box service")
        try {
            ensureLibboxSetup()

            val patchedConfig = injectLogOutput(configJson)

            val platform = HexPlatformInterface(
                vpnService,
                tunFd,
                onUnderlyingNetworkChanged,
            )
            val handler = HexCommandServerHandler()
            commandServer = CommandServer(handler, platform)
            commandServer!!.start()
            commandServer!!.startOrReloadService(patchedConfig, OverrideOptions())

            synchronized(lifecycleLock) {
                state = ServiceState.RUNNING
            }
            Log.i(TAG, "sing-box service started")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start sing-box", e)
            synchronized(lifecycleLock) {
                state = ServiceState.STOPPED
            }
            throw e
        }
    }

    fun stop() {
        synchronized(lifecycleLock) {
            if (state == ServiceState.STOPPED || state == ServiceState.STOPPING) {
                return
            }
            state = ServiceState.STOPPING
        }

        Log.i(TAG, "Stopping sing-box service")
        try {
            commandServer?.closeService()
            commandServer?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing sing-box", e)
        } finally {
            commandServer = null
            synchronized(lifecycleLock) {
                state = ServiceState.STOPPED
            }
        }
        Log.i(TAG, "sing-box service stopped")
    }

    fun isRunning(): Boolean = state == ServiceState.RUNNING

    private fun injectLogOutput(configJson: String): String {
        return try {
            val json = JSONObject(configJson)
            val log = json.optJSONObject("log") ?: JSONObject()
            val logFile = vpnService.filesDir.absolutePath + "/singbox/box.log"
            log.put("output", logFile)
            json.put("log", log)
            Log.i(TAG, "sing-box log output: $logFile")
            json.toString()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to inject log output path", e)
            configJson
        }
    }

    private fun ensureLibboxSetup() {
        ensureLibboxSetup(vpnService)
    }
}

// ── PlatformInterface ─────────────────────────────────────────────────────────

class HexPlatformInterface(
    private val vpnService: VpnService,
    private val preEstablishedTunFd: Int,
    private val onUnderlyingNetworkChanged: ((String?, String?) -> Unit)? = null,
) : PlatformInterface {

    private val connectivityManager =
        vpnService.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private var networkCallback: ConnectivityManager.NetworkCallback? = null

    // Debounce rapid interface updates to prevent connection-breaking flapping
    private val debounceHandler = Handler(Looper.getMainLooper())
    private var pendingUpdate: Runnable? = null
    private companion object {
        const val DEBOUNCE_MS = 300L
    }

    override fun openTun(options: TunOptions): Int = preEstablishedTunFd

    override fun autoDetectInterfaceControl(fd: Int) {
        if (!vpnService.protect(fd)) throw Exception("protect() failed for fd=$fd")
    }

    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun useProcFS(): Boolean = true
    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun localDNSTransport(): LocalDNSTransport? = null
    override fun clearDNSCache() {}
    override fun readWIFIState(): WIFIState? = null
    override fun systemCertificates(): StringIterator = EmptyStringIterator()

    override fun sendNotification(notification: Notification) {
        if (Log.isLoggable("SingBox", Log.DEBUG)) {
            Log.d("SingBox", "Notification: ${notification.title} - ${notification.body}")
        }
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        try {
            val javaInterfaces = JavaNetworkInterface.getNetworkInterfaces()
            if (javaInterfaces != null) {
                for (javaIf in javaInterfaces) {
                    // Skip VPN TUN and dummy interfaces to avoid recursion
                    val name = javaIf.name ?: continue
                    if (name.startsWith("tun") || name.startsWith("dummy")) continue

                    val libboxIf = LibboxNetworkInterface()
                    libboxIf.name = name
                    libboxIf.index = javaIf.index
                    libboxIf.mtu = try { javaIf.mtu } catch (_: Exception) { 0 }
                    libboxIf.metered = false
                    libboxIf.dnsServer = EmptyStringIterator()

                    // Map Java NetworkInterface flags to Go net.Flags
                    // Go constants: FlagUp=1, FlagBroadcast=2, FlagLoopback=4, FlagPointToPoint=8, FlagMulticast=16
                    var goFlags = 0
                    try {
                        if (javaIf.isUp) goFlags = goFlags or 1
                        if (javaIf.isLoopback) goFlags = goFlags or 4
                        if (javaIf.isPointToPoint) goFlags = goFlags or 8
                        if (javaIf.supportsMulticast()) goFlags = goFlags or 16
                        // Broadcast: not directly queryable; set for non-loopback UP interfaces
                        if (javaIf.isUp && !javaIf.isLoopback && !javaIf.isPointToPoint) goFlags = goFlags or 2
                    } catch (_: Exception) {
                        goFlags = 1 // assume UP
                    }
                    libboxIf.flags = goFlags
                    // Map interface name to sing-box type: WiFi=0, Cellular=1, Ethernet=2, Other=3
                    libboxIf.type = when {
                        name.startsWith("wlan") -> 0
                        name.startsWith("rmnet") || name.startsWith("ccmni") || name.startsWith("pdp") || name.startsWith("seth") -> 1
                        name.startsWith("eth") || name.startsWith("usb") -> 2
                        else -> 3
                    }

                    val addrs = mutableListOf<String>()
                    for (addr in javaIf.interfaceAddresses) {
                        val hostAddr = addr.address?.hostAddress ?: continue
                        // Strip IPv6 scope ID (%wlan0 etc.) — libbox Go parser can't handle it
                        val cleanAddr = hostAddr.substringBefore('%')
                        addrs.add("$cleanAddr/${addr.networkPrefixLength}")
                    }
                    libboxIf.addresses = ListStringIterator(addrs)
                    interfaces.add(libboxIf)
                }
            }
        } catch (e: Exception) {
            Log.w("SingBox", "Failed to enumerate network interfaces", e)
        }
        Log.d("SingBox", "getInterfaces: ${interfaces.map { it.name }}")
        return ListNetworkInterfaceIterator(interfaces)
    }

    override fun findConnectionOwner(
        ipProtocol: Int, sourceAddress: String, sourcePort: Int,
        destinationAddress: String, destinationPort: Int
    ): ConnectionOwner {
        throw Exception("findConnectionOwner not supported")
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        Log.i("SingBox", "startDefaultInterfaceMonitor")

        // Find the current default non-VPN network and report it immediately
        notifyCurrentDefaultInterface(listener)

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.d("SingBox", "Network available: $network")
                debouncedPickBestInterface(listener)
            }

            override fun onLinkPropertiesChanged(network: Network, linkProperties: LinkProperties) {
                Log.d("SingBox", "Link properties changed: ${linkProperties.interfaceName}")
                debouncedPickBestInterface(listener)
            }

            override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
                debouncedPickBestInterface(listener)
            }

            override fun onLost(network: Network) {
                Log.d("SingBox", "Network lost: $network")
                debouncedPickBestInterface(listener)
            }
        }

        val request = NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()

        try {
            connectivityManager.registerNetworkCallback(request, callback)
            networkCallback = callback
        } catch (e: Exception) {
            Log.e("SingBox", "Failed to register network callback", e)
        }
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        Log.i("SingBox", "closeDefaultInterfaceMonitor")
        pendingUpdate?.let { debounceHandler.removeCallbacks(it) }
        pendingUpdate = null
        networkCallback?.let {
            try {
                connectivityManager.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                Log.w("SingBox", "Failed to unregister network callback", e)
            }
            networkCallback = null
        }
    }

    /**
     * Debounce interface updates: collect rapid-fire callbacks within [DEBOUNCE_MS],
     * then pick the best available network (WiFi > Ethernet > Cellular).
     */
    private fun debouncedPickBestInterface(listener: InterfaceUpdateListener) {
        pendingUpdate?.let { debounceHandler.removeCallbacks(it) }
        pendingUpdate = Runnable { notifyCurrentDefaultInterface(listener) }
        debounceHandler.postDelayed(pendingUpdate!!, DEBOUNCE_MS)
    }

    private fun notifyCurrentDefaultInterface(listener: InterfaceUpdateListener) {
        try {
            data class Candidate(val network: Network, val ifName: String, val caps: NetworkCapabilities)
            val candidates = mutableListOf<Candidate>()

            for (network in connectivityManager.allNetworks) {
                val caps = connectivityManager.getNetworkCapabilities(network) ?: continue
                if (!caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) continue
                if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) continue
                val lp = connectivityManager.getLinkProperties(network) ?: continue
                val ifName = lp.interfaceName ?: continue
                candidates.add(Candidate(network, ifName, caps))
            }

            // Prefer WiFi > Ethernet > Cellular > Other
            val best = candidates.minByOrNull { (_, _, caps) ->
                when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> 0
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> 1
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> 2
                    else -> 3
                }
            }

            if (best == null) {
                Log.w("SingBox", "No non-VPN internet network found")
                onUnderlyingNetworkChanged?.invoke(null, "offline")
                return
            }

            val isExpensive = best.caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == false
            val isConstrained = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                best.caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_CONGESTED) == false
            } else false
            val ifIndex = resolveInterfaceIndex(best.ifName)
            Log.i("SingBox", "Default interface: ${best.ifName} index=$ifIndex (network=${best.network}, expensive=$isExpensive, constrained=$isConstrained)")
            onUnderlyingNetworkChanged?.invoke(best.ifName, describeTransport(best.caps))
            listener.updateDefaultInterface(best.ifName, ifIndex, isExpensive, isConstrained)
        } catch (e: Exception) {
            Log.w("SingBox", "Failed to detect default interface", e)
        }
    }

    private fun describeTransport(caps: NetworkCapabilities): String {
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            else -> "other"
        }
    }

    private fun resolveInterfaceIndex(ifName: String): Int {
        return try {
            JavaNetworkInterface.getByName(ifName)?.index ?: 0
        } catch (_: Exception) {
            0
        }
    }
}

// ── CommandServerHandler ──────────────────────────────────────────────────────

class HexCommandServerHandler : CommandServerHandler {
    override fun serviceStop() { Log.i("SingBox", "serviceStop") }
    override fun serviceReload() { Log.i("SingBox", "serviceReload") }
    override fun getSystemProxyStatus(): SystemProxyStatus =
        SystemProxyStatus().apply { setAvailable(false); setEnabled(false) }
    override fun setSystemProxyEnabled(enabled: Boolean) {}
    override fun writeDebugMessage(message: String) {
        if (Log.isLoggable("SingBox", Log.DEBUG)) {
            Log.d("SingBox", message)
        }
    }
}

// ── EmptyStringIterator ───────────────────────────────────────────────────────

class EmptyStringIterator : StringIterator {
    override fun hasNext(): Boolean = false
    override fun len(): Int = 0
    override fun next(): String = ""
}

// ── ListStringIterator ───────────────────────────────────────────────────────

class ListStringIterator(private val items: List<String>) : StringIterator {
    private var index = 0
    override fun hasNext(): Boolean = index < items.size
    override fun len(): Int = items.size
    override fun next(): String = items[index++]
}

// ── ListNetworkInterfaceIterator ─────────────────────────────────────────────

class ListNetworkInterfaceIterator(
    private val items: List<LibboxNetworkInterface>
) : NetworkInterfaceIterator {
    private var index = 0
    override fun hasNext(): Boolean = index < items.size
    override fun next(): LibboxNetworkInterface = items[index++]
}
