package com.example.sdg.services

import android.content.Intent
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import android.widget.Toast

/**
 * Quick Settings Tile that appears in the Android notification quick panel.
 * When tapped, immediately starts the VoiceRecognitionService to listen
 * for emergency keywords. Works even when the app is not open.
 */
class SOSQuickSettingsTile : TileService() {

    companion object {
        const val TAG = "SOSQuickSettingsTile"
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        Log.d(TAG, "Quick Settings SOS tile tapped")

        unlockAndRun {
            if (VoiceRecognitionService.isRunning) {
                // Stop voice recognition
                val stopIntent = Intent(this, VoiceRecognitionService::class.java).apply {
                    action = VoiceRecognitionService.ACTION_STOP
                }
                startService(stopIntent)
                Toast.makeText(this, "Voice SOS stopped", Toast.LENGTH_SHORT).show()
            } else {
                // Start voice recognition
                val startIntent = Intent(this, VoiceRecognitionService::class.java).apply {
                    action = VoiceRecognitionService.ACTION_START
                }
                startForegroundService(startIntent)
                Toast.makeText(this, "🎤 SmartAid listening for emergency...", Toast.LENGTH_SHORT).show()
            }

            updateTileState()
        }
    }

    override fun onTileAdded() {
        super.onTileAdded()
        Log.d(TAG, "SOS tile added to Quick Settings")
        updateTileState()
    }

    override fun onTileRemoved() {
        super.onTileRemoved()
        Log.d(TAG, "SOS tile removed from Quick Settings")
    }

    private fun updateTileState() {
        val tile = qsTile ?: return

        if (VoiceRecognitionService.isRunning) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "SOS Active"
            tile.subtitle = "Listening..."
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "SmartAid SOS"
            tile.subtitle = "Tap to activate"
        }

        tile.updateTile()
    }
}
