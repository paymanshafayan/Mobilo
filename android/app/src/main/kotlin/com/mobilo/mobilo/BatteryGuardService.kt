package com.mobilo.mobilo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel
import java.util.HashMap

/**
 * 24/7 battery guardian.
 *
 * Runs as a foreground service with a persistent notification that always
 * shows the current battery level. It polls the battery every 30 seconds
 * (plus event-driven checks when the charger is plugged/unplugged) and posts
 * loud local notifications when:
 *  - the battery drops to [LOW_THRESHOLD] % or below while not charging,
 *  - the battery reaches [FULL_THRESHOLD] % or above while charging
 *    (the user is asked to unplug the charger - no third-party app can
 *    physically stop charging on Android or iOS).
 *
 * Alert sessions repeat every [ALERT_REPEAT_MS] (2 minutes) until the user
 * taps "skip" - either the "اسکیپ اعلان" action on the notification, the
 * MethodChannel `dismissAlert` call from the app UI, or the condition is
 * resolved (charger plugged in / unplugged).
 */
class BatteryGuardService : Service() {

    companion object {
        private const val SERVICE_CHANNEL_ID = "battery_guard_service"
        private const val ALERT_CHANNEL_ID = "battery_guard_alerts"

        private const val SERVICE_NOTIFICATION_ID = 1001
        private const val LOW_BATTERY_NOTIFICATION_ID = 2001
        private const val FULL_BATTERY_NOTIFICATION_ID = 2002

        const val LOW_THRESHOLD = 15
        const val FULL_THRESHOLD = 95

        private const val POLL_INTERVAL_MS = 30_000L
        private const val WAKE_LOCK_TIMEOUT_MS = 5_000L
        private const val ALERT_REPEAT_MS = 120_000L
        private const val ACTION_STOP = "com.mobilo.mobilo.action.STOP"
        private const val ACTION_DISMISS_ALERT = "com.mobilo.mobilo.action.DISMISS_ALERT"

        @Volatile
        var isRunning = false
            private set

        /** Active alert session: "low", "full" or null. */
        @Volatile
        var activeAlert: String? = null
            private set

        @Volatile
        private var lastAlertPost: Long = 0

        @Volatile
        private var eventSink: EventChannel.EventSink? = null

        private val mainHandler = Handler(Looper.getMainLooper())

        fun start(context: Context) {
            activeAlert = null
            lastAlertPost = 0
            val intent = Intent(context, BatteryGuardService::class.java)
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, BatteryGuardService::class.java)
                .setAction(ACTION_STOP)
            ContextCompat.startForegroundService(context, intent)
        }

        fun dismissAlert(context: Context) {
            val intent = Intent(context, BatteryGuardService::class.java)
                .setAction(ACTION_DISMISS_ALERT)
            ContextCompat.startForegroundService(context, intent)
        }

