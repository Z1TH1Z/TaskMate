import 'package:flutter/services.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import '../db/repositories/alarm_repository.dart';
import '../db/repositories/task_repository.dart';
import '../../models/alarm_model.dart';
import '../../models/task.dart';
import '../../utils/id_generator.dart';
import '../../widget/widget_provider.dart';

// Alarms are handled fully natively (AlarmManager.setAlarmClock → AlarmReceiver
// → AlarmForegroundService → AlarmActivity) so they ring like a real alarm:
// looping ringtone + vibration + a full-screen dismiss/snooze screen, even when
// the phone is in use. Reminders & recurring still use android_alarm_manager_plus
// below (they only need a notification, not a ringing alarm).
const MethodChannel _alarmChannel = MethodChannel('taskmate/alarm');

/// Runs in a background isolate when a REMINDER fires. We deliberately route
/// reminders through android_alarm_manager_plus (which only runs Dart) and post
/// the notification here with fln.show() — the SAME mechanism the alarm path
/// uses and which is proven to display on-device. flutter_local_notifications'
/// own zonedSchedule fires its native receiver but silently fails to display
/// the notification on this device, so we avoid it entirely.
@pragma('vm:entry-point')
void reminderCallback(int id) async {
  // Idempotency guard: only fire if an active reminder still owns this id.
  // Already-fired reminders are marked complete, so a stale re-fire (app
  // reinstall / reboot re-running a past alarm) finds no owner and bails.
  int? ownerTaskId;
  try {
    final db = await DatabaseHelper.instance.database;
    final tasks = await TaskRepository(db).getActive();
    for (final t in tasks) {
      if (t.type == 'reminder' && t.notificationIds.contains(id)) {
        ownerTaskId = t.id;
        break;
      }
    }
    if (ownerTaskId == null) {
      await AndroidAlarmManager.cancel(id);
      return;
    }
  } catch (_) {
    // DB unavailable — fall through and show.
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final title = prefs.getString('reminder_title_$id') ?? 'Reminder';
  final body = prefs.getString('reminder_body_$id') ?? '';

  final fln = FlutterLocalNotificationsPlugin();
  // Register the action handler here too: this runs in a background isolate, and
  // its initialize() must not leave the plugin without the background response
  // handler (that would break Done/Snooze taps when the app is killed).
  await fln.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: reminderActionCallback,
    onDidReceiveBackgroundNotificationResponse: reminderActionCallback,
  );

  const channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Task reminders and recurring notifications',
    importance: Importance.high,
  );
  await fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await fln.show(
    id,
    title,
    body,
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Task reminders and recurring notifications',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        enableVibration: true,
        autoCancel: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('reminder_done', 'Done',
              showsUserInterface: false, cancelNotification: true),
          AndroidNotificationAction('reminder_snooze', 'Snooze 10 min',
              showsUserInterface: false, cancelNotification: true),
        ],
      ),
    ),
  );

  // One-shot reminder fired — mark the task complete so it leaves the list.
  try {
    if (ownerTaskId != null) {
      final db = await DatabaseHelper.instance.database;
      await TaskRepository(db).markComplete(ownerTaskId);
    }
    await AndroidAlarmManager.cancel(id);
    await prefs.remove('reminder_title_$id');
    await prefs.remove('reminder_body_$id');
    await WidgetProvider.refresh();
  } catch (_) {}
}

String _two(int n) => n.toString().padLeft(2, '0');

