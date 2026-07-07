package com.taskmate.taskmate

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin

class TaskMateWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.taskmate_widget)

            try {
                val widgetData = HomeWidgetPlugin.getData(context)
                val tasksToday = widgetData.getInt("tasks_today", 0)
                val nextAlarm = widgetData.getString("next_alarm", "--:--")
                val taskPreview = widgetData.getString("task_preview", "All clear today")
                val accentHex = widgetData.getString("accent_color", "#10B981")

                val accentColor = try {
                    Color.parseColor(accentHex)
                } catch (e: Exception) {
                    Color.parseColor("#10B981")
                }

                views.setTextViewText(R.id.widget_tasks_count, tasksToday.toString())
                views.setTextViewText(R.id.widget_next_alarm, "Next alarm — $nextAlarm")
                views.setTextViewText(R.id.widget_task_preview, taskPreview ?: "All clear today")

                views.setInt(R.id.widget_accent_bar, "setBackgroundColor", accentColor)
                views.setTextColor(R.id.widget_tasks_count, accentColor)
            } catch (e: Exception) {
                views.setTextViewText(R.id.widget_tasks_count, "0")
                views.setTextViewText(R.id.widget_next_alarm, "Next alarm — --:--")
                views.setTextViewText(R.id.widget_task_preview, "Open TaskMate")
            }

            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    appWidgetId,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
            }

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
