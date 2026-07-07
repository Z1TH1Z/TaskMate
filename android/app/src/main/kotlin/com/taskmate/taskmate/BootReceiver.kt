package com.taskmate.taskmate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // Re-arm native alarms immediately (setAlarmClock doesn't survive a
            // reboot), so alarms fire even before the app is next opened.
            try { AlarmScheduler.rescheduleAll(context) } catch (e: Exception) {}

            // Flag reminders/recurring for Dart to re-check on next launch.
            val prefs: SharedPreferences = context.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            prefs.edit().putBoolean("flutter.boot_reschedule_needed", true).apply()
        }
    }
}
