package com.sota.hexdecensor

import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.Manifest
import android.os.Build
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — entry point of the application.
 *
 * Extends FlutterFragmentActivity (→ FragmentActivity → ComponentActivity) so that
 * the modern Activity Result API (registerForActivityResult) is available directly,
 * eliminating the deprecated startActivityForResult / onActivityResult pair.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        const val SINGBOX_CHANNEL = "hex_decensor/singbox"
        const val STATUS_CHANNEL  = "hex_decensor/status"
    }

    private lateinit var bridge: SingBoxBridge
    private var pendingConfig: PendingVpnConfig? = null
    private val permissionHandler = Handler(Looper.getMainLooper())
    private val permissionTimeoutRunnable = Runnable {
        if (bridge.pendingResult != null || pendingConfig != null) {
            pendingConfig = null
            bridge.pendingResult?.error(
                "VPN_PERMISSION_TIMEOUT",
                "VPN permission dialog timed out",
                null
            )
            bridge.pendingResult = null
        }
    }

    private val notificationsPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { _ -> }

    // Registered at class initialisation time — safe because FlutterFragmentActivity
    // is a ComponentActivity and lifecycle-aware registration is guaranteed.
    private val vpnPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            handleVpnPermissionResult(result.resultCode)
        }

    private data class PendingVpnConfig(
        val sessionId: String,
        val config: String,
        val splitMode: String,
        val packageNames: List<String>,
        val privateDnsServer: String?,
        val privateDnsHostname: String?,
        val notificationRegion: String?,
        val connectionMode: String,
        val offlineDeblockSettings: String?,
        val offlineDeblockRuntimeBundle: String?,
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        ensureNotificationsPermissionIfNeeded()

        bridge = SingBoxBridge(this)

        // Main method channel
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            SINGBOX_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val sessionId = call.argument<String>("sessionId") ?: "unknown"
                    val config = call.argument<String>("config") ?: ""
                    val splitMode = call.argument<String>("splitMode") ?: "off"
                    val packageNames = call.argument<List<String>>("packageNames") ?: emptyList()
                    val privateDnsServer = call.argument<String>("privateDnsServer")
                    val privateDnsHostname = call.argument<String>("privateDnsHostname")
                    val notificationRegion = call.argument<String>("notificationRegion")
                    val connectionMode = call.argument<String>("connectionMode") ?: "tunnel"
                    val offlineDeblockSettings = call.argument<String>("offlineDeblockSettings")
                    val offlineDeblockRuntimeBundle = call.argument<String>("offlineDeblockRuntimeBundle")
                    requestVpnPermissionAndStart(
                        sessionId,
                        config,
                        splitMode,
                        packageNames,
                        privateDnsServer,
                        privateDnsHostname,
                        notificationRegion,
                        connectionMode,
                        offlineDeblockSettings,
                        offlineDeblockRuntimeBundle,
                        result
                    )
                }
                "stop" -> bridge.stop(result)
                "isRunning" -> result.success(bridge.isRunning())
                "getInstalledApps" -> result.success(listInstalledApps())
                "testLatency" -> {
                    val server  = call.argument<String>("server") ?: ""
                    val port    = call.argument<Int>("port") ?: 443
                    bridge.testLatency(server, port, result)
                }
                "getStatus" -> result.success(bridge.getStatusMap())
                "getPrivateDnsConfig" -> result.success(getPrivateDnsConfig())
                "getAppDir" -> result.success(applicationContext.filesDir.absolutePath)
                else -> result.notImplemented()
            }
        }

        // Status event channel — streams status updates to Flutter
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            STATUS_CHANNEL
        ).setStreamHandler(bridge.eventStreamHandler)
    }

    // ── VPN permission flow ──────────────────────────────────────────────────

    fun requestVpnPermissionAndStart(
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
        result: MethodChannel.Result
    ) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            // Permission already granted
            bridge.startService(
                sessionId,
                configJson,
                splitMode,
                packageNames,
                privateDnsServer,
                privateDnsHostname,
                notificationRegion,
                connectionMode,
                offlineDeblockSettings,
                offlineDeblockRuntimeBundle,
                result
            )
            return
        }

        if (bridge.pendingResult != null || pendingConfig != null) {
            result.error(
                "VPN_PERMISSION_IN_PROGRESS",
                "VPN permission request already in progress",
                null
            )
            return
        }

        pendingConfig = PendingVpnConfig(
            sessionId,
            configJson,
            splitMode,
            packageNames,
            privateDnsServer,
            privateDnsHostname,
            notificationRegion,
            connectionMode,
            offlineDeblockSettings,
            offlineDeblockRuntimeBundle,
        )
        bridge.pendingResult = result
        permissionHandler.removeCallbacks(permissionTimeoutRunnable)
        permissionHandler.postDelayed(permissionTimeoutRunnable, 30_000)
        vpnPermissionLauncher.launch(intent)
    }

    private fun handleVpnPermissionResult(resultCode: Int) {
        permissionHandler.removeCallbacks(permissionTimeoutRunnable)
        val config = pendingConfig
        pendingConfig = null

        if (resultCode == RESULT_OK) {
            if (config != null) {
                bridge.startService(
                    config.sessionId,
                    config.config,
                    config.splitMode,
                    config.packageNames,
                    config.privateDnsServer,
                    config.privateDnsHostname,
                    config.notificationRegion,
                    config.connectionMode,
                    config.offlineDeblockSettings,
                    config.offlineDeblockRuntimeBundle,
                    bridge.pendingResult
                )
            } else {
                bridge.pendingResult?.error(
                    "CONFIG_LOST",
                    "Pending config lost during activity result",
                    null
                )
            }
        } else {
            bridge.pendingResult?.error(
                "VPN_PERMISSION_DENIED",
                "User denied VPN permission",
                null
            )
        }

        bridge.pendingResult = null
    }


    private fun listInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        return pm.getInstalledApplications(PackageManager.GET_META_DATA)
            .asSequence()
            .filter { it.packageName != packageName }
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null }
            .map { app ->
                val label = pm.getApplicationLabel(app).toString().ifBlank { app.packageName }
                mapOf(
                    "packageName" to app.packageName,
                    "label" to label,
                    "systemApp" to ((app.flags and ApplicationInfo.FLAG_SYSTEM) != 0)
                )
            }
            .sortedBy { (it["label"] as String).lowercase() }
            .toList()
    }

    private fun getPrivateDnsConfig(): Map<String, String> {
        val resolver = contentResolver
        val mode = Settings.Global.getString(resolver, "private_dns_mode") ?: ""
        val specifier = Settings.Global.getString(resolver, "private_dns_specifier") ?: ""
        return mapOf(
            "mode" to mode,
            "specifier" to specifier,
        )
    }

    private fun ensureNotificationsPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationsPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    override fun onDestroy() {
        permissionHandler.removeCallbacks(permissionTimeoutRunnable)
        super.onDestroy()
    }
}
