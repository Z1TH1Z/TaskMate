package com.taskmate.taskmate

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import android.widget.TextView
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The full-screen alarm screen. Shows over the lock screen and turns the screen
 * on, displays the time + label, and offers Snooze / Dismiss. The ringing itself
 * is owned by AlarmForegroundService; the buttons just tell it to stop or snooze.
 */
class AlarmActivity : Activity() {
    private val clock = Handler(Looper.getMainLooper())
    private var alarmId: Int = 0
    private var label: String = "Alarm"

    private val tick = object : Runnable {
        override fun run() {
            findViewById<TextView>(R.id.alarm_time)?.text =
                SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())
            clock.postDelayed(this, 1000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        showWhenLockedAndTurnScreenOn()
        setContentView(R.layout.activity_alarm)

        alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ID, 0)
        label = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: "Alarm"

        findViewById<TextView>(R.id.alarm_label).text = label
        findViewById<android.widget.Button>(R.id.btn_dismiss).setOnClickListener { dismiss() }
        findViewById<android.widget.Button>(R.id.btn_snooze).setOnClickListener { snooze() }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        alarmId = intent.getIntExtra(AlarmScheduler.EXTRA_ID, alarmId)
        label = intent.getStringExtra(AlarmScheduler.EXTRA_LABEL) ?: label
        findViewById<TextView>(R.id.alarm_label)?.text = label
    }

    override fun onResume() {
        super.onResume()
        clock.post(tick)
    }

    override fun onPause() {
        super.onPause()
        clock.removeCallbacks(tick)
    }

    private fun showWhenLockedAndTurnScreenOn() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            (getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager)
                .requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun dismiss() {
        startService(
            Intent(this, AlarmForegroundService::class.java)
                .setAction(AlarmForegroundService.ACTION_STOP)
        )
        finish()
    }

    private fun snooze() {
        startService(
            Intent(this, AlarmForegroundService::class.java)
                .setAction(AlarmForegroundService.ACTION_SNOOZE)
                .putExtra(AlarmScheduler.EXTRA_ID, alarmId)
                .putExtra(AlarmScheduler.EXTRA_LABEL, label)
        )
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        clock.removeCallbacks(tick)
    }
}
