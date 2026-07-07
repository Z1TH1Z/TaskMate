package com.taskmate.taskmate

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts a MethodChannel that lets the Dart side open the system ringtone picker
 * (TYPE_ALL → alarms, ringtones, notifications and any audio on the device, so
 * the user can pick "any ringtone they want"). The picker returns a content://
 * URI that the OS can read directly, which is what flutter_local_notifications
 * needs for a custom notification/alarm channel sound — far more reliable than
 * copying a file and handing the system a file:// path it can't read.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "taskmate/ringtone"
    private val pickRequestCode = 4711
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickRingtone" -> openPicker(call.argument<String>("currentUri"), result)
                    "ringtoneTitle" -> {
                        val uri = call.argument<String>("uri")
                        result.success(titleFor(uri))
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskmate/alarm")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "schedule" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val trigger = (call.argument<Number>("triggerAtMillis"))?.toLong() ?: 0L
                        val label = call.argument<String>("label") ?: "Alarm"
                        val recurrence = call.argument<String>("recurrence") ?: "none"
                        AlarmScheduler.schedule(this, id, trigger, label, recurrence)
                        result.success(true)
                    }
                    "cancel" -> {
                        val id = call.argument<Int>("id") ?: 0
                        AlarmScheduler.cancel(this, id)
                        result.success(true)
                    }
                    "rescheduleAll" -> {
                        AlarmScheduler.rescheduleAll(this)
                        result.success(true)
                    }
                    "scheduledIds" -> result.success(AlarmScheduler.scheduledIds(this))
                    else -> result.notImplemented()
                }
            }
    }

    private fun openPicker(currentUri: String?, result: MethodChannel.Result) {
        // Only one pick can be in flight at a time.
        pendingResult?.success(null)
        pendingResult = result

        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE, RingtoneManager.TYPE_ALL)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "Select alarm sound")
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_DEFAULT_URI,
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            )
            if (currentUri != null && currentUri.isNotEmpty()) {
                putExtra(
                    RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                    Uri.parse(currentUri)
                )
            }
        }
        startActivityForResult(intent, pickRequestCode)
    }

    private fun titleFor(uri: String?): String? {
        if (uri.isNullOrEmpty()) return null
        return try {
            RingtoneManager.getRingtone(this, Uri.parse(uri))?.getTitle(this)
        } catch (e: Exception) {
            null
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRequestCode) return
        val result = pendingResult ?: return
        pendingResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(null) // user cancelled — keep existing selection
            return
        }
        val uri: Uri? = data?.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
        if (uri == null) {
            result.success(null)
            return
        }
        val map = HashMap<String, String?>()
        map["uri"] = uri.toString()
        map["title"] = titleFor(uri.toString())
        result.success(map)
    }
}
