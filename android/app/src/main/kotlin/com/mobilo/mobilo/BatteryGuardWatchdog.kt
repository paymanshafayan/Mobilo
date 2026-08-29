package com.mobilo.mobilo

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock

/**
 * Best-effort self-healing for the guardian service.
 *
 * Some systems stop long-running foreground services (for example Android 16
 * enforces a time limit on dataSync services, and aggressive OEM battery
 * savers kill services in Doze). This inexact repeating alarm (no special
 * permissions required) restarts the service if it is not running.
 *
 * Note: on Android 12+ the OS may still block a background FGS start in some
 * edge cases; in that scenario the app UI shows the off state so the user
 * can start monitoring with one tap.
 */
class BatteryGuardWatchdog : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == ACTION_WATCHDOG) {
            runCatching {
                if (!BatteryGuardService.isRunning) {
                    BatteryGuardService.start(context)
                }
            }
        }
    }

    companion object {
        const val ACTION_WATCHDOG = "com.mobilo.mobilo.action.WATCHDOG"

        private const val INTERVAL_MS = 30 * 60 * 1000L

        fun schedule(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            try {
                val am =
                    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.setInexactRepeating(
                    AlarmManager.ELAPSED_REALTIME,
                    SystemClock.elapsedRealtime() + INTERVAL_MS,
                    INTERVAL_MS,
                    pendingIntent(context)
                )
            } catch (e: Exception) {
                // Scheduling is best-effort only.
            }
        }

        fun cancel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
            try {
                val am =
                    context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                am.cancel(pendingIntent(context))
            } catch (e: Exception) {
                // Nothing to do.
            }
        }

        private fun pendingIntent(context: Context): PendingIntent =
            PendingIntent.getBroadcast(
                context,
                0,
                Intent(context, BatteryGuardWatchdog::class.java)
                    .setAction(ACTION_WATCHDOG),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
    }
}