/// Handles taps on a reminder notification's action buttons ("Done" /
/// "Snooze 10 min"). The plugin invokes this in the foreground isolate when the
/// app is alive, or a fresh background isolate otherwise — so it only touches
/// the DB, prefs and AlarmManager, never UI. Non-reminder actions are ignored.
@pragma('vm:entry-point')
void reminderActionCallback(NotificationResponse response) async {
  final id = response.id;
  final action = response.actionId;
  if (id == null || action == null) return;
  if (action != 'reminder_snooze' && action != 'reminder_done') return;

  final fln = FlutterLocalNotificationsPlugin();
  await fln.cancel(id);

  // Find the owning reminder (it was marked complete when it fired, so search
  // ALL tasks, not just active ones).
  Task? owner;
  try {
    final db = await DatabaseHelper.instance.database;
    final all = await TaskRepository(db).getAll();
    for (final t in all) {
      if (t.type == 'reminder' && t.notificationIds.contains(id)) {
        owner = t;
        break;
      }
    }
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();

  if (action == 'reminder_snooze') {
    final snoozeAt = DateTime.now().add(const Duration(minutes: 10));
    // reminderCallback cleared the title/body prefs when it fired — restore
    // them (from the task if needed) so the re-armed alarm can display.
    final title = prefs.getString('reminder_title_$id') ?? owner?.title ?? 'Reminder';
    await prefs.setString('reminder_title_$id', title);
    await prefs.setString(
        'reminder_body_$id', prefs.getString('reminder_body_$id') ?? '');

    await AndroidAlarmManager.oneShotAt(
      snoozeAt,
      id,
      reminderCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );

    // Revive the task so it re-appears in the list and the re-fire's
    // idempotency guard passes; push its due date to the snooze time so the
    // stale-reminder cleanup doesn't immediately re-complete it.
    if (owner?.id != null) {
      final db = await DatabaseHelper.instance.database;
      final repo = TaskRepository(db);
      await repo.markActive(owner!.id!);
      final due =
          '${snoozeAt.year}-${_two(snoozeAt.month)}-${_two(snoozeAt.day)} ${_two(snoozeAt.hour)}:${_two(snoozeAt.minute)}';
      await repo.updateDueDate(owner.id!, due);
    }
  } else {
    // Done: finalise. Complete the task, cancel any pending (snoozed) alarm,
    // and clear its pref keys.
    if (owner?.id != null) {
      final db = await DatabaseHelper.instance.database;
      await TaskRepository(db).markComplete(owner!.id!);
    }
    await AndroidAlarmManager.cancel(id);
    await prefs.remove('reminder_title_$id');
    await prefs.remove('reminder_body_$id');
  }

  try {
    await WidgetProvider.refresh();
  } catch (_) {}
}

/// Runs daily (in a background isolate) for a RECURRING reminder. Unlike
/// reminderCallback it does NOT complete the task — it keeps firing. Reads its
/// schedule rules (weekday skipping, end date) from SharedPreferences and posts
/// via fln.show(), the display path that actually works on this device. Replaces
/// the old WorkManager + zonedSchedule recurring path, which never displayed.
@pragma('vm:entry-point')
void recurringReminderCallback(int id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final title = prefs.getString('recur_title_$id') ?? 'Reminder';
  final skipWeekends = prefs.getBool('recur_skip_$id') ?? false;
  final endStr = prefs.getString('recur_end_$id');
  final schedTime = prefs.getString('recur_time_$id'); // 'HH:MM'

  final freq = prefs.getString('recur_freq_$id') ?? 'daily';
  final weekday = prefs.getInt('recur_weekday_$id');

  final now = DateTime.now();

  // Lifecycle guard: stop if the owning recurring task was completed/removed.
  try {
    final db = await DatabaseHelper.instance.database;
    final tasks = await TaskRepository(db).getActive();
    final stillActive =
        tasks.any((t) => t.type == 'recurring' && t.notificationIds.contains(id));
    if (!stillActive) {
      await AndroidAlarmManager.cancel(id);
      await prefs.remove('recur_title_$id');
      await prefs.remove('recur_skip_$id');
      await prefs.remove('recur_end_$id');
      await prefs.remove('recur_time_$id');
      await prefs.remove('recur_freq_$id');
      await prefs.remove('recur_weekday_$id');
      return;
    }
  } catch (_) {}

  // Stale-fire guard: a real daily fire happens at the scheduled minute. When
  // the app is reinstalled/rebooted the OS re-fires past periodic alarms
  // immediately, at the wrong time of day — skip those so reloads don't spam.
  if (schedTime != null) {
    final p = schedTime.split(':');
    final sched = DateTime(now.year, now.month, now.day,
        int.tryParse(p[0]) ?? 0, int.tryParse(p[1]) ?? 0);
    final diff = now.difference(sched).inMinutes;
    if (diff < -1 || diff > 30) return;
  }

  // Past the end date → cancel the recurring alarm and stop.
  if (endStr != null) {
    final end = DateTime.tryParse(endStr);
    if (end != null && now.isAfter(end)) {
      await AndroidAlarmManager.cancel(id);
      await prefs.remove('recur_title_$id');
      await prefs.remove('recur_skip_$id');
      await prefs.remove('recur_end_$id');
      await prefs.remove('recur_time_$id');
      await prefs.remove('recur_freq_$id');
      await prefs.remove('recur_weekday_$id');
      return;
    }
  }

  // Weekday-only schedule → silently skip weekends (alarm still fires tomorrow).
  if (skipWeekends &&
      (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday)) {
    return;
  }

  // Weekly schedule → the alarm fires daily, but only show on the anchor
  // weekday so the effective cadence is once a week.
  if (freq == 'weekly' && weekday != null && now.weekday != weekday) {
    return;
  }

  final fln = FlutterLocalNotificationsPlugin();
  // Keep the background action handler registered (see reminderCallback) so a
  // recurring fire in this isolate doesn't clear it and break reminder actions.
  await fln.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: reminderActionCallback,
    onDidReceiveBackgroundNotificationResponse: reminderActionCallback,
  );

  const channel = AndroidNotificationChannel(
    'reminders',
    'Reminders',
    description: 'Task reminders and recurring notifications',
    importance: Importance.high,
  );
  await fln
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await fln.show(
    id,
    title,
    '',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Task reminders and recurring notifications',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        enableVibration: true,
        autoCancel: true,
      ),
    ),
  );
}

