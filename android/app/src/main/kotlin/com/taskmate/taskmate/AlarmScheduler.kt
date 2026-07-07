package com.taskmate.taskmate

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Schedules alarms with AlarmManager.setAlarmClock — the real "alarm clock" API:
 * exact, exempt from Doze/battery saver, and shown by the system as a pending
 * alarm. Each alarm's spec is also persisted to SharedPreferences so it can be
 * re-armed after a reboot (setAlarmClock does not survive restarts).
 */
object AlarmScheduler {
    const val EXTRA_ID = "alarm_id"
    const val EXTRA_LABEL = "alarm_label"
    const val EXTRA_RECURRENCE = "alarm_recurrence"

    private const val PREFS = "FlutterSharedPreferences"
    private const val STORE_KEY = "flutter.native_alarms"

    fun schedule(ctx: Context, id: Int, triggerAt: Long, label: String, recurrence: String) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        val showIntent = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName)
        val showPi = PendingIntent.getActivity(
            ctx, id, showIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val info = AlarmManager.AlarmClockInfo(triggerAt, showPi)
        am.setAlarmClock(info, operationPi(ctx, id, label, recurrence))

        saveSpec(ctx, id, triggerAt, label, recurrence)
    }

    fun cancel(ctx: Context, id: Int) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        am.cancel(operationPi(ctx, id, "", "none"))
        removeSpec(ctx, id)
    }

    /** Re-arm every stored alarm (called after reboot). One-shots in the past are dropped. */
    fun rescheduleAll(ctx: Context) {
        val arr = readStore(ctx)
        val now = System.currentTimeMillis()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            val id = o.optInt("id")
            val label = o.optString("label")
            val recurrence = o.optString("recurrence", "none")
            var trigger = o.optLong("trigger")
            if (recurrence == "none") {
                if (trigger <= now) {
                    removeSpec(ctx, id)
                    continue
                }
            } else {
                // Roll a recurring alarm forward to its next valid occurrence.
                while (trigger <= now) trigger = nextOccurrence(trigger, recurrence)
            }
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val showPi = PendingIntent.getActivity(
                ctx, id, ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: Intent(),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            am.setAlarmClock(
                AlarmManager.AlarmClockInfo(trigger, showPi),
                operationPi(ctx, id, label, recurrence)
            )
            saveSpec(ctx, id, trigger, label, recurrence)
        }
    }

    /** Next day's trigger for a recurring alarm, skipping weekends when "weekdays". */
    fun nextOccurrence(fromTrigger: Long, recurrence: String): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = fromTrigger }
        do {
            cal.add(Calendar.DAY_OF_YEAR, 1)
        } while (recurrence == "weekdays" &&
            (cal.get(Calendar.DAY_OF_WEEK) == Calendar.SATURDAY ||
             cal.get(Calendar.DAY_OF_WEEK) == Calendar.SUNDAY))
        return cal.timeInMillis
    }

    private fun operationPi(ctx: Context, id: Int, label: String, recurrence: String): PendingIntent {
        val intent = Intent(ctx, AlarmReceiver::class.java).apply {
            action = "com.taskmate.ALARM_FIRE_$id"
            putExtra(EXTRA_ID, id)
            putExtra(EXTRA_LABEL, label)
            putExtra(EXTRA_RECURRENCE, recurrence)
        }
        return PendingIntent.getBroadcast(
            ctx, id, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // ---- persistence ----

    private fun prefs(ctx: Context) =
        ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun readStore(ctx: Context): JSONArray {
        val raw = prefs(ctx).getString(STORE_KEY, null) ?: return JSONArray()
        return try { JSONArray(raw) } catch (e: Exception) { JSONArray() }
    }

    private fun saveSpec(ctx: Context, id: Int, trigger: Long, label: String, recurrence: String) {
        val arr = readStore(ctx)
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optInt("id") != id) out.put(o)
        }
        out.put(JSONObject().apply {
            put("id", id)
            put("trigger", trigger)
            put("label", label)
            put("recurrence", recurrence)
        })
        prefs(ctx).edit().putString(STORE_KEY, out.toString()).apply()
    }

    /** Ids of every alarm still armed (used by Dart to retire fired one-shots). */
    fun scheduledIds(ctx: Context): List<Int> {
        val arr = readStore(ctx)
        val ids = ArrayList<Int>()
        for (i in 0 until arr.length()) {
            arr.optJSONObject(i)?.let { ids.add(it.optInt("id")) }
        }
        return ids
    }

    fun removeSpec(ctx: Context, id: Int) {
        val arr = readStore(ctx)
        val out = JSONArray()
        for (i in 0 until arr.length()) {
            val o = arr.optJSONObject(i) ?: continue
            if (o.optInt("id") != id) out.put(o)
        }
        prefs(ctx).edit().putString(STORE_KEY, out.toString()).apply()
    }
}
