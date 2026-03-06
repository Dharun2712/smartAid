package com.example.sdg.services

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import kotlinx.coroutines.*
import org.json.JSONObject
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/**
 * Central manager for emergency alert workflow:
 * 1. Detects emergency keywords from speech text
 * 2. Obtains GPS location via FusedLocationProviderClient
 * 3. Sends alert to SmartAid backend
 */
object EmergencyAlertManager {

    private const val TAG = "EmergencyAlertManager"
    private const val BACKEND_URL = "http://20.47.72.43:8000"

    // Emergency keywords that trigger SOS
    private val emergencyKeywords = listOf(
        "help", "accident", "ambulance", "emergency",
        "medical", "injured", "hurt", "bleeding",
        "unconscious", "crash", "fire", "sos",
        "save me", "need doctor", "call ambulance",
        "send help", "heart attack", "stroke", "choking"
    )

    /**
     * Check if the transcribed text contains any emergency keyword.
     * Returns the matched keyword or null.
     */
    fun detectEmergencyKeyword(text: String): String? {
        val lower = text.lowercase().trim()
        return emergencyKeywords.firstOrNull { lower.contains(it) }
    }

    /**
     * Get current GPS location using FusedLocationProviderClient.
     * Returns Location or null if unavailable.
     */
    suspend fun getCurrentLocation(context: Context): Location? = withContext(Dispatchers.Main) {
        if (ActivityCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION)
            != PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Location permission not granted")
            return@withContext null
        }

        val client = LocationServices.getFusedLocationProviderClient(context)

        return@withContext suspendCancellableCoroutine { cont ->
            // Try last known first
            client.lastLocation.addOnSuccessListener { location ->
                if (location != null) {
                    cont.resume(location) {}
                } else {
                    // Request a fresh location
                    val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000)
                        .setMaxUpdates(1)
                        .setWaitForAccurateLocation(false)
                        .setMaxUpdateDelayMillis(5000)
                        .build()

                    val callback = object : LocationCallback() {
                        override fun onLocationResult(result: LocationResult) {
                            client.removeLocationUpdates(this)
                            cont.resume(result.lastLocation) {}
                        }
                    }

                    try {
                        client.requestLocationUpdates(request, callback, Looper.getMainLooper())
                    } catch (e: SecurityException) {
                        Log.e(TAG, "SecurityException requesting location", e)
                        cont.resume(null) {}
                    }

                    cont.invokeOnCancellation {
                        client.removeLocationUpdates(callback)
                    }
                }
            }.addOnFailureListener {
                Log.e(TAG, "Failed to get last location", it)
                cont.resume(null) {}
            }
        }
    }

    /**
     * Send an emergency alert to the SmartAid backend.
     * Runs on IO dispatcher.
     */
    suspend fun sendEmergencyAlert(
        context: Context,
        latitude: Double,
        longitude: Double,
        spokenText: String,
        keyword: String
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            // Get auth token from shared prefs (stored by MainActivity when Flutter starts native services)
            val prefs = context.getSharedPreferences("smartaid_native", Context.MODE_PRIVATE)
            val token = prefs.getString("auth_token", null)

            val url = URL("$BACKEND_URL/api/client/sos")
            val conn = url.openConnection() as HttpURLConnection
            conn.requestMethod = "POST"
            conn.setRequestProperty("Content-Type", "application/json")
            conn.connectTimeout = 15000
            conn.readTimeout = 15000
            conn.doOutput = true

            if (token != null) {
                conn.setRequestProperty("Authorization", "Bearer $token")
            }

            val body = JSONObject().apply {
                put("location", JSONObject().apply {
                    put("lat", latitude)
                    put("lng", longitude)
                })
                put("condition", "voice_emergency: $spokenText")
                put("preliminary_severity", "high")
                put("auto_triggered", true)
                put("sensor_data", JSONObject().apply {
                    put("trigger_type", "native_voice_activation")
                    put("spoken_text", spokenText)
                    put("matched_keyword", keyword)
                    put("source", "android_native")
                })
                put("contact", "")
            }

            val writer = OutputStreamWriter(conn.outputStream)
            writer.write(body.toString())
            writer.flush()
            writer.close()

            val responseCode = conn.responseCode
            Log.d(TAG, "SOS alert sent, response: $responseCode")
            conn.disconnect()

            return@withContext responseCode in 200..299
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send emergency alert", e)
            return@withContext false
        }
    }

    /**
     * Full emergency workflow: detect keyword → get location → send alert.
     * Returns a result map for the UI.
     */
    suspend fun handleEmergencySpeech(
        context: Context,
        spokenText: String
    ): Map<String, Any> {
        val keyword = detectEmergencyKeyword(spokenText)
            ?: return mapOf(
                "emergency" to false,
                "text" to spokenText,
                "action" to "NONE"
            )

        Log.d(TAG, "Emergency keyword '$keyword' detected in: $spokenText")

        val location = getCurrentLocation(context)
        val lat = location?.latitude ?: 0.0
        val lng = location?.longitude ?: 0.0

        val sent = if (location != null) {
            sendEmergencyAlert(context, lat, lng, spokenText, keyword)
        } else {
            Log.w(TAG, "No location available, sending alert with 0,0")
            sendEmergencyAlert(context, 0.0, 0.0, spokenText, keyword)
        }

        return mapOf(
            "emergency" to true,
            "text" to spokenText,
            "keyword" to keyword,
            "latitude" to lat,
            "longitude" to lng,
            "alert_sent" to sent,
            "action" to "SEND_EMERGENCY_ALERT"
        )
    }
}
