package com.example.sdg.services

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.*
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat

/**
 * Service that displays a floating SOS overlay button on top of all other apps.
 * Tapping the button starts the VoiceRecognitionService for emergency keyword detection.
 * Can be dragged around the screen.
 */
class FloatingSOSService : Service() {

    companion object {
        const val TAG = "FloatingSOSService"
        const val CHANNEL_ID = "smartaid_overlay_channel"
        const val NOTIFICATION_ID = 9002

        var isRunning = false
            private set
    }

    private var windowManager: WindowManager? = null
    private var floatingView: View? = null
    private var statusView: View? = null
    private var layoutParams: WindowManager.LayoutParams? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == "STOP") {
            removeOverlay()
            stopSelf()
            return START_NOT_STICKY
        }

        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true
        createOverlay()
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isRunning = false
        removeOverlay()
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "SmartAid SOS Overlay",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Running when SOS floating button is active"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val stopIntent = Intent(this, FloatingSOSService::class.java).apply { action = "STOP" }
        val stopPending = PendingIntent.getService(
            this, 0, stopIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SmartAid SOS Button Active")
            .setContentText("Floating SOS button is ready")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Hide", stopPending)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .build()
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createOverlay() {
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        // === Build the SOS floating button ===
        val container = FrameLayout(this)
        val buttonSize = dpToPx(64)

        // Red circle background
        val circle = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#E53935")) // Red
            setStroke(dpToPx(2), Color.WHITE)
        }

        // SOS text
        val sosText = TextView(this).apply {
            text = "SOS"
            setTextColor(Color.WHITE)
            textSize = 14f
            gravity = Gravity.CENTER
            typeface = android.graphics.Typeface.DEFAULT_BOLD
            background = circle
            layoutParams = FrameLayout.LayoutParams(buttonSize, buttonSize)
        }

        container.addView(sosText)
        floatingView = container

        // Window layout params for overlay
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        layoutParams = WindowManager.LayoutParams(
            buttonSize,
            buttonSize,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = dpToPx(16)
            y = dpToPx(200)
        }

        windowManager?.addView(floatingView, layoutParams)

        // === Touch handling: drag + tap/long-press ===
        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f
        var isDragging = false
        var longPressTriggered = false

        val longPressHandler = android.os.Handler(mainLooper)
        val longPressRunnable = Runnable {
            longPressTriggered = true
            // Long press → activate voice recognition
            activateVoiceRecognition()
            pulseButton(sosText)
        }

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = layoutParams!!.x
                    initialY = layoutParams!!.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    longPressTriggered = false
                    longPressHandler.postDelayed(longPressRunnable, 600)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - initialTouchX).toInt()
                    val dy = (event.rawY - initialTouchY).toInt()

                    if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                        isDragging = true
                        longPressHandler.removeCallbacks(longPressRunnable)
                    }

                    if (isDragging) {
                        layoutParams!!.x = initialX + dx
                        layoutParams!!.y = initialY + dy
                        windowManager?.updateViewLayout(floatingView, layoutParams)
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    longPressHandler.removeCallbacks(longPressRunnable)
                    if (!isDragging && !longPressTriggered) {
                        // Single tap → activate voice recognition
                        activateVoiceRecognition()
                        pulseButton(sosText)
                    }
                    true
                }
                else -> false
            }
        }

        Log.d(TAG, "Floating SOS overlay created")
    }

    private fun activateVoiceRecognition() {
        Log.d(TAG, "SOS button pressed — activating voice recognition")
        Toast.makeText(this, "🎤 Speak your emergency...", Toast.LENGTH_SHORT).show()

        val intent = Intent(this, VoiceRecognitionService::class.java).apply {
            action = VoiceRecognitionService.ACTION_START
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun pulseButton(view: View) {
        // Visual feedback: scale up and back
        view.animate()
            .scaleX(1.3f).scaleY(1.3f)
            .setDuration(150)
            .withEndAction {
                view.animate().scaleX(1f).scaleY(1f).setDuration(150).start()
            }
            .start()
    }

    private fun removeOverlay() {
        try {
            floatingView?.let { windowManager?.removeView(it) }
            statusView?.let { windowManager?.removeView(it) }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing overlay", e)
        }
        floatingView = null
        statusView = null
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density).toInt()
    }
}
