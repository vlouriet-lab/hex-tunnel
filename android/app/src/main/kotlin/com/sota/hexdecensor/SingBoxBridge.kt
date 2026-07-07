package com.sota.hexdecensor

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.os.Build
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket

/**
 * SingBoxBridge — Flutter MethodChannel handler.
 *
 * Translates Dart calls into Android Service commands and broadcasts
 * status changes back to Flutter via an EventChannel stream.
 */
class SingBoxBridge(private val activity: MainActivity) {

    companion object {
        private const val TAG = "SingBoxBridge"
    }

    // Holds a pending MethodChannel.Result during VPN permission flow
    internal var pendingResult: MethodChannel.Result? = null

    private var currentStatus = "stopped"
    private var currentMode = "tunnel"
    private var currentSessionId = ""
    private var currentServer = ""
    private var currentProtocol = ""
    private var latencyMs = -1
    private var lastErrorCode = ""
    private var lastStage = ""
    private var currentNetworkEventId = 0L
    private var currentNetworkInterface = ""
    private var currentNetworkTransport = ""

    private val coroutineScope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ── EventChannel stream handler ──────────────────────────────────────────

    val eventStreamHandler = object : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var statusReceiver: BroadcastReceiver? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            statusReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val status = intent.getStringExtra(HexVpnService.EXTRA_STATUS) ?: "stopped"
                    val error  = intent.getStringExtra(HexVpnService.EXTRA_ERROR)
                    val errorCode = intent.getStringExtra(HexVpnService.EXTRA_ERROR_CODE) ?: ""
                    val stage = intent.getStringExtra(HexVpnService.EXTRA_STAGE) ?: ""
                    val sessionId = intent.getStringExtra(HexVpnService.EXTRA_SESSION_ID) ?: ""
                    val networkEventId =
                        intent.getLongExtra(HexVpnService.EXTRA_NETWORK_EVENT_ID, 0L)
                    val networkInterface =
                        intent.getStringExtra(HexVpnService.EXTRA_NETWORK_INTERFACE)
                    val networkTransport =
                        intent.getStringExtra(HexVpnService.EXTRA_NETWORK_TRANSPORT)
                    if (status == "stopped" || status == "error") {
                        currentServer = ""
                        currentProtocol = ""
                        currentNetworkEventId = 0L
                        currentNetworkInterface = ""
                        currentNetworkTransport = ""
                        if (status == "stopped") latencyMs = -1
                    }
                    if (sessionId.isNotBlank()) {
                        currentSessionId = sessionId
                    }
                    if (networkEventId > 0L) {
                        currentNetworkEventId = networkEventId
                    }
                    if (networkInterface != null) {
                        currentNetworkInterface = networkInterface
                    }
                    if (networkTransport != null) {
                        currentNetworkTransport = networkTransport
                    }
                    lastErrorCode = errorCode
                    lastStage = stage
                    currentStatus = status
                    if (isDebuggable()) {
                        Log.i(TAG, "status=$status sessionId=$currentSessionId error=${error ?: ""}")
                    }
                    val map = buildStatusMap(status, error, errorCode, stage)
                    val sink = eventSink ?: return
                    activity.runOnUiThread { sink.success(map) }
                }
            }
            val filter = IntentFilter(HexVpnService.BROADCAST_STATUS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(statusReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                activity.registerReceiver(statusReceiver, filter)
            }

            val snapshot = getStatusMap()
            activity.runOnUiThread { eventSink?.success(snapshot) }
        }

        override fun onCancel(arguments: Any?) {
            statusReceiver?.let { activity.unregisterReceiver(it) }
            statusReceiver = null
            eventSink = null
        }
    }

    // ── MethodChannel handlers ───────────────────────────────────────────────

    fun startService(
        sessionId: String,
        configJson: String,
        splitMode: String,
        packageNames: List<String>,
        privateDnsServer: String?,
        privateDnsHostname: String?,
        notificationRegion: String?,
        connectionMode: String,
        offlineDeblockSettings: String?,
        offlineDeblockRuntimeBundle: String?,
        result: MethodChannel.Result?
    ) {
        try {
            currentSessionId = sessionId
            updateCurrentTargetFromConfig(configJson)
            currentMode = connectionMode
            if (connectionMode == "offline_deblock") {
                currentProtocol = "offline_deblock"
                currentServer = "local"
            }
            cacheQuickToggleStartPayload(
                configJson = configJson,
                splitMode = splitMode,
                packageNames = packageNames,
                privateDnsServer = privateDnsServer,
                privateDnsHostname = privateDnsHostname,
                notificationRegion = notificationRegion,
                connectionMode = connectionMode,
                offlineDeblockSettings = offlineDeblockSettings,
                offlineDeblockRuntimeBundle = offlineDeblockRuntimeBundle,
            )
            val intent = Intent(activity, HexVpnService::class.java).apply {
                action = HexVpnService.ACTION_START
                putExtra(HexVpnService.EXTRA_CONFIG, configJson)
                putExtra(HexVpnService.EXTRA_SESSION_ID, sessionId)
                putExtra(HexVpnService.EXTRA_SPLIT_MODE, splitMode)
                putStringArrayListExtra(
                    HexVpnService.EXTRA_PACKAGE_LIST,
                    ArrayList(packageNames)
                )
                putExtra(HexVpnService.EXTRA_DNS_SERVER, privateDnsServer)
                putExtra(HexVpnService.EXTRA_DNS_HOSTNAME, privateDnsHostname)
                putExtra(HexVpnService.EXTRA_NOTIFICATION_REGION, notificationRegion)
                putExtra(HexVpnService.EXTRA_CONNECTION_MODE, connectionMode)
                putExtra(HexVpnService.EXTRA_OFFLINE_DEBLOCK_SETTINGS, offlineDeblockSettings)
                putExtra(HexVpnService.EXTRA_OFFLINE_DEBLOCK_RUNTIME_BUNDLE, offlineDeblockRuntimeBundle)
            }
            activity.startForegroundService(intent)
            currentStatus = "connecting"
            if (isDebuggable()) {
                Log.i(TAG, "startService sessionId=$currentSessionId server=$currentServer protocol=$currentProtocol")
            }
            result?.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "startService failed", e)
            result?.error("START_FAILED", e.message, null)
        }
    }

    private fun cacheQuickToggleStartPayload(
        configJson: String,
        splitMode: String,
        packageNames: List<String>,
        privateDnsServer: String?,
        privateDnsHostname: String?,
        notificationRegion: String?,
        connectionMode: String,
        offlineDeblockSettings: String?,
        offlineDeblockRuntimeBundle: String?,
    ) {
        activity.getSharedPreferences(HexVpnService.QUICK_TOGGLE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(HexVpnService.QUICK_TOGGLE_CONFIG, configJson)
            .putString(HexVpnService.QUICK_TOGGLE_SPLIT_MODE, splitMode)
            .putStringSet(HexVpnService.QUICK_TOGGLE_PACKAGE_LIST, packageNames.toSet())
            .putString(HexVpnService.QUICK_TOGGLE_DNS_SERVER, privateDnsServer)
            .putString(HexVpnService.QUICK_TOGGLE_DNS_HOSTNAME, privateDnsHostname)
            .putString(HexVpnService.QUICK_TOGGLE_NOTIFICATION_REGION, notificationRegion)
            .putString(HexVpnService.QUICK_TOGGLE_CONNECTION_MODE, connectionMode)
            .putString(HexVpnService.QUICK_TOGGLE_OFFLINE_DEBLOCK_SETTINGS, offlineDeblockSettings)
            .putString(
                HexVpnService.QUICK_TOGGLE_OFFLINE_DEBLOCK_RUNTIME_BUNDLE,
                offlineDeblockRuntimeBundle,
            )
            .apply()
    }

    fun stop(result: MethodChannel.Result) {
        try {
            val intent = Intent(activity, HexVpnService::class.java).apply {
                action = HexVpnService.ACTION_STOP
            }
            activity.startService(intent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "stop failed", e)
            result.error("STOP_FAILED", e.message, null)
        }
    }

    fun isRunning(): Boolean {
        if (currentStatus == "connected" || currentStatus == "connecting") {
            return true
        }
        @Suppress("DEPRECATION")
        val runningServices =
            (activity.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager)
                .getRunningServices(Int.MAX_VALUE)
        return runningServices.any {
            it.service.className == HexVpnService::class.java.name
        }
    }

    fun getStatusMap(): Map<String, Any> {
        val status = effectiveStatus()
        return buildStatusMap(status, null, lastErrorCode, lastStage)
    }

    fun testLatency(server: String, port: Int, result: MethodChannel.Result) {
        coroutineScope.launch {
            val ms = measureTcpLatency(server, port)
            latencyMs = ms
            withContext(Dispatchers.Main) { result.success(ms) }
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private fun buildStatusMap(
        status: String,
        error: String?,
        errorCode: String,
        stage: String
    ): Map<String, Any> {
        return mapOf(
            "status"    to status,
            "server"    to currentServer,
            "protocol"  to currentProtocol,
            "mode" to currentMode,
            "sessionId" to currentSessionId,
            "latencyMs" to latencyMs,
            "error"     to (error ?: ""),
            "errorCode" to errorCode,
            "stage" to stage,
            "networkEventId" to currentNetworkEventId,
            "networkInterface" to currentNetworkInterface,
            "networkTransport" to currentNetworkTransport,
        )
    }

    private fun effectiveStatus(): String {
        if (currentStatus == "connected" || currentStatus == "connecting" || currentStatus == "error") {
            return currentStatus
        }
        return if (isRunning()) "connected" else currentStatus
    }

    private fun measureTcpLatency(host: String, port: Int): Int {
        return try {
            if (host.isBlank()) return -1
            val start = System.currentTimeMillis()
            Socket().use { socket ->
                socket.connect(InetSocketAddress(host, port), 5000)
                (System.currentTimeMillis() - start).toInt()
            }
        } catch (e: Exception) {
            -1
        }
    }

    private fun updateCurrentTargetFromConfig(configJson: String) {
        try {
            val root = JSONObject(configJson)
            val outbounds = root.optJSONArray("outbounds") ?: return

            for (i in 0 until outbounds.length()) {
                val outbound = outbounds.optJSONObject(i) ?: continue
                val tag = outbound.optString("tag")
                if (tag == "proxy") {
                    currentServer = outbound.optString("server", "")
                    currentProtocol = outbound.optString("type", "")
                    return
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Unable to parse outbound target from config", e)
            currentServer = ""
            currentProtocol = ""
        }
    }

    private fun isDebuggable(): Boolean {
        return (activity.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }
}
