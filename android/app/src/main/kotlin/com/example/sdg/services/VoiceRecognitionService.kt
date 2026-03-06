package com.example.sdg.services

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log
import android.widget.Toast
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.*

/**
 * Foreground service that runs speech recognition via Android SpeechRecognizer API.
 * Activated only when user explicitly triggers via overlay button, Quick Settings tile,
 * or long-press inside the app (no passive listening = reduces false triggers).
 */
class VoiceRecognitionService : Service() {

    companion object {
        const val TAG = "VoiceRecognitionSvc"
        const val CHANNEL_ID = "smartaid_voice_channel"
        const val NOTIFICATION_ID = 9001
        const val ACTION_START = "com.example.sdg.ACTION_START_VOICE"
        const val ACTION_STOP = "com.example.sdg.ACTION_STOP_VOICE"

        var isRunning = false
            private set

        var onResultCallback: ((Map<String, Any>) -> Unit)? = null
        var onStatusCallback: ((String) -> Unit)? = null
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var wakeLock: PowerManager.WakeLock? = null
    private var isListening = false
    private var retryCount = 0
    private val maxRetries = 3

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                startForegroundNotification()
                acquireWakeLock()
                startListening()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        isListening = false
        stopListening()
        releaseWakeLock()
        serviceScope.cancel()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SmartAid Voice Emergency",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active when voice emergency detection is running"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val stopIntent = Intent(this, VoiceRecognitionService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Open app when notification tapped
        val openIntent = packageManager.getLaunchIntentForPackage(packageName)
        val openPendingIntent = PendingIntent.getActivity(
            this, 1, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SmartAid Voice Emergency")
            .setContentText("Listening for emergency commands...")
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setOngoing(true)
            .setContentIntent(openPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop", stopPendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID, notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isRunning = true
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "SmartAid::VoiceRecognition"
        ).apply {
            acquire(5 * 60 * 1000L) // 5 min max
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) it.release()
        }
        wakeLock = null
    }

    private fun startListening() {
        if (isListening) return

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            Log.e(TAG, "Speech recognition not available on this device")
            onStatusCallback?.invoke("Speech recognition not available")
            showToast("Speech recognition unavailable")
            stopSelf()
            return
        }

        isListening = true
        retryCount = 0
        onStatusCallback?.invoke("LISTENING")

        startSpeechRecognizer()
    }

    private fun startSpeechRecognizer() {
        // Must create on main thread
        Handler(Looper.getMainLooper()).post {
            try {
                speechRecognizer?.destroy()
                speechRecognizer = SpeechRecognizer.createSpeechRecognizer(this)
                speechRecognizer?.setRecognitionListener(recognitionListener)

                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 3000)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 2000)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 2000)
                }

                speechRecognizer?.startListening(intent)
                Log.d(TAG, "Speech recognizer started")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting speech recognizer", e)
                handleRecognitionEnd()
            }
        }
    }

    private val recognitionListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            Log.d(TAG, "Ready for speech")
            onStatusCallback?.invoke("LISTENING")
        }

        override fun onBeginningOfSpeech() {
            Log.d(TAG, "Speech started")
            onStatusCallback?.invoke("HEARING_SPEECH")
        }

        override fun onRmsChanged(rmsdB: Float) {}

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() {
            Log.d(TAG, "Speech ended")
            onStatusCallback?.invoke("PROCESSING")
        }

        override fun onError(error: Int) {
            val errorMsg = when (error) {
                SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected"
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Speech timeout"
                SpeechRecognizer.ERROR_AUDIO -> "Audio error"
                SpeechRecognizer.ERROR_CLIENT -> "Client error"
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Permission denied"
                SpeechRecognizer.ERROR_NETWORK -> "Network error"
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                SpeechRecognizer.ERROR_SERVER -> "Server error"
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                else -> "Unknown error ($error)"
            }
            Log.w(TAG, "Recognition error: $errorMsg")

            // Retry for timeout/no-match errors (user didn't speak yet)
            if (error == SpeechRecognizer.ERROR_NO_MATCH ||
                error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT) {
                handleRecognitionEnd()
            } else {
                onStatusCallback?.invoke("ERROR: $errorMsg")
                handleRecognitionEnd()
            }
        }

        override fun onResults(results: Bundle?) {
            val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = matches?.firstOrNull() ?: ""
            Log.d(TAG, "Final result: $text")

            if (text.isNotBlank()) {
                retryCount = 0 // Reset on successful recognition
                processResult(text)
            } else {
                handleRecognitionEnd()
            }
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
            val text = matches?.firstOrNull() ?: ""
            if (text.isNotBlank()) {
                Log.d(TAG, "Partial: $text")
                onStatusCallback?.invoke("HEARING: $text")

                // Check emergency keywords in partial results for faster response
                val keyword = EmergencyAlertManager.detectEmergencyKeyword(text)
                if (keyword != null) {
                    Log.d(TAG, "Emergency keyword in partial result! Keyword: $keyword")
                    // Don't wait for final - process immediately
                    stopListening()
                    processResult(text)
                }
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun processResult(text: String) {
        serviceScope.launch {
            onStatusCallback?.invoke("ANALYZING: $text")

            val result = EmergencyAlertManager.handleEmergencySpeech(this@VoiceRecognitionService, text)
            val isEmergency = result["emergency"] as? Boolean ?: false

            if (isEmergency) {
                val alertSent = result["alert_sent"] as? Boolean ?: false
                val keyword = result["keyword"] as? String ?: "unknown"

                // Update notification 
                updateNotification("Emergency detected: \"$keyword\" — ${if (alertSent) "Alert sent!" else "Sending..."}")
                onStatusCallback?.invoke("EMERGENCY_DETECTED")
                onResultCallback?.invoke(result)

                showToast("🚨 Emergency SOS sent!")

                // Stay alive briefly then stop
                delay(3000)
                stopSelf()
            } else {
                onStatusCallback?.invoke("NO_EMERGENCY: $text")
                onResultCallback?.invoke(result)

                // Continue listening for more commands
                handleRecognitionEnd()
            }
        }
    }

    private fun handleRecognitionEnd() {
        if (!isRunning) return

        retryCount++
        if (retryCount > maxRetries) {
            Log.d(TAG, "Max retries reached, stopping")
            onStatusCallback?.invoke("STOPPED")
            showToast("Voice listening ended")
            stopSelf()
            return
        }

        // Restart after short delay
        Handler(Looper.getMainLooper()).postDelayed({
            if (isRunning) {
                startSpeechRecognizer()
            }
        }, 500)
    }

    private fun stopListening() {
        isListening = false
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.cancel()
            speechRecognizer?.destroy()
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping recognizer", e)
        }
        speechRecognizer = null
    }

    private fun updateNotification(text: String) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SmartAid Emergency")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, notification)
    }

    private fun showToast(msg: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this@VoiceRecognitionService, msg, Toast.LENGTH_LONG).show()
        }
    }
}
