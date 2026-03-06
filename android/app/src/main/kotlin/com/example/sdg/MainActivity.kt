package com.example.sdg

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.widget.Toast
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.example.sdg.services.FloatingSOSService
import com.example.sdg.services.VoiceRecognitionService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main Activity bridging Flutter and Native Android emergency services.
 * Provides MethodChannel "com.smartaid.emergency" for Flutter to:
 *  - Request all permissions
 *  - Start/stop floating SOS overlay
 *  - Start/stop voice recognition
 *  - Check overlay permission status
 *  - Activate long-press voice SOS
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val TAG = "SmartAidMainActivity"
        const val CHANNEL = "com.smartaid.emergency"
        const val PERMISSION_REQUEST_CODE = 1001
        const val OVERLAY_REQUEST_CODE = 1002
    }

    private var methodChannel: MethodChannel? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermissions" -> {
                    requestAllPermissions(result)
                }
                "checkPermissions" -> {
                    result.success(checkAllPermissions())
                }
                "hasOverlayPermission" -> {
                    result.success(hasOverlayPermission())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "startFloatingButton" -> {
                    startFloatingButton(result)
                }
                "stopFloatingButton" -> {
                    stopFloatingButton(result)
                }
                "isFloatingButtonRunning" -> {
                    result.success(FloatingSOSService.isRunning)
                }
                "startVoiceRecognition" -> {
                    startVoiceRecognition(result)
                }
                "stopVoiceRecognition" -> {
                    stopVoiceRecognition(result)
                }
                "isVoiceRecognitionRunning" -> {
                    result.success(VoiceRecognitionService.isRunning)
                }
                "activateLongPressSOS" -> {
                    activateLongPressSOS(result)
                }
                "setAuthToken" -> {
                    val token = call.arguments as? String
                    com.example.sdg.services.EmergencyAlertManager.authToken =
                        if (!token.isNullOrBlank()) token else null
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Wire native callbacks back to Flutter
        VoiceRecognitionService.onResultCallback = { resultMap ->
            runOnUiThread {
                methodChannel?.invokeMethod("onVoiceResult", resultMap)
            }
        }

        VoiceRecognitionService.onStatusCallback = { status ->
            runOnUiThread {
                methodChannel?.invokeMethod("onVoiceStatus", status)
            }
        }
    }

    // === Permissions ===

    private fun checkAllPermissions(): Map<String, Boolean> {
        val perms = mutableMapOf<String, Boolean>()
        perms["microphone"] = ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        perms["fine_location"] = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        perms["coarse_location"] = ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        perms["overlay"] = hasOverlayPermission()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            perms["notifications"] = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        } else {
            perms["notifications"] = true
        }

        val runtimePermissionKeys = listOf("microphone", "fine_location", "coarse_location", "notifications")
        perms["all_granted"] = runtimePermissionKeys.all { key -> perms[key] == true }
        return perms
    }

    private fun requestAllPermissions(result: MethodChannel.Result) {
        pendingPermissionResult = result

        val permissions = mutableListOf(
            Manifest.permission.RECORD_AUDIO,
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (needed.isEmpty()) {
            pendingPermissionResult?.success(checkAllPermissions())
            pendingPermissionResult = null
        } else {
            ActivityCompat.requestPermissions(this, needed.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PERMISSION_REQUEST_CODE) {
            pendingPermissionResult?.success(checkAllPermissions())
            pendingPermissionResult = null
        }
    }

    private fun hasOverlayPermission(): Boolean {
        return Settings.canDrawOverlays(this)
    }

    private fun requestOverlayPermission() {
        if (!hasOverlayPermission()) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivityForResult(intent, OVERLAY_REQUEST_CODE)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OVERLAY_REQUEST_CODE) {
            val granted = hasOverlayPermission()
            methodChannel?.invokeMethod("onOverlayPermissionResult", granted)
            if (granted) {
                Toast.makeText(this, "Overlay permission granted!", Toast.LENGTH_SHORT).show()
            }
        }
    }

    // === Floating SOS Button ===

    private fun startFloatingButton(result: MethodChannel.Result) {
        if (!hasOverlayPermission()) {
            result.error("NO_OVERLAY_PERMISSION", "Overlay permission required", null)
            return
        }

        val intent = Intent(this, FloatingSOSService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
        Log.d(TAG, "Floating SOS button started")
    }

    private fun stopFloatingButton(result: MethodChannel.Result) {
        val intent = Intent(this, FloatingSOSService::class.java).apply { action = "STOP" }
        startService(intent)
        result.success(true)
    }

    // === Voice Recognition ===

    private fun startVoiceRecognition(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            result.error("NO_MIC_PERMISSION", "Microphone permission required", null)
            return
        }

        val intent = Intent(this, VoiceRecognitionService::class.java).apply {
            action = VoiceRecognitionService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }

    private fun stopVoiceRecognition(result: MethodChannel.Result) {
        val intent = Intent(this, VoiceRecognitionService::class.java).apply {
            action = VoiceRecognitionService.ACTION_STOP
        }
        startService(intent)
        result.success(true)
    }

    // === Long-press SOS ===

    private fun activateLongPressSOS(result: MethodChannel.Result) {
        Log.d(TAG, "Long-press SOS activated from Flutter")
        Toast.makeText(this, "SmartAid listening for emergency...", Toast.LENGTH_SHORT).show()

        val intent = Intent(this, VoiceRecognitionService::class.java).apply {
            action = VoiceRecognitionService.ACTION_START
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        result.success(true)
    }
}