        fun setEventSink(sink: EventChannel.EventSink?) {
            eventSink = sink
        }
    }

    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            checkBattery()
        }
    }

    private var pollThread: Thread? = null
    private var wakeLock: PowerManager.WakeLock? = null

    private var lastLevel: Int = -1
    private var lastCharging = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                clearAlert()
                BatteryGuardWatchdog.cancel(this)
                stopForegroundCompat()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_DISMISS_ALERT -> {
                clearAlert()
                emitEvent(lastLevel, lastCharging)
                return START_NOT_STICKY
            }
        }

        createChannels()
        val notification = buildServiceNotification(lastLevel, lastCharging)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                SERVICE_NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(SERVICE_NOTIFICATION_ID, notification)
        }

        isRunning = true

        try {
            registerReceiver(
                powerReceiver,
                IntentFilter().apply {
                    addAction(Intent.ACTION_POWER_CONNECTED)
                    addAction(Intent.ACTION_POWER_DISCONNECTED)
                }
            )
        } catch (e: Exception) {
            // Receiver already registered - safe to ignore.
        }

        startPollThread()
        BatteryGuardWatchdog.schedule(this)
        checkBattery()
        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        activeAlert = null
        try {
            unregisterReceiver(powerReceiver)
        } catch (e: Exception) {
            // Not registered - safe to ignore.
        }
        pollThread?.interrupt()
        withNotificationManager().cancel(SERVICE_NOTIFICATION_ID)
        super.onDestroy()
    }

    // ------------------------------------------------------------------
    // Battery reading + threshold / alert-session logic
    // ------------------------------------------------------------------

    @Synchronized
    private fun checkBattery() {
        val battery = readBattery()
        if (battery.first < 0) return
        val level = battery.first
        val charging = battery.second
        val now = SystemClock.elapsedRealtime()

        val lowCondition = !charging && level <= LOW_THRESHOLD
        val fullCondition = charging && level >= FULL_THRESHOLD
        val activeBefore = activeAlert

        // End sessions whose condition is gone (charger plugged/unplugged).
        if (activeAlert == "low" && !lowCondition) clearAlert()
        if (activeAlert == "full" && !fullCondition) clearAlert()

        // Start new sessions or repeat the active one every 2 minutes.
        when {
            lowCondition -> {
                if (activeAlert == null) {
                    activeAlert = "low"
                    lastAlertPost = now
                    showLowAlert(level)
                } else if (now - lastAlertPost >= ALERT_REPEAT_MS) {
                    lastAlertPost = now
                    showLowAlert(level)
                }
            }
            fullCondition -> {
                if (activeAlert == null) {
                    activeAlert = "full"
                    lastAlertPost = now
                    showFullAlert(level)
                } else if (now - lastAlertPost >= ALERT_REPEAT_MS) {
                    lastAlertPost = now
                    showFullAlert(level)
                }
            }
        }

        val levelChanged = level != lastLevel
        val chargingChanged = charging != lastCharging
        val alertChanged = activeAlert != activeBefore
        lastLevel = level
        lastCharging = charging

        updateServiceNotification(level, charging)
        if (levelChanged || chargingChanged || alertChanged) {
            emitEvent(level, charging)
        }
    }

    /** Ends the active alert session and removes its notifications. */
    private fun clearAlert() {
        if (activeAlert == null) return
        activeAlert = null
        lastAlertPost = 0
        val nm = withNotificationManager()
        nm.cancel(LOW_BATTERY_NOTIFICATION_ID)
        nm.cancel(FULL_BATTERY_NOTIFICATION_ID)
    }

    /** Reads the battery via the sticky ACTION_BATTERY_CHANGED broadcast. */
    private fun readBattery(): Pair<Int, Boolean> {
        val sticky: Intent? =
            registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        if (sticky == null) return Pair(-1, false)

        val level = sticky.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = sticky.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else -1

        val plugged = sticky.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)
        val charging =
            plugged != 0 && plugged != BatteryManager.BATTERY_PLUGGED_UNKNOWN
        return Pair(percent, charging)
    }

    private fun startPollThread() {
        if (pollThread?.isAlive == true) return
        val thread = Thread({
            while (isRunning) {
                try {
                    acquireWakeLock()
                    checkBattery()
                    SystemClock.sleep(POLL_INTERVAL_MS)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    // Never let an unexpected error kill the guardian.
                }
            }
        }, "mobilo-battery-guard")
        thread.isDaemon = true
        pollThread = thread
        thread.start()
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val lock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "mobilo:battery-guard"
            )
            lock.setReferenceCounted(false)
            lock.acquire(WAKE_LOCK_TIMEOUT_MS)
            wakeLock = lock
        } catch (e: SecurityException) {
            // WAKE_LOCK permission missing - polling still works, just slower.
        }
    }

    // ------------------------------------------------------------------
    // Notifications
    // ------------------------------------------------------------------

    private fun withNotificationManager(): NotificationManager =
        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun createChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = withNotificationManager()

        nm.createNotificationChannel(
            NotificationChannel(
                SERVICE_CHANNEL_ID,
                "نظارت باتری",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "نمایش زنده وضعیت باتری و کنترل نظارت"
                setShowBadge(false)
            }
        )

        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "اخطارهای باتری",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "اخطار باتری کم (۱۵٪) و اتمام شارژ (۹۵٪)"
                enableVibration(true)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
        )
    }

    private fun buildServiceNotification(level: Int, charging: Boolean): Notification {
        val text = when {
            level < 0 -> "نظارت باتری فعال است"
            charging -> "باتری: ${fa(level)}٪ • در حال شارژ"
            else -> "باتری: ${fa(level)}٪ • در حال مصرف"
        }
        return NotificationCompat.Builder(this, SERVICE_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_battery)
            .setContentTitle("Mobilo - نگهبان باتری")
            .setContentText(text)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setContentIntent(openAppIntent())
            .addAction(R.drawable.ic_stat_battery, "باز کردن", openAppIntent())
            .addAction(R.drawable.ic_stat_battery, "توقف نظارت", stopSelfIntent())
            .build()
    }

    private fun updateServiceNotification(level: Int, charging: Boolean) {
        withNotificationManager().notify(
            SERVICE_NOTIFICATION_ID,
            buildServiceNotification(level, charging)
        )
    }

    private fun showLowAlert(level: Int) {
        val text =
            "سطح باتری به ${fa(level)}٪ رسیده است. لطفاً گوشی را به شارژ وصل کنید. " +
                "(تا فشردن «اسکیپ»، هر ۲ دقیقه تکرار می‌شود)"
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_battery)
            .setContentTitle("⚠️ باتری رو به اتمام است")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_ALERT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppIntent())
            .addAction(R.drawable.ic_stat_battery, "اسکیپ اعلان", dismissAlertIntent())
            .build()
        withNotificationManager().notify(LOW_BATTERY_NOTIFICATION_ID, notification)
    }

    private fun showFullAlert(level: Int) {
        val text =
            "سطح باتری به ${fa(level)}٪ رسید. برای حفظ عمر باتری، شارژر را جدا کنید. " +
                "(تا فشردن «اسکیپ»، هر ۲ دقیقه تکرار می‌شود)"
        val notification = NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_battery)
            .setContentTitle("🔋 باتری شارژ کامل شد")
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setCategory(NotificationCompat.CATEGORY_ALERT)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openAppIntent())
            .addAction(R.drawable.ic_stat_battery, "اسکیپ اعلان", dismissAlertIntent())
            .build()
        withNotificationManager().notify(FULL_BATTERY_NOTIFICATION_ID, notification)
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun stopSelfIntent(): PendingIntent {
        val intent = Intent(this, BatteryGuardService::class.java)
            .setAction(ACTION_STOP)
        return PendingIntent.getService(
            this, 1, intent, PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun dismissAlertIntent(): PendingIntent {
        val intent = Intent(this, BatteryGuardService::class.java)
            .setAction(ACTION_DISMISS_ALERT)
        return PendingIntent.getService(
            this, 2, intent, PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun stopForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
    }

    private fun emitEvent(level: Int, charging: Boolean) {
        val map = HashMap<String, Any>()
        map["level"] = level
        map["charging"] = charging
        map["active"] = activeAlert ?: ""
        // EventSink must be used on the platform (main) thread.
        mainHandler.post {
            eventSink?.success(map)
        }
    }

    /** Converts ASCII digits to Persian digits. */
    private fun fa(value: Int): String = value.toString().map { c ->
        if (c in '0'..'9') ('۰' + (c - '0')) else c
    }
}
