package com.taskmate.taskmate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * Fires when an alarm's time arrives. Starts the foreground service that rings
 * and shows the full-screen alarm, then re-arms the next occurrence for
 * recurring alarms (or forgets one-shots).
 */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
        val label = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm"
        val recurrence = intent.getStringExtra(AlarmScheduler.EXTRA_RECURRENCE) ?: "none"

        val serviceIntent = Intent(context, AlarmForegroundService::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL, label)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }

        // Re-arm recurring alarms for their next day; drop one-shots from the store.
        if (recurrence != "none") {
            val next = AlarmScheduler.nextOccurrence(System.currentTimeMillis(), recurrence)
            AlarmScheduler.schedule(context, id, next, label, recurrence)
        } else {
            AlarmScheduler.removeSpec(context, id)
        }
    }
}
