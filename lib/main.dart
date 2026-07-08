import 'package:flutter/material.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/db/database.dart';
import 'core/db/repositories/task_repository.dart';
import 'core/scheduler/notification_service.dart';
import 'core/scheduler/alarm_service.dart';
import 'widget/widget_provider.dart';
import 'app.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // Recurring reminders are handled by android_alarm_manager_plus
    // (AlarmService.scheduleRecurringReminder), not here. WorkManager now only
    // drives the daily morning briefing.
    if (taskName == 'morningBriefing') {
      final db = await DatabaseHelper.instance.database;
      final tasks = await TaskRepository(db).getTasksDueToday();
      final active = await TaskRepository(db).getActive();
      final recurring = active.where((t) => t.type == 'recurring').toList();
      final allToday = {...tasks, ...recurring}.toList();

      if (allToday.isNotEmpty) {
        final summary = allToday.map((t) => t.title).join(' · ');
        final notifService = NotificationService();
        await notifService.init();
        await notifService.showSimple(
          id: 9999,
          title: 'Today',
          body: summary,
        );
      }
    }

    return true;
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AndroidAlarmManager.initialize();
  await Workmanager().initialize(callbackDispatcher);
  await NotificationService().init();
  await DatabaseHelper.instance.database;

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('boot_reschedule_needed') ?? false) {
    await AlarmService().rescheduleAllAfterReboot();
    await prefs.setBool('boot_reschedule_needed', false);
  }

  // On the first launch after upgrading to native alarms, re-arm existing
  // alarms once so none are lost; afterwards, retire one-shots that already
  // fired (native firing doesn't touch the DB) so they don't linger as active.
  if (prefs.getBool('native_alarms_migrated') ?? false) {
    await AlarmService().reconcileFiredAlarms();
  } else {
    await AlarmService().migrateAlarmsToNative();
    await prefs.setBool('native_alarms_migrated', true);
  }

  // Clean up any one-time reminders that fired but weren't marked complete
  // (e.g. background isolate was killed by the OS before DB write finished).
  await AlarmService().cleanupStaleReminders();

  await WidgetProvider.refresh();

  runApp(const TaskMateApp());
}
