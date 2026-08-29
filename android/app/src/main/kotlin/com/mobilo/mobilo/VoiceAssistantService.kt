package com.mobilo.mobilo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Mobina's wake-word listener.
 *
 * Runs as a foreground service (microphone type) so the listener survives
 * with the app closed. When the wake word («مبینا») is detected in a final
 * result, the command (everything after the wake word) is forwarded to Dart
 * over the `mobilo/voice_assistant` channel and the app is brought to the
 * foreground; Dart then executes the command (contacts lookup, web search,
 * ...). If the wake word arrives with no command yet, a notification invites
 * the user to speak ("بفرمایید").
 *
 * If the device has no usable speech recognizer, the service reports
 * status ok=false and exits; the Dart layer then falls back to its own
 * in-app listening loop.
 */
class VoiceAssistantService : Service() {

    companion object {
        const val ACTION_START = "mobilo.voice.start"
        const val ACTION_STOP = "mobilo.voice.stop"

        const val CHANNEL_NAME = "mobilo/voice_assistant"
        private const val CHANNEL_ID = "mobilo_voice"
        private const val NOTIF_ID = 3001
        private const val WAKE_NOTIF_ID = 3002

        /** Engine reference so we can call into Dart (set by MainActivity). */
        @Volatile
        var engine: FlutterEngine? = null

        /**
         * Commands captured while the Dart engine was unavailable (activity
         * destroyed). MainActivity forwards them to Dart on resume.
         */
        @Volatile
        var pendingCommand: String? = null

        fun messenger(): DartExecutor? = engine?.dartExecutor
    }

    private val handler = Handler(Looper.getMainLooper())
    private var recognizer: SpeechRecognizer? = null
    private var running = false
    private var retryCount = 0
    private var expectingCommand = false
    private var commandAttempts = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopListening()
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        createChannel()
        try {
            startForeground(NOTIF_ID, buildNotification("مبینا در حال گوش دادن است"))
        } catch (e: SecurityException) {
            // The microphone FGS type requires the RECORD_AUDIO runtime
            // permission. Report failure; the Dart side requests the
            // permission (via STT) and the next arm cycle retries.
            sendStatus(false)
            stopSelf()
            return START_NOT_STICKY
        }

        if (running) {
            return START_STICKY
        }

        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            sendStatus(false)
            stopSelf()
            return START_NOT_STICKY
        }

        running = true
        retryCount = 0
        expectingCommand = false
        commandAttempts = 0
        startRecognition()
        sendStatus(true)
        return START_STICKY
    }

    private fun startRecognition() {
        if (!running) return
        val sr = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer = sr
        sr.setRecognitionListener(object : RecognitionListener {
            override fun onReadyForSpeech(params: Bundle?) {}
            override fun onBeginningOfSpeech() {}
            override fun onRmsChanged(rmsdB: Float) {}
            override fun onBufferReceived(buffer: ByteArray?) {}
            override fun onEndOfSpeech() {
                scheduleNext()
            }

            override fun onError(error: Int) {
                scheduleNext()
            }

            override fun onResults(results: Bundle?) {
                val list =
                    results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                val text = list?.firstOrNull().orEmpty()
                handleUtterance(text)
            }

            override fun onPartialResults(partial: Bundle?) {}
            override fun onEvent(eventType: Int, params: Bundle?) {}
        })
        sr.listen(buildIntent())
    }

    /**
     * Called with the FINAL recognized utterance. Looks for the wake word;
     * the command is everything spoken after it.
     */
    private fun handleUtterance(text: String) {
        if (!running) return
        val lowered = text.lowercase()
        val wakeVariants = listOf("مبینا", "مبینا", "mobina")
        var best = -1
        var bestLen = 0
        for (v in wakeVariants) {
            val i = lowered.indexOf(v)
            if (i >= 0 && (best < 0 || i < best)) {
                best = i
                bestLen = v.length
            }
        }
        if (best < 0) {
            if (expectingCommand && commandAttempts < 3 && text.isNotBlank()) {
                // The user woke Mobina earlier and is now speaking the
                // command (without repeating the wake word).
                commandAttempts++
                expectingCommand = false
                sendCommand(text.trim())
                openApp()
                notifyWake("مبینا دریافت کرد: $text")
                scheduleNext()
                return
            }
            scheduleNext()
            return
        }
        val command = text.substring(best + bestLen).trim()
        if (command.isNotEmpty) {
            // Wake word + command in one breath: hand it to Dart and reopen
            // the app so the user sees what Mobina is doing.
            sendCommand(command)
            openApp()
            notifyWake("مبینا دریافت کرد: $command")
        } else {
            // Wake word only: invite the user to speak the command.
            expectingCommand = true
            commandAttempts = 0
            notifyWake("مبینا بیدار شد! بفرمایید 🎙")
        }
        scheduleNext()
    }

    private fun scheduleNext() {
        if (!running) return
        retryCount++
        if (retryCount > 200) {
            // Safety valve: give up after long failures (mic busy etc.).
            stopListening()
            stopForegroundCompat()
            stopSelf()
            return
        }
        handler.postDelayed({
            if (running) startRecognition()
        }, 600)
    }

    private fun stopListening() {
        running = false
        handler.removeCallbacksAndMessages(null)
        try {
            recognizer?.stopListening()
            recognizer?.destroy()
        } catch (_: Exception) {
        }
        recognizer = null
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun buildIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
        }

    // ------------------------------------------------------------------
    // Communication with Dart
    // ------------------------------------------------------------------

    private fun sendStatus(ok: Boolean) {
        try {
            MethodChannel(messenger()!!, CHANNEL_NAME)
                .invokeMethod("status", mapOf("ok" to ok))
        } catch (_: Exception) {
        }
    }

    private fun sendCommand(command: String) {
        try {
            MethodChannel(messenger()!!, CHANNEL_NAME)
                .invokeMethod("command", mapOf("text" to command))
        } catch (_: Exception) {
            pendingCommand = command
        }
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        }
        startActivity(intent)
    }

    // ------------------------------------------------------------------
    // Notifications
    // ------------------------------------------------------------------

    private fun createChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "دستیار صوتی مبینا",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "اعلان‌های دستیار صوتی مبینا"
            }
            nm.createNotificationChannel(channel)
        }
    }

    private fun baseBuilder(): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

    private fun buildNotification(text: String): Notification =
        baseBuilder()
            .setSmallIcon(R.drawable.ic_stat_battery)
            .setContentTitle("مبینا")
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .setContentIntent(openAppPendingIntent())
            .build()

    private fun notifyWake(text: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = baseBuilder()
            .setSmallIcon(R.drawable.ic_stat_battery)
            .setContentTitle("مبینا")
            .setContentText(text)
            .setOngoing(false)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_VOICE)
            .setContentIntent(openAppPendingIntent())
            .build()
        nm.notify(WAKE_NOTIF_ID, notification)
    }

    private fun openAppPendingIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            this,
            1,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}
