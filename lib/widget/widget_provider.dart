import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../core/db/database.dart';
import '../core/db/repositories/task_repository.dart';
import '../core/db/repositories/alarm_repository.dart';
import '../core/theme/theme_provider.dart';
import '../models/alarm_model.dart';

class WidgetProvider {
  static String _fmtHHMM(String hhmm) {
    try {
      final parts = hhmm.split(':');
      final dt = DateTime(2000, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return hhmm;
    }
  }

  /// The DateTime an alarm will next ring: later today if its time is still
  /// ahead, otherwise tomorrow (weekday alarms skip the weekend). This is why a
  /// 7am alarm correctly shows as "next" even at 9pm the night before.
  static DateTime? _nextAlarmFire(AlarmModel a, DateTime now) {
    try {
      final p = a.alarmTime.split(':');
      var dt = DateTime(now.year, now.month, now.day,
          int.parse(p[0]), int.parse(p[1]));
      if (!dt.isAfter(now)) dt = dt.add(const Duration(days: 1));
      if (a.recurrence == 'weekdays') {
        while (dt.weekday == DateTime.saturday ||
            dt.weekday == DateTime.sunday) {
          dt = dt.add(const Duration(days: 1));
        }
      }
      return dt;
    } catch (_) {
      return null;
    }
  }

  /// Returns the next upcoming event label — either an alarm time or a
  /// reminder due time — whichever fires soonest.
  static Future<String> _nextEventLabel(dynamic db) async {
    final now = DateTime.now();

    // Soonest alarm across ALL active alarms (not just ones later today).
    DateTime? alarmDt;
    AlarmModel? soonestAlarm;
    final alarms = await AlarmRepository(db).getActiveAlarms();
    for (final a in alarms) {
      final dt = _nextAlarmFire(a, now);
      if (dt != null && (alarmDt == null || dt.isBefore(alarmDt))) {
        alarmDt = dt;
        soonestAlarm = a;
      }
    }

    // Next reminder from tasks table.
    DateTime? reminderDt;
    String reminderLabel = '';
    final tasks = await TaskRepository(db).getActive();
    for (final t in tasks) {
      if (t.dueDate == null) continue;
      try {
        final dt = DateTime.parse(t.dueDate!.replaceFirst(' ', 'T'));
        if (dt.isAfter(now)) {
          if (reminderDt == null || dt.isBefore(reminderDt)) {
            reminderDt = dt;
            reminderLabel = DateFormat('h:mm a').format(dt);
          }
        }
      } catch (_) {}
    }

    // Pick whichever is sooner.
    if (alarmDt == null && reminderDt == null) return '--:--';
    if (alarmDt == null) return reminderLabel;
    if (reminderDt == null) return _fmtHHMM(soonestAlarm!.alarmTime);
    return alarmDt.isBefore(reminderDt)
        ? _fmtHHMM(soonestAlarm!.alarmTime)
        : reminderLabel;
  }

  static Future<void> refresh() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final todayTasks = await TaskRepository(db).getTasksDueToday();
      final nextLabel = await _nextEventLabel(db);

      final accentHex = '#${ThemeProvider.instance.accent.value.toRadixString(16).substring(2).toUpperCase()}';
      await HomeWidget.saveWidgetData('accent_color', accentHex);
      await HomeWidget.saveWidgetData('tasks_today', todayTasks.length);
      await HomeWidget.saveWidgetData('next_alarm', nextLabel);
      await HomeWidget.saveWidgetData(
        'task_preview',
        todayTasks.isEmpty ? 'All clear today' : todayTasks.first.title,
      );
      await HomeWidget.updateWidget(
        androidName: 'TaskMateWidgetProvider',
        qualifiedAndroidName: 'com.taskmate.taskmate.TaskMateWidgetProvider',
      );
    } catch (_) {
      // Widget update is non-critical — swallow errors
    }
  }
}
