package com.sota.hexdecensor

import android.content.Intent
import android.os.Build
import android.app.ActivityManager
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

class QuickToggleTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()

        if (isVpnActive()) {
            stopVpnFromTile()
            updateTileState(activating = false)
            return
        }

        if (startVpnFromCache()) {
            updateTileState(activating = true)
            return
        }

        // If no cached profile/config exists, open the app so user can connect once.
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pending = android.app.PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(launchIntent)
        }
    }

    private fun startVpnFromCache(): Boolean {
        val prefs = PrefsHelper.getEncryptedPrefs(this, HexVpnService.QUICK_TOGGLE_PREFS)
        val config = prefs.getString(HexVpnService.QUICK_TOGGLE_CONFIG, null)
        if (config.isNullOrBlank()) {
            return false
        }

        val splitMode = prefs.getString(HexVpnService.QUICK_TOGGLE_SPLIT_MODE, "off") ?: "off"
        val packageList = prefs.getStringSet(HexVpnService.QUICK_TOGGLE_PACKAGE_LIST, emptySet())
            ?.toList()
            ?: emptyList()
        val dnsServer = prefs.getString(HexVpnService.QUICK_TOGGLE_DNS_SERVER, null)
        val dnsHostname = prefs.getString(HexVpnService.QUICK_TOGGLE_DNS_HOSTNAME, null)
        val notificationRegion = prefs.getString(HexVpnService.QUICK_TOGGLE_NOTIFICATION_REGION, null)
        val connectionMode = prefs.getString(HexVpnService.QUICK_TOGGLE_CONNECTION_MODE, "tunnel") ?: "tunnel"
        val offlineDeblockSettings =
            prefs.getString(HexVpnService.QUICK_TOGGLE_OFFLINE_DEBLOCK_SETTINGS, null)
        val offlineDeblockBundle =
            prefs.getString(HexVpnService.QUICK_TOGGLE_OFFLINE_DEBLOCK_RUNTIME_BUNDLE, null)

        val intent = Intent(this, HexVpnService::class.java).apply {
            action = HexVpnService.ACTION_START
            putExtra(HexVpnService.EXTRA_SESSION_ID, "tile-${System.currentTimeMillis()}")
            putExtra(HexVpnService.EXTRA_CONFIG, config)
            putExtra(HexVpnService.EXTRA_SPLIT_MODE, splitMode)
            putStringArrayListExtra(HexVpnService.EXTRA_PACKAGE_LIST, ArrayList(packageList))
            putExtra(HexVpnService.EXTRA_DNS_SERVER, dnsServer)
            putExtra(HexVpnService.EXTRA_DNS_HOSTNAME, dnsHostname)
            putExtra(HexVpnService.EXTRA_NOTIFICATION_REGION, notificationRegion)
            putExtra(HexVpnService.EXTRA_CONNECTION_MODE, connectionMode)
            putExtra(HexVpnService.EXTRA_OFFLINE_DEBLOCK_SETTINGS, offlineDeblockSettings)
            putExtra(HexVpnService.EXTRA_OFFLINE_DEBLOCK_RUNTIME_BUNDLE, offlineDeblockBundle)
        }
        startForegroundService(intent)
        return true
    }

    private fun stopVpnFromTile() {
        val intent = Intent(this, HexVpnService::class.java).apply {
            action = HexVpnService.ACTION_STOP
        }
        startForegroundService(intent)
    }

    private fun isVpnActive(): Boolean {
        @Suppress("DEPRECATION")
        val running = (getSystemService(ACTIVITY_SERVICE) as ActivityManager)
            .getRunningServices(Int.MAX_VALUE)
            .any { it.service.className == HexVpnService::class.java.name }
        if (running) {
            return true
        }

        val status = PrefsHelper.getEncryptedPrefs(this, HexVpnService.QUICK_TOGGLE_PREFS)
            .getString(HexVpnService.QUICK_TOGGLE_LAST_STATUS, "stopped")
            ?: "stopped"
        return status == "connected" || status == "connecting"
    }

    private fun updateTileState(activating: Boolean? = null) {
        val tile = qsTile ?: return
        val active = activating ?: isVpnActive()
        tile.label = getString(R.string.tile_label)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = getTileSubtitle(active)
        }
        tile.icon = android.graphics.drawable.Icon.createWithResource(this, R.drawable.ic_qs_hex)
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.updateTile()
    }

    private fun getTileSubtitle(active: Boolean): String {
        if (!active) {
            return getString(R.string.tile_subtitle_off)
        }
        val region = PrefsHelper.getEncryptedPrefs(this, HexVpnService.QUICK_TOGGLE_PREFS)
            .getString(HexVpnService.QUICK_TOGGLE_LAST_REGION, null)
            ?.trim()
            .orEmpty()
        return if (region.isNotEmpty()) {
            region
        } else {
            getString(R.string.tile_subtitle_on)
        }
    }
}