class AlarmService {
  static final AlarmService _instance = AlarmService._();
  factory AlarmService() => _instance;
  AlarmService._();

  Future<int> scheduleAlarm({
    required String time, // HH:MM
    required String label,
    required String recurrence,
  }) async {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    var scheduledTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );

    if (scheduledTime.isBefore(DateTime.now())) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final alarmId = generateId();

    await _alarmChannel.invokeMethod('schedule', {
      'id': alarmId,
      'triggerAtMillis': scheduledTime.millisecondsSinceEpoch,
      'label': label,
      'recurrence': recurrence,
    });

    final db = await DatabaseHelper.instance.database;
    final repo = AlarmRepository(db);
    final dbId = await repo.insert(AlarmModel(
      label: label,
      alarmTime: time,
      recurrence: recurrence,
      androidAlarmId: alarmId,
      createdAt: DateTime.now().toIso8601String(),
    ));
    await repo.updateAndroidId(dbId, alarmId);

    return alarmId;
  }

  Future<void> cancelAlarm(int androidAlarmId) async {
    await _alarmChannel.invokeMethod('cancel', {'id': androidAlarmId});
    final db = await DatabaseHelper.instance.database;
    await AlarmRepository(db).deactivate(androidAlarmId);
  }

  /// One-time migration when upgrading to the native-alarm build: every alarm
  /// still active in the DB predates the native store, so re-arm it natively
  /// instead of letting reconcileFiredAlarms() mistake it for an already-fired
  /// alarm and drop it.
  Future<void> migrateAlarmsToNative() async {
    final db = await DatabaseHelper.instance.database;
    final alarms = await AlarmRepository(db).getActiveAlarms();
    for (final a in alarms) {
      if (a.androidAlarmId != null) {
        await scheduleAlarmById(
          androidAlarmId: a.androidAlarmId!,
          time: a.alarmTime,
          label: a.label,
          recurrence: a.recurrence,
        );
      }
    }
  }

  /// Alarms now fire natively, which doesn't touch our SQLite `alarms` table, so
  /// a fired one-shot would otherwise linger as "active". Native drops one-shots
  /// from its store the moment they fire, so any active one-shot whose id is no
  /// longer scheduled natively has already rung — deactivate it. Recurring
  /// alarms stay in the native store (re-armed each day), so they're untouched.
  Future<void> reconcileFiredAlarms() async {
    try {
      final ids = await _alarmChannel.invokeMethod('scheduledIds');
      final scheduled = (ids as List).map((e) => e as int).toSet();
      final db = await DatabaseHelper.instance.database;
      final repo = AlarmRepository(db);
      for (final a in await repo.getActiveAlarms()) {
        if (a.recurrence == 'none' &&
            a.androidAlarmId != null &&
            !scheduled.contains(a.androidAlarmId)) {
          await repo.deactivate(a.androidAlarmId!);
        }
      }
    } catch (_) {
      // Channel unavailable (e.g. background isolate) — skip; runs again on resume.
    }
  }

  /// Schedule a one-time reminder. Uses android_alarm_manager_plus + a Dart
  /// callback (reminderCallback) that posts the notification, rather than
  /// flutter_local_notifications' zonedSchedule, which does not reliably
  /// display scheduled notifications on this device.
  Future<int> scheduleReminder({
    required int id,
    required String title,
    String? body,
    required DateTime scheduledAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('reminder_title_$id', title);
    await prefs.setString('reminder_body_$id', body ?? '');

    await AndroidAlarmManager.oneShotAt(
      scheduledAt,
      id,
      reminderCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );
    return id;
  }

  /// Schedule a recurring (daily) reminder — one periodic alarm per notify time.
  /// Returns the alarm ids so they can be stored on the task and cancelled later.
  Future<List<int>> scheduleRecurringReminder({
    required String title,
    required List<String> times,
    required bool skipWeekends,
    String recurrence = 'daily',
    DateTime? endDate,
  }) async {
    final ids = <int>[];
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    for (final time in times) {
      final parts = time.split(':');
      var startAt = DateTime(
        now.year,
        now.month,
        now.day,
        int.parse(parts[0]),
        int.parse(parts[1]),
      );
      if (startAt.isBefore(now)) startAt = startAt.add(const Duration(days: 1));

      final id = generateId();
      await prefs.setString('recur_title_$id', title);
      await prefs.setBool('recur_skip_$id', skipWeekends);
      await prefs.setString('recur_time_$id', time);
      await prefs.setString('recur_freq_$id', recurrence);
      if (recurrence == 'weekly') {
        // Anchor the weekly cadence to the weekday of the first fire.
        await prefs.setInt('recur_weekday_$id', startAt.weekday);
      }
      if (endDate != null) {
        await prefs.setString('recur_end_$id', endDate.toIso8601String());
      }

      await AndroidAlarmManager.periodic(
        const Duration(days: 1),
        id,
        recurringReminderCallback,
        startAt: startAt,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );
      ids.add(id);
    }
    return ids;
  }

  /// Cancel a scheduled reminder (both the pending alarm and, if already shown,
  /// the visible notification). Clears one-time and recurring pref keys alike,
  /// so the same call cleanly cancels either kind by id.
  Future<void> cancelReminder(int id) async {
    await AndroidAlarmManager.cancel(id);
    await FlutterLocalNotificationsPlugin().cancel(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('reminder_title_$id');
    await prefs.remove('reminder_body_$id');
    await prefs.remove('recur_title_$id');
    await prefs.remove('recur_skip_$id');
    await prefs.remove('recur_end_$id');
    await prefs.remove('recur_time_$id');
    await prefs.remove('recur_freq_$id');
    await prefs.remove('recur_weekday_$id');
  }

  /// Re-arm every scheduled item from the current DB + prefs. Used after a
  /// data restore: native alarms come back from the DB, one-time reminders from
  /// their (future) due date, and recurring from the notify time stored in
  /// prefs. Each item is best-effort — a failure on one never aborts the rest.
  Future<void> rearmAllFromDb() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final db = await DatabaseHelper.instance.database;

    // Native alarms (time + recurrence live in the DB).
    try {
      await rescheduleAllAfterReboot();
    } catch (_) {}

    final now = DateTime.now();
    final tasks = await TaskRepository(db).getActive();
    for (final t in tasks) {
      try {
        if (t.type == 'reminder') {
          if (t.dueDate == null) continue;
          final due = DateTime.tryParse(t.dueDate!.replaceFirst(' ', 'T'));
          if (due == null || !due.isAfter(now)) continue;
          for (final id in t.notificationIds) {
            if (prefs.getString('reminder_title_$id') == null) {
              await prefs.setString('reminder_title_$id', t.title);
              await prefs.setString('reminder_body_$id', '');
            }
            await AndroidAlarmManager.oneShotAt(
              due,
              id,
              reminderCallback,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
            );
          }
        } else if (t.type == 'recurring') {
          for (final id in t.notificationIds) {
            final time = prefs.getString('recur_time_$id');
            if (time == null) continue; // notify time unknown — can't re-arm
            final parts = time.split(':');
            var startAt = DateTime(now.year, now.month, now.day,
                int.parse(parts[0]), int.parse(parts[1]));
            if (startAt.isBefore(now)) {
              startAt = startAt.add(const Duration(days: 1));
            }
            await AndroidAlarmManager.periodic(
              const Duration(days: 1),
              id,
              recurringReminderCallback,
              startAt: startAt,
              exact: true,
              wakeup: true,
              rescheduleOnReboot: true,
            );
          }
        }
      } catch (_) {}
    }
  }

  /// Clean up one-time reminders whose scheduled time has passed but were never
  /// marked complete (e.g. background isolate killed by OS before DB write).
  Future<void> cleanupStaleReminders() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final repo = TaskRepository(db);
      final active = await repo.getActive();
      final now = DateTime.now();
      for (final task in active) {
        if (task.type == 'reminder' && task.dueDate != null) {
          final due = DateTime.tryParse(task.dueDate!.replaceFirst(' ', 'T'));
          if (due != null && due.isBefore(now)) {
            await repo.markComplete(task.id!);
            for (final id in task.notificationIds) {
              await cancelReminder(id);
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> rescheduleAllAfterReboot() async {
    final db = await DatabaseHelper.instance.database;
    final alarms = await AlarmRepository(db).getActiveAlarms();

    for (final alarm in alarms) {
      if (alarm.androidAlarmId != null) {
        await scheduleAlarmById(
          androidAlarmId: alarm.androidAlarmId!,
          time: alarm.alarmTime,
          label: alarm.label,
          recurrence: alarm.recurrence,
        );
      }
    }
  }

  Future<void> scheduleAlarmById({
    required int androidAlarmId,
    required String time,
    required String label,
    required String recurrence,
  }) async {
    final parts = time.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    var scheduledTime = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
      hour,
      minute,
    );

    if (scheduledTime.isBefore(DateTime.now())) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    await _alarmChannel.invokeMethod('schedule', {
      'id': androidAlarmId,
      'triggerAtMillis': scheduledTime.millisecondsSinceEpoch,
      'label': label,
      'recurrence': recurrence,
    });
  }
}
