package com.mobilo.mobilo

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restarts the battery guardian after a reboot.
 *
 * Note: some aggressive OEM battery savers may block auto-start after boot;
 * the service can always be started again from the app itself.
 */
class BatteryGuardBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            runCatching {
                BatteryGuardService.start(context)
            }
        }
    }
}
