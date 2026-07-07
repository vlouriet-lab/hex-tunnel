package com.sota.hexdecensor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.pm.ApplicationInfo
import android.content.pm.ServiceInfo
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*
import java.net.Inet4Address
import java.net.InetAddress
import java.io.FileDescriptor
import java.util.concurrent.atomic.AtomicLong
import org.json.JSONArray
import org.json.JSONObject

/**
 * HexVpnService — Android VpnService that manages the sing-box TUN tunnel.
 *
 * Communication flow:
 *   Flutter  ──MethodChannel──▶  SingBoxBridge  ──Intent──▶  HexVpnService
 *   HexVpnService  ──Broadcast──▶  SingBoxBridge  ──EventChannel──▶  Flutter
 *
 * sing-box integration:
 *   The service establishes an Android TUN interface and passes the file
 *   descriptor to sing-box libbox via the PlatformInterface.openTun() callback.
 *   When libbox is unavailable, a fallback SOCKS5 proxy mode is used.
 */
class HexVpnService : VpnService() {

    private enum class TunnelState {
        STOPPED,
        CONNECTING,
        CONNECTED,
        STOPPING
    }

    companion object {
        private const val TAG = "HexVpnService"
        const val NOTIFICATION_ID   = 1001
        const val CHANNEL_ID        = "hex_decensor_vpn"
        const val ACTION_START      = "com.sota.hexdecensor.START_VPN"
        const val ACTION_STOP       = "com.sota.hexdecensor.STOP_VPN"
        const val EXTRA_CONFIG      = "config_json"
        const val EXTRA_SESSION_ID  = "session_id"
        const val EXTRA_SPLIT_MODE  = "split_mode"
        const val EXTRA_PACKAGE_LIST = "package_list"
        const val EXTRA_DNS_SERVER  = "dns_server"
        const val EXTRA_DNS_HOSTNAME = "dns_hostname"
        const val EXTRA_NOTIFICATION_REGION = "notification_region"
        const val EXTRA_CONNECTION_MODE = "connection_mode"
        const val EXTRA_OFFLINE_DEBLOCK_SETTINGS = "offline_deblock_settings"
        const val EXTRA_OFFLINE_DEBLOCK_RUNTIME_BUNDLE = "offline_deblock_runtime_bundle"

        const val QUICK_TOGGLE_PREFS = "hex_quick_toggle"
        const val QUICK_TOGGLE_LAST_STATUS = "last_status"
        const val QUICK_TOGGLE_LAST_REGION = "last_region"
        const val QUICK_TOGGLE_CONFIG = "config_json"
        const val QUICK_TOGGLE_SPLIT_MODE = "split_mode"
        const val QUICK_TOGGLE_PACKAGE_LIST = "package_list"
        const val QUICK_TOGGLE_DNS_SERVER = "dns_server"
        const val QUICK_TOGGLE_DNS_HOSTNAME = "dns_hostname"
        const val QUICK_TOGGLE_CONNECTION_MODE = "connection_mode"
        const val QUICK_TOGGLE_OFFLINE_DEBLOCK_SETTINGS = "offline_deblock_settings"
        const val QUICK_TOGGLE_OFFLINE_DEBLOCK_RUNTIME_BUNDLE = "offline_deblock_runtime_bundle"
        const val QUICK_TOGGLE_NOTIFICATION_REGION = "notification_region"

        // Broadcast actions sent back to SingBoxBridge
        const val BROADCAST_STATUS  = "com.sota.hexdecensor.STATUS"
        const val EXTRA_STATUS      = "status"   // "connected" | "stopped" | "error"
        const val EXTRA_ERROR       = "error"
        const val EXTRA_ERROR_CODE  = "errorCode"
        const val EXTRA_STAGE       = "stage"
        const val EXTRA_NETWORK_EVENT_ID = "networkEventId"
        const val EXTRA_NETWORK_INTERFACE = "networkInterface"
        const val EXTRA_NETWORK_TRANSPORT = "networkTransport"

        // TUN interface parameters (same as sing-box defaults for Android)
        private const val TUN_MTU         = 1400
        private const val TUN_ADDR_V4     = "172.19.0.1"
        private const val TUN_PREFIX_V4   = 30
        private const val TUN_ADDR_V6     = "fdfe:dcba:9876::1"
        private const val TUN_PREFIX_V6   = 126
    }

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var tunInterface: ParcelFileDescriptor? = null
    private var singBoxController: SingBoxController? = null
    private var tlsTricksProxy: TlsTricksSocksProxy? = null
    private var startJob: Job? = null
    @Volatile
    private var connectionMode: String = "tunnel"
    @Volatile
    private var currentSessionId: String = ""
    @Volatile
    private var notificationRegionLabel: String = "Не определен"
    private val stateLock = Any()
    @Volatile
    private var tunnelState: TunnelState = TunnelState.STOPPED
    private val networkEventCounter = AtomicLong(0L)

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.action) {
            ACTION_START -> {
                val sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: "unknown"
                val config = intent.getStringExtra(EXTRA_CONFIG) ?: ""
                val splitMode = intent.getStringExtra(EXTRA_SPLIT_MODE) ?: "off"
                val packageList = intent.getStringArrayListExtra(EXTRA_PACKAGE_LIST) ?: arrayListOf()
                val dnsServer = intent.getStringExtra(EXTRA_DNS_SERVER)
                val dnsHostname = intent.getStringExtra(EXTRA_DNS_HOSTNAME)
                notificationRegionLabel =
                    normalizeNotificationRegion(intent.getStringExtra(EXTRA_NOTIFICATION_REGION))
                connectionMode = intent.getStringExtra(EXTRA_CONNECTION_MODE) ?: "tunnel"
                currentSessionId = sessionId
                val offlineDeblockSettings = intent.getStringExtra(EXTRA_OFFLINE_DEBLOCK_SETTINGS)
                val offlineDeblockRuntimeBundle =
                    intent.getStringExtra(EXTRA_OFFLINE_DEBLOCK_RUNTIME_BUNDLE)

                if (config.isBlank()) {
                    broadcastStatus(
                        "error",
                        "Empty VPN config",
                        errorCode = "config_missing",
                        stage = "start"
                    )
                    stopSelf()
                    return START_NOT_STICKY
                }

                synchronized(stateLock) {
                    if (tunnelState == TunnelState.CONNECTING || tunnelState == TunnelState.CONNECTED) {
                        Log.w(TAG, "Ignoring duplicate ACTION_START while state=$tunnelState")
                        return START_STICKY
                    }
                    tunnelState = TunnelState.CONNECTING
                }

                startVpnForeground(initialNotificationText())
                startJob?.cancel()
                startJob = serviceScope.launch {
                    Log.i(TAG, "start requested sessionId=$currentSessionId mode=$connectionMode")
                    startTunnel(
                        config,
                        splitMode,
                        packageList,
                        dnsServer,
                        dnsHostname,
                        offlineDeblockSettings,
                        offlineDeblockRuntimeBundle,
                    )
                }
                START_STICKY
            }
            ACTION_STOP -> {
                serviceScope.launch { stopTunnel() }
                START_NOT_STICKY
            }
            else -> START_NOT_STICKY
        }
    }

    override fun onRevoke() {
        super.onRevoke()
        serviceScope.launch { stopTunnel() }
    }

    override fun onDestroy() {
        startJob?.cancel()
        // Best-effort synchronous cleanup before the coroutine scope is cancelled
        try { singBoxController?.stop() } catch (_: Exception) {}
        singBoxController = null
        try { tlsTricksProxy?.stop() } catch (_: Exception) {}
        tlsTricksProxy = null
        try { tunInterface?.close() } catch (_: Exception) {}
        tunInterface = null
        super.onDestroy()
        serviceScope.cancel()
    }

    // ── Tunnel management ────────────────────────────────────────────────────

    private suspend fun startTunnel(
        configJson: String,
        splitMode: String,
        packageList: List<String>,
        dnsServer: String?,
        dnsHostname: String?,
        offlineDeblockSettingsRaw: String?,
        offlineDeblockRuntimeBundleRaw: String?
    ) {
        val startMs = System.currentTimeMillis()
        try {
            Log.i(TAG, "Starting tunnel")
            Log.i(TAG, "sessionId=$currentSessionId stage=tun_establish")
            broadcastStatus("connecting", null, stage = "tun_establish")

            if (connectionMode == "offline_deblock") {
                logOfflineDeblockRuntimeBundle(offlineDeblockRuntimeBundleRaw)
            }

            val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val underlyingNetworksBeforeVpn: Array<Network> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                cm.allNetworks.filter { network ->
                    val caps = cm.getNetworkCapabilities(network)
                    caps != null &&
                        caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                        !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
                }.toTypedArray()
            } else {
                emptyArray()
            }

            // Advertise only public resolvers to Android's system resolver.
            // The explicit marker in logs makes it easy to verify the device is
            // running the freshly built service implementation.
            val vpnDnsServers = mutableListOf<String>()

            val preferredDns = resolvePreferredDns(
                explicitDns = dnsServer,
                privateDnsHostname = dnsHostname,
                connectivityManager = cm,
                underlyingNetworks = underlyingNetworksBeforeVpn
            )
            if (!preferredDns.isNullOrEmpty()) {
                vpnDnsServers.add(preferredDns)
            }
            listOf("1.1.1.1", "8.8.8.8").forEach { fallbackDns ->
                if (!vpnDnsServers.contains(fallbackDns)) {
                    vpnDnsServers.add(fallbackDns)
                }
            }

            val isDebuggable =
                (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
            if (isDebuggable) {
                Log.i(
                    TAG,
                    "VPN DNS mode=primary+fallback preferred=${preferredDns ?: "none"} servers=${vpnDnsServers.joinToString(",")}",
                )
            }

            val tunMtu = extractTunMtu(configJson)
            Log.i(TAG, "Using Android TUN MTU=$tunMtu")

            // Build TUN interface
            val builder = Builder()
                .setSession(sessionName())
                .setMtu(tunMtu)
                .addAddress(TUN_ADDR_V4, TUN_PREFIX_V4)
                .addRoute("0.0.0.0", 0)     // Route all IPv4

            try {
                builder.addAddress(TUN_ADDR_V6, TUN_PREFIX_V6)
                builder.addRoute("::", 0)   // Route all IPv6
            } catch (e: IllegalArgumentException) {
                Log.w(TAG, "IPv6 address/route rejected by device, continuing with IPv4 only", e)
            }

            vpnDnsServers.forEach { dnsIp -> builder.addDnsServer(dnsIp) }


            // Let system components bypass VPN when needed for connectivity checks.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                builder.allowBypass()
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // Match common commercial VPN behavior: don't mark tunnel as metered
                // unless explicitly required by the app/business logic.
                builder.setMetered(false)
            }

            val distinctPackages = packageList
                .filter { it.isNotBlank() }
                .distinct()

            for (pkg in distinctPackages) {
                try {
                    when (splitMode) {
                        "only_selected" -> builder.addAllowedApplication(pkg)
                        "except_selected" -> builder.addDisallowedApplication(pkg)
                    }
                } catch (e: PackageManager.NameNotFoundException) {
                    Log.w(TAG, "Split tunneling package not found: $pkg", e)
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to apply split tunneling rule for: $pkg", e)
                }
            }

            val coreVersion = SingBoxController.getCoreVersion(this)
            Log.i(TAG, "Libbox core version: $coreVersion")

            try {
                SingBoxController.validateConfig(this, configJson)
            } catch (e: Exception) {
                Log.e(TAG, "Config preflight failed before TUN establish", e)
                broadcastStatus(
                    "error",
                    e.message ?: "Invalid sing-box config",
                    errorCode = "config_invalid",
                    stage = "config_preflight"
                )
                synchronized(stateLock) {
                    tunnelState = TunnelState.STOPPED
                }
                stopSelf()
                return
            }

            val tun = builder.establish()

            if (tun == null) {
                broadcastStatus(
                    "error",
                    "Failed to establish TUN interface",
                    errorCode = "tun_establish_failed",
                    stage = "tun_establish"
                )
                synchronized(stateLock) {
                    tunnelState = TunnelState.STOPPED
                }
                stopSelf()
                return
            }

            tunInterface = tun
            Log.i(TAG, "TUN fd = ${tun.fd}")
            val tunMs = System.currentTimeMillis() - startMs
            Log.i(TAG, "TUN establish took ${tunMs}ms")

            // Hint Android which physical network underlies this VPN.
            // Some OEM stacks behave better with Private DNS/validation when set.
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && underlyingNetworksBeforeVpn.isNotEmpty()) {
                    setUnderlyingNetworks(underlyingNetworksBeforeVpn)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Unable to set underlying network", e)
            }

            broadcastStatus("connecting", null, stage = "libbox_start")

            var runtimeConfig = configJson
            if (connectionMode == "offline_deblock") {
                val tlsOptions = TlsTricksOptions.fromSettingsJson(offlineDeblockSettingsRaw)
                if (tlsOptions.enabled) {
                    try {
                        tlsTricksProxy?.stop()
                    } catch (_: Exception) {
                    }
                    val proxy = TlsTricksSocksProxy(this, tlsOptions)
                    val proxyPort = proxy.start()
                    tlsTricksProxy = proxy
                    runtimeConfig = patchConfigForTlsTricks(runtimeConfig, proxyPort)
                    Log.i(TAG, "TLS tricks proxy enabled on localhost:$proxyPort")
                }
            }

            // Start sing-box with the TUN file descriptor
            singBoxController = SingBoxController(this, runtimeConfig, tun.fd) { ifName, transport ->
                handleUnderlyingNetworkChanged(ifName, transport)
            }
            singBoxController?.start()
            val totalMs = System.currentTimeMillis() - startMs
            Log.i(TAG, "Tunnel connected in ${totalMs}ms")

            updateNotification(connectedNotificationText())
            broadcastStatus("connected", null, stage = "connected")
            synchronized(stateLock) {
                tunnelState = TunnelState.CONNECTED
            }

        } catch (e: Exception) {
            Log.e(TAG, "startTunnel failed sessionId=$currentSessionId", e)
            // Clean up resources that may have been partially established before the failure
            try { singBoxController?.stop() } catch (_: Exception) {}
            singBoxController = null
            try { tlsTricksProxy?.stop() } catch (_: Exception) {}
            tlsTricksProxy = null
            try { tunInterface?.close() } catch (_: Exception) {}
            tunInterface = null
            val errorCode = when {
                e.message?.contains("permission", ignoreCase = true) == true -> "vpn_permission_denied"
                e.message?.contains("tun", ignoreCase = true) == true -> "tun_establish_failed"
                e.message?.contains("config", ignoreCase = true) == true -> "config_invalid"
                else -> "libbox_start_failed"
            }
            broadcastStatus(
                "error",
                e.message ?: "Unknown error",
                errorCode = errorCode,
                stage = "start_failed"
            )
            synchronized(stateLock) {
                tunnelState = TunnelState.STOPPED
            }
            stopSelf()
        }
    }

    private fun logOfflineDeblockRuntimeBundle(raw: String?) {
        if (raw.isNullOrBlank()) {
            Log.i(TAG, "offline_deblock runtime bundle: missing")
            return
        }

        try {
            val json = JSONObject(raw)
            val deliveryMode = json.optString("deliveryMode", "unknown")
            val bundleVersion = json.optInt("bundleVersion", -1)
            val bootstrapSource = json.optString("bootstrapSource", "")
            val ingressConfig = json.optJSONObject("ingressConfig")
            val edgeHost = ingressConfig?.optString("edgeHost", "") ?: ""
            val transport = ingressConfig?.optString("transport", "") ?: ""
            val outboundType = ingressConfig?.optString("outboundType", "") ?: ""

            Log.i(
                TAG,
                "offline_deblock runtime bundle delivery=$deliveryMode " +
                    "version=$bundleVersion source=${if (bootstrapSource.isBlank()) "-" else bootstrapSource} " +
                    "edge=${if (edgeHost.isBlank()) "-" else edgeHost} " +
                    "transport=${if (transport.isBlank()) "-" else transport} " +
                    "outbound=${if (outboundType.isBlank()) "-" else outboundType}",
            )
        } catch (e: Exception) {
            Log.w(TAG, "Failed to parse offline_deblock runtime bundle", e)
        }
    }

    private fun resolvePreferredDns(
        explicitDns: String?,
        privateDnsHostname: String?,
        connectivityManager: ConnectivityManager,
        underlyingNetworks: Array<Network>
    ): String? {
        val explicit = explicitDns?.trim().orEmpty()
        if (isIpv4Literal(explicit)) {
            return explicit
        }

        val hostname = privateDnsHostname?.trim().orEmpty()
        if (hostname.isNotEmpty()) {
            try {
                val resolved = InetAddress.getAllByName(hostname)
                    .firstOrNull { it is Inet4Address }
                    ?.hostAddress
                    ?.trim()
                if (isIpv4Literal(resolved)) {
                    return resolved
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to resolve private DNS hostname: $hostname", e)
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            for (network in underlyingNetworks) {
                try {
                    val linkProps = connectivityManager.getLinkProperties(network) ?: continue
                    val candidate = linkProps.dnsServers
                        .firstOrNull { it is Inet4Address }
                        ?.hostAddress
                        ?.trim()
                    if (isIpv4Literal(candidate)) {
                        return candidate
                    }
                } catch (_: Exception) {
                }
            }
        }

        return null
    }

    private fun isIpv4Literal(value: String?): Boolean {
        if (value.isNullOrBlank()) return false
        val parts = value.split('.')
        if (parts.size != 4) return false
        return parts.all { part ->
            if (part.isEmpty()) return false
            val n = part.toIntOrNull() ?: return false
            n in 0..255
        }
    }

    private suspend fun stopTunnel() {
        synchronized(stateLock) {
            if (tunnelState == TunnelState.STOPPED || tunnelState == TunnelState.STOPPING) {
                return
            }
            tunnelState = TunnelState.STOPPING
        }

        Log.i(TAG, "Stopping tunnel sessionId=$currentSessionId")
        try {
            singBoxController?.stop()
            singBoxController = null
            tlsTricksProxy?.stop()
            tlsTricksProxy = null
            tunInterface?.close()
            tunInterface = null
        } catch (e: Exception) {
            Log.w(TAG, "Error during tunnel stop", e)
        } finally {
            synchronized(stateLock) {
                tunnelState = TunnelState.STOPPED
            }
        }
        broadcastStatus("stopped", null, stage = "stopped")
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun patchConfigForTlsTricks(originalConfig: String, localPort: Int): String {
        return try {
            val root = JSONObject(originalConfig)
            val outbounds = root.optJSONArray("outbounds") ?: JSONArray().also {
                root.put("outbounds", it)
            }

            val route = root.optJSONObject("route") ?: JSONObject().also {
                root.put("route", it)
            }
            val previousFinal = route.optString("final", "direct")

            val tlsProxyOutbound = JSONObject().apply {
                put("type", "socks")
                put("tag", "tls_tricks_proxy")
                put("server", "127.0.0.1")
                put("server_port", localPort)
                put("version", "5")
                if (previousFinal.isNotBlank() && previousFinal != "tls_tricks_proxy") {
                    put("detour", previousFinal)
                }
            }

            var replaced = false
            for (i in 0 until outbounds.length()) {
                val item = outbounds.optJSONObject(i) ?: continue
                if (item.optString("tag") == "tls_tricks_proxy") {
                    outbounds.put(i, tlsProxyOutbound)
                    replaced = true
                    break
                }
            }
            if (!replaced) {
                outbounds.put(tlsProxyOutbound)
            }

            route.put("final", "tls_tricks_proxy")
            root.toString()
        } catch (e: Exception) {
            Log.w(TAG, "Failed to patch config for TLS tricks proxy", e)
            originalConfig
        }
    }

    private fun handleUnderlyingNetworkChanged(ifName: String?, transport: String?) {
        if (tunnelState != TunnelState.CONNECTED) {
            return
        }

        val eventId = networkEventCounter.incrementAndGet()
        val safeInterface = ifName?.trim().orEmpty()
        val safeTransport = transport?.trim().takeUnless { it.isNullOrEmpty() } ?: "unknown"
        Log.i(
            TAG,
            "Underlying network changed eventId=$eventId interface=${if (safeInterface.isBlank()) "-" else safeInterface} transport=$safeTransport",
        )
        broadcastStatus(
            "connected",
            null,
            stage = "connected",
            networkEventId = eventId,
            networkInterface = safeInterface,
            networkTransport = safeTransport,
        )
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun buildNotification(text: String): Notification {
        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, HexVpnService::class.java).apply { action = ACTION_STOP },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(notificationTitle())
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_hex_vpn)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_media_pause, "Отключить", stopIntent)
            .build()
    }

    private fun updateNotification(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.notify(NOTIFICATION_ID, buildNotification(text))
    }

    private fun startVpnForeground(text: String) {
        val notification = buildNotification(text)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            getString(R.string.vpn_channel_name),
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "Hex Tunnel VPN tunnel status" }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(channel)
    }

    private fun sessionName(): String {
        return if (connectionMode == "offline_deblock") {
            "Hex Offline Deblock"
        } else {
            "Hex Tunnel"
        }
    }

    private fun notificationTitle(): String {
        return getString(R.string.app_name)
    }

    private fun initialNotificationText(): String {
        val region = notificationRegionLabel
        return if (connectionMode == "offline_deblock") {
            "Запуск локального деблока… Регион: $region"
        } else {
            "VPN запускается. Регион: $region"
        }
    }

    private fun connectedNotificationText(): String {
        val region = notificationRegionLabel
        return if (connectionMode == "offline_deblock") {
            "Локальный деблок активен. Регион: $region"
        } else {
            "VPN активен. Регион: $region"
        }
    }

    private fun normalizeNotificationRegion(raw: String?): String {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) {
            return "Не определен"
        }
        return value
    }

    private fun extractTunMtu(configJson: String): Int {
        return try {
            val root = JSONObject(configJson)
            val inbounds = root.optJSONArray("inbounds") ?: return TUN_MTU
            for (index in 0 until inbounds.length()) {
                val inbound = inbounds.optJSONObject(index) ?: continue
                if (inbound.optString("type") != "tun") {
                    continue
                }
                val mtu = inbound.optInt("mtu", TUN_MTU)
                return mtu.coerceIn(1200, 1500)
            }
            TUN_MTU
        } catch (e: Exception) {
            Log.w(TAG, "Unable to parse tun MTU from config, using default $TUN_MTU", e)
            TUN_MTU
        }
    }

    // ── Broadcast helper ─────────────────────────────────────────────────────

    private fun broadcastStatus(
        status: String,
        error: String?,
        errorCode: String? = null,
        stage: String? = null,
        networkEventId: Long? = null,
        networkInterface: String? = null,
        networkTransport: String? = null,
    ) {
        getSharedPreferences(QUICK_TOGGLE_PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(QUICK_TOGGLE_LAST_STATUS, status)
            .putString(QUICK_TOGGLE_LAST_REGION, notificationRegionLabel)
            .apply()

        val intent = Intent(BROADCAST_STATUS).apply {
            putExtra(EXTRA_STATUS, status)
            putExtra(EXTRA_SESSION_ID, currentSessionId)
            if (error != null) putExtra(EXTRA_ERROR, error)
            if (errorCode != null) putExtra(EXTRA_ERROR_CODE, errorCode)
            if (stage != null) putExtra(EXTRA_STAGE, stage)
            if (networkEventId != null) {
                putExtra(EXTRA_NETWORK_EVENT_ID, networkEventId)
            }
            if (networkInterface != null) {
                putExtra(EXTRA_NETWORK_INTERFACE, networkInterface)
            }
            if (networkTransport != null) {
                putExtra(EXTRA_NETWORK_TRANSPORT, networkTransport)
            }
            setPackage(packageName)
        }
        sendBroadcast(intent)

        try {
            TileService.requestListeningState(
                this,
                ComponentName(this, QuickToggleTileService::class.java),
            )
        } catch (_: Exception) {
        }
    }
}
