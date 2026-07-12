package com.taskmate.taskmate

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager

/**
 * Keeps the alarm ringing (looping ringtone + continuous vibration) until the
 * user dismisses it — even if the phone is in active use and the full-screen UI
 * is only shown as a heads-up. This is the "rings till dismissed" behaviour of a
 * normal alarm, done with our own MediaPlayer instead of an insistent
 * notification (no notification spam).
 */
class AlarmForegroundService : Service() {
    companion object {
        const val ACTION_STOP = "com.taskmate.ALARM_STOP"
        const val ACTION_SNOOZE = "com.taskmate.ALARM_SNOOZE"
        const val SNOOZE_MINUTES = 10
        // Give up ringing after this long so a missed alarm can never ring forever.
        const val AUTO_STOP_MINUTES = 5
        private const val CHANNEL_ID = "taskmate_alarm_fullscreen"
        private const val NOTIF_ID = 424242
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentId: Int = 0
    private var currentLabel: String = "Alarm"
    private var ringing = false
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private val autoStop = Runnable { stopAlarm() }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_NOT_STICKY means we should never be restarted with a null intent,
        // but guard anyway: a null/unknown restart must not resurrect a ghost alarm.
        if (intent == null) { stopAlarm(); return START_NOT_STICKY }

        when (intent.action) {
            ACTION_STOP -> { stopAlarm(); return START_NOT_STICKY }
            ACTION_SNOOZE -> {
                val id = intent.getIntExtra(AlarmScheduler.EXTRA_ID, currentId)
                val label = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: currentLabel
                snooze(id, label)
                return START_NOT_STICKY
            }
        }

        currentId = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
        currentLabel = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm"

        startForeground(NOTIF_ID, buildNotification(currentLabel))

        // Already ringing (a second fire hit the same service instance): just refresh
        // the notification/UI — do NOT start a second MediaPlayer/vibration, or the
        // first one leaks with no reference and can never be stopped.
        if (ringing) {
            launchAlarmActivity(currentId, currentLabel)
            return START_NOT_STICKY
        }
        ringing = true

        acquireWakeLock()
        startSound()
        startVibration()
        launchAlarmActivity(currentId, currentLabel)
        timeoutHandler.postDelayed(autoStop, AUTO_STOP_MINUTES * 60_000L)
        return START_NOT_STICKY
    }

    private fun buildNotification(label: String): Notification {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Alarm", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Active alarm"
                setSound(null, null) // we play audio ourselves
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreen = Intent(this, AlarmActivity::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ID, currentId)
            putExtra(AlarmScheduler.EXTRA_LABEL, label)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, currentId, fullScreen,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val dismissPi = PendingIntent.getService(
            this, currentId * 31 + 1,
            Intent(this, AlarmForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val snoozePi = PendingIntent.getService(
            this, currentId * 31 + 2,
            Intent(this, AlarmForegroundService::class.java)
                .setAction(ACTION_SNOOZE)
                .putExtra(AlarmScheduler.EXTRA_ID, currentId)
                .putExtra(AlarmScheduler.EXTRA_LABEL, label),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID) else Notification.Builder(this)

        return builder
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(label)
            .setContentText("Alarm")
            .setCategory(Notification.CATEGORY_ALARM)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPi, true)
            .setContentIntent(fullScreenPi)
            .addAction(0, "Snooze", snoozePi)
            .addAction(0, "Dismiss", dismissPi)
            .build()
    }

    private fun startSound() {
        // Never leave an old player behind — a leaked looping MediaPlayer can't be stopped.
        try { player?.stop(); player?.release() } catch (_: Exception) {}
        player = null
        val uriStr = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .getString("flutter.alarm_sound_uri", null)
        val soundUri: Uri = if (!uriStr.isNullOrEmpty()) {
            Uri.parse(uriStr)
        } else {
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        }
        try {
            player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                setDataSource(this@AlarmForegroundService, soundUri)
                isLooping = true
                prepare()
                start()
            }
        } catch (e: Exception) {
            // Fall back to the default alarm tone if the custom URI fails.
            try {
                player = MediaPlayer.create(
                    this, RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                )?.apply { isLooping = true; start() }
            } catch (_: Exception) {}
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 1000, 1000)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK, "taskmate:alarm"
        ).apply { acquire(5 * 60 * 1000L) }
    }

    private fun launchAlarmActivity(id: Int, label: String) {
        val intent = Intent(this, AlarmActivity::class.java).apply {
            putExtra(AlarmScheduler.EXTRA_ID, id)
            putExtra(AlarmScheduler.EXTRA_LABEL, label)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        try { startActivity(intent) } catch (_: Exception) {}
    }

    private fun snooze(id: Int, label: String) {
        // Re-arm with a distinct id so it doesn't clobber a recurring alarm entry.
        val snoozeId = id xor 0x40000000.toInt()
        val trigger = System.currentTimeMillis() + SNOOZE_MINUTES * 60_000L
        AlarmScheduler.schedule(this, snoozeId, trigger, label, "none")
        stopAlarm()
    }

    private fun stopAlarm() {
        ringing = false
        timeoutHandler.removeCallbacks(autoStop)
        try { player?.stop(); player?.release() } catch (_: Exception) {}
        player = null
        vibrator?.cancel()
        vibrator = null
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        super.onDestroy()
        timeoutHandler.removeCallbacks(autoStop)
        try { player?.release() } catch (_: Exception) {}
        vibrator?.cancel()
        try { if (wakeLock?.isHeld == true) wakeLock?.release() } catch (_: Exception) {}
    }
}
