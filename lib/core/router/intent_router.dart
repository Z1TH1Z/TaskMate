import 'package:sqflite/sqflite.dart';
import '../../models/intents/base_intent.dart';
import '../../models/intents/alarm_intent.dart';
import '../../models/intents/reminder_intent.dart';
import '../../models/intents/recurring_intent.dart';
import '../../models/intents/list_intent.dart';
import '../../models/intents/todo_intent.dart';
import '../../models/intents/complete_intent.dart';
import '../../models/intents/query_intent.dart';
import '../../models/intents/clarify_intent.dart';
import '../../models/intents/reschedule_intent.dart';
import '../../models/intents/repeat_intent.dart';
import '../../models/task.dart';
import '../../models/task_list.dart';
import '../../models/list_item.dart';
import '../db/repositories/task_repository.dart';
import '../db/repositories/list_repository.dart';
import '../db/repositories/alarm_repository.dart';
import '../scheduler/alarm_service.dart';
import '../scheduler/notification_service.dart';
import '../../utils/id_generator.dart';
import '../../utils/date_helper.dart';

class IntentRouter {
  final Database db;

  IntentRouter(this.db);

  TaskRepository get _taskRepo => TaskRepository(db);
  ListRepository get _listRepo => ListRepository(db);
  AlarmRepository get _alarmRepo => AlarmRepository(db);

  Future<List<String>> route(List<BaseIntent> intents) async {
    final responses = <String>[];
    for (final intent in intents) {
      final reply = await _handle(intent);
      if (reply != null) responses.add(reply);
    }
    return responses;
  }

  Future<String?> _handle(BaseIntent intent) async {
    if (intent is AlarmIntent) return _handleAlarm(intent);
    if (intent is ReminderIntent) return _handleReminder(intent);
    if (intent is RecurringIntent) return _handleRecurring(intent);
    if (intent is ListIntent) return _handleList(intent);
    if (intent is TodoIntent) return _handleTodo(intent);
    if (intent is CompleteIntent) return _handleComplete(intent);
    if (intent is QueryIntent) return _handleQuery(intent);
    if (intent is RescheduleIntent) return _handleReschedule(intent);
    if (intent is RepeatIntent) return _handleRepeat(intent);
    if (intent is ClarifyIntent) return intent.message;
    return "Didn't understand that part.";
  }

  Future<String> _handleAlarm(AlarmIntent intent) async {
    final set = <String>[];
    final skipped = <String>[];
    for (final time in intent.times) {
      final already = await _alarmRepo.existsAtTime(time);
      if (already) {
        skipped.add(DateHelper.formatTime(time));
        continue;
      }
      await AlarmService().scheduleAlarm(
        time: time,
        label: intent.label,
        recurrence: intent.recurrence,
      );
      set.add(DateHelper.formatTime(time));
    }
    if (set.isEmpty) {
      return 'Alarm${skipped.length > 1 ? 's' : ''} already set for ${skipped.join(' · ')}.';
    }
    final recurrenceStr = intent.recurrence != 'none' ? ' · ${intent.recurrence}' : '';
    String reply = '✓ ${set.length} alarm${set.length > 1 ? 's' : ''} set\n${set.join(' · ')}$recurrenceStr';
    if (skipped.isNotEmpty) {
      reply += '\nSkipped ${skipped.join(' · ')} — already set';
    }
    return reply;
  }

  Future<String> _handleReminder(ReminderIntent intent) async {
    DateTime? scheduledAt;
    try {
      scheduledAt = DateTime.parse(intent.remindAt.replaceFirst(' ', 'T'));
    } catch (_) {
      return "Couldn't parse the reminder time. Please try again.";
    }

    if (scheduledAt.isBefore(DateTime.now())) {
      return "That time is already past. Please set a future time.";
    }

    final notifId = generateId();
    await AlarmService().scheduleReminder(
      id: notifId,
      title: intent.title,
      body: intent.notes,
      scheduledAt: scheduledAt,
    );

    final taskId = await _taskRepo.insert(Task(
      title: intent.title,
      type: 'reminder',
      dueDate: intent.remindAt,
      notificationIds: [notifId],
      createdAt: DateHelper.nowIso(),
    ));
    await _taskRepo.updateNotificationIds(taskId, [notifId]);

    return '✓ Reminder set — ${intent.title}\n${DateHelper.formatDisplay(intent.remindAt)}';
  }

  Future<String> _handleRecurring(RecurringIntent intent) async {
    final skipWeekends = intent.recurrence == 'weekdays';
    DateTime? endDate;
    if (intent.endDate != null) {
      try {
        endDate = DateTime.parse(intent.endDate!);
      } catch (_) {}
    }

    final taskId = await _taskRepo.insert(Task(
      title: intent.title,
      type: 'recurring',
      recurrence: intent.recurrence,
      recurrenceEnd: intent.endDate,
      skipWeekends: skipWeekends,
      createdAt: DateHelper.nowIso(),
    ));

    final ids = await AlarmService().scheduleRecurringReminder(
      title: intent.title,
      times: intent.notifyTimes,
      skipWeekends: skipWeekends,
      recurrence: intent.recurrence,
      endDate: endDate,
    );
    await _taskRepo.updateNotificationIds(taskId, ids);

    final timesStr = intent.notifyTimes.map(DateHelper.formatTime).join(' · ');
    final endStr = intent.endDate != null ? ' · until ${DateHelper.formatDisplay(intent.endDate)}' : '';
    return '✓ Recurring set — ${intent.title}\n$timesStr · ${intent.recurrence}$endStr';
  }

  Future<String> _handleList(ListIntent intent) async {
    TaskList? existingList = await _listRepo.getListByName(intent.listName);

    // Fallback: match by category if exact name not found
    if (existingList == null && intent.category != 'general') {
      final byCategory = await _listRepo.searchLists(intent.category);
      if (byCategory.isNotEmpty) {
        existingList = byCategory.first;
      }
    }

    if (existingList == null) {
      if (intent.action == 'remove') {
        return "Couldn't find a list called '${intent.listName}'.";
      }
      final listId = await _listRepo.insertList(TaskList(
        name: intent.listName,
        category: intent.category,
        createdAt: DateHelper.nowIso(),
      ));
      existingList = TaskList(
        id: listId,
        name: intent.listName,
        category: intent.category,
        createdAt: DateHelper.nowIso(),
      );
    }

    if (intent.action == 'remove') {
      final removed = <String>[];
      for (final item in intent.items) {
        final count = await _listRepo.deleteItemsByTitle(existingList.id!, item.title);
        if (count > 0) removed.add(item.title);
      }
      if (removed.isEmpty) return "Couldn't find those items in ${intent.listName}.";
      return '✓ Removed from ${intent.listName}\n${removed.join(' · ')}';
    }

    final added = <String>[];
    for (final item in intent.items) {
      await _listRepo.insertItem(ListItem(
        listId: existingList.id!,
        title: item.title,
        notes: item.notes,
      ));
      added.add(item.title);
    }

    return '✓ ${added.length > 1 ? "${added.length} items" : added.first} added to ${intent.listName}\n${added.join(' · ')}';
  }

  Future<String> _handleTodo(TodoIntent intent) async {
    await _taskRepo.insert(Task(
      title: intent.title,
      type: 'todo',
      dueDate: intent.dueDate,
      priority: intent.priority,
      createdAt: DateHelper.nowIso(),
    ));

    final dueStr = intent.dueDate != null ? '\n${DateHelper.formatDisplay(intent.dueDate)}' : '';
    return '✓ Todo added — ${intent.title}$dueStr';
  }

  Future<String> _handleComplete(CompleteIntent intent) async {
    final notifService = NotificationService();
    final responses = <String>[];
    final isWildcard = intent.searchTerm.trim() == '*';
    final alarmsOnly = intent.scope == 'alarms';

    // Cancel tasks/reminders — skip entirely if alarmsOnly.
    if (!alarmsOnly) {
      final tasks = isWildcard
          ? await _taskRepo.getActive()
          : await _taskRepo.searchByTitle(intent.searchTerm);

      for (final task in tasks) {
        if (intent.scope == 'today' && !isWildcard) {
          if (task.type == 'recurring') {
            for (final id in task.notificationIds) {
              await notifService.cancel(id);
            }
          } else {
            for (final id in task.notificationIds) {
              await notifService.cancel(id);
              await AlarmService().cancelReminder(id);
            }
          }
          responses.add("Got it. No more reminders for '${task.title}' today.");
        } else {
          for (final id in task.notificationIds) {
            await notifService.cancel(id);
            await AlarmService().cancelReminder(id);
          }
          await _taskRepo.updateNotificationIds(task.id!, []);
          await _taskRepo.markComplete(task.id!);
          responses.add("'${task.title}' marked done.");
        }
      }
    }

    // Cancel alarms — always run for wildcards and alarm-scope requests.
    final alarms = await _alarmRepo.getActiveAlarms();
    final term = intent.searchTerm.toLowerCase();
    for (final alarm in alarms) {
      if (isWildcard || alarm.label.toLowerCase().contains(term)) {
        if (alarm.androidAlarmId != null) {
          await AlarmService().cancelAlarm(alarm.androidAlarmId!);
        } else {
          await _alarmRepo.deactivateById(alarm.id!);
        }
        responses.add("Alarm '${alarm.label}' (${DateHelper.formatTime(alarm.alarmTime)}) cancelled.");
      }
    }

    // Mark list items done — "watched Backrooms", "finished reading Dune", etc.
    if (!isWildcard && !alarmsOnly) {
      final lists = await _listRepo.getLists();
      for (final list in lists) {
        final items = await _listRepo.getItems(list.id!);
        for (final item in items) {
          if (!item.isDone && item.title.toLowerCase().contains(term)) {
            await _listRepo.markItemDone(item.id!);
            responses.add('✓ "${item.title}" marked done in ${list.name}.');
          }
        }
      }
    }

    if (responses.isEmpty) {
      return "Couldn't find anything matching '${intent.searchTerm}'.";
    }
    if (isWildcard && alarmsOnly) return "All alarms cleared. ${responses.length} cancelled.";
    if (isWildcard) return "All cleared. ${responses.length} item(s) cancelled.";
    return responses.join('\n');
  }

  Future<String> _handleQuery(QueryIntent intent) async {
    // List query — show items from a named list.
    if (intent.filter == 'list') {
      final searchTerm = intent.listName ?? '';
      final lists = searchTerm.isEmpty
          ? await _listRepo.getLists()
          : await _listRepo.searchLists(searchTerm);

      if (lists.isEmpty) {
        return "Couldn't find a list matching '$searchTerm'.";
      }

      final buffer = StringBuffer();
      for (final list in lists) {
        final items = await _listRepo.getItems(list.id!);
        final pending = items.where((i) => !i.isDone).toList();
        buffer.writeln('📋 ${list.name}:');
        if (pending.isEmpty) {
          buffer.writeln('  (empty)');
        } else {
          for (final item in pending) {
            final note = item.notes != null ? ' — ${item.notes}' : '';
            buffer.writeln('  • ${item.title}$note');
          }
        }
      }
      return buffer.toString().trimRight();
    }

    List<Task> tasks;

    switch (intent.filter) {
      case 'today':
        tasks = await _taskRepo.getTasksDueToday();
        if (tasks.isEmpty) {
          final active = await _taskRepo.getActive();
          tasks = active.where((t) => t.type == 'recurring').toList();
        }
      case 'week':
        tasks = await _taskRepo.getActive();
        final now = DateTime.now();
        final weekEnd = now.add(const Duration(days: 7));
        tasks = tasks.where((t) {
          if (t.dueDate == null) return t.type == 'recurring';
          try {
            final due = DateTime.parse(t.dueDate!.replaceFirst(' ', 'T'));
            return due.isBefore(weekEnd);
          } catch (_) {
            return false;
          }
        }).toList();
      case 'overdue':
        tasks = await _taskRepo.getOverdue();
      // Type-specific filters (feature 1)
      case 'reminders':
        tasks = await _taskRepo.getByType('reminder');
      case 'todos':
        tasks = await _taskRepo.getByType('todo');
      case 'recurring':
        tasks = await _taskRepo.getByType('recurring');
      case 'alarms':
        tasks = [];
      // Urgency sort (feature 10)
      case 'urgent':
        final overdue = await _taskRepo.getOverdue();
        final today = await _taskRepo.getTasksDueToday();
        today.sort((a, b) => (a.dueDate ?? '').compareTo(b.dueDate ?? ''));
        final allActive = await _taskRepo.getActive();
        final highPrio = allActive
            .where((t) => t.priority == 'high' && !overdue.contains(t) && !today.contains(t))
            .toList();
        tasks = [...overdue, ...today, ...highPrio];
      default:
        tasks = await _taskRepo.getActive();
    }

    // Include active alarms for today/all/alarms/urgent views.
    final alarmLines = <String>[];
    if (intent.filter == 'today' || intent.filter == 'all' ||
        intent.filter == 'alarms' || intent.filter == 'urgent') {
      final alarms = await _alarmRepo.getActiveAlarms();
      for (final a in alarms) {
        final rec = a.recurrence != 'none' ? ' (${a.recurrence})' : '';
        alarmLines.add('⏰ ${DateHelper.formatTime(a.alarmTime)} — ${a.label}$rec');
      }
    }

    if (tasks.isEmpty && alarmLines.isEmpty) {
      return "Nothing on your list for ${intent.filter}.";
    }

    final taskLines = tasks.map((t) {
      final due = t.dueDate != null ? ' — ${DateHelper.formatDisplay(t.dueDate)}' : '';
      return '• ${t.title}$due';
    }).toList();

    final all = [...taskLines, ...alarmLines].join('\n');
    return "Here's what you have (${intent.filter}):\n$all";
  }

  // Feature 4: reschedule an existing alarm or reminder to a new time.
  Future<String> _handleReschedule(RescheduleIntent intent) async {
    final responses = <String>[];
    final term = intent.searchTerm.toLowerCase();

    // Reschedule matching alarms.
    if (intent.newTime != null) {
      final alarms = await _alarmRepo.searchByLabel(term);
      for (final alarm in alarms) {
        if (alarm.androidAlarmId != null) {
          await AlarmService().cancelAlarm(alarm.androidAlarmId!);
          await AlarmService().scheduleAlarm(
            time: intent.newTime!,
            label: alarm.label,
            recurrence: alarm.recurrence,
          );
          responses.add('Alarm "${alarm.label}" moved to ${DateHelper.formatTime(intent.newTime)}.');
        }
      }
    }

    // Reschedule matching reminder tasks. Validate the new time BEFORE touching
    // the existing alarm — otherwise a bad/past time would cancel the reminder
    // and leave the task orphaned (active but with no alarm behind it).
    if (intent.newDatetime != null) {
      DateTime? newDt;
      try {
        newDt = DateTime.parse(intent.newDatetime!.replaceFirst(' ', 'T'));
      } catch (_) {}
      if (newDt == null || !newDt.isAfter(DateTime.now())) {
        return "Couldn't reschedule — that time is invalid or already past. Your reminder is unchanged.";
      }
      final tasks = await _taskRepo.searchByTitle(term);
      for (final task in tasks.where((t) => t.type == 'reminder')) {
        for (final id in task.notificationIds) {
          await AlarmService().cancelReminder(id);
        }
        final notifId = generateId();
        await AlarmService().scheduleReminder(
          id: notifId,
          title: task.title,
          body: null,
          scheduledAt: newDt,
        );
        await _taskRepo.updateDueDate(task.id!, intent.newDatetime!);
        await _taskRepo.updateNotificationIds(task.id!, [notifId]);
        responses.add('Reminder "${task.title}" moved to ${DateHelper.formatDisplay(intent.newDatetime)}.');
      }
    }

    if (responses.isEmpty) return "Couldn't find anything to reschedule matching '${intent.searchTerm}'.";
    return '✓ Rescheduled\n${responses.join('\n')}';
  }

  // Feature 8: repeat the most recent alarm or reminder, offset from now.
  Future<String> _handleRepeat(RepeatIntent intent) async {
    final target = DateTime.now().add(Duration(minutes: intent.offsetMinutes));
    final hhmm =
        '${target.hour.toString().padLeft(2, '0')}:${target.minute.toString().padLeft(2, '0')}';

    // Try latest alarm first.
    final latestAlarm = await _alarmRepo.getLatest();
    if (latestAlarm != null) {
      await AlarmService().scheduleAlarm(
        time: hhmm,
        label: latestAlarm.label,
        recurrence: 'none',
      );
      return '✓ "${latestAlarm.label}" rescheduled\n${DateHelper.formatTime(hhmm)}';
    }

    // Fall back to latest reminder.
    final latestReminder = await _taskRepo.getLatestByType('reminder');
    if (latestReminder != null) {
      final notifId = generateId();
      await AlarmService().scheduleReminder(
        id: notifId,
        title: latestReminder.title,
        body: null,
        scheduledAt: target,
      );
      String two(int n) => n.toString().padLeft(2, '0');
      final dueStr =
          '${target.year}-${two(target.month)}-${two(target.day)} ${two(target.hour)}:${two(target.minute)}';
      final taskId = await _taskRepo.insert(Task(
        title: latestReminder.title,
        type: 'reminder',
        dueDate: dueStr,
        notificationIds: [notifId],
        createdAt: DateHelper.nowIso(),
      ));
      await _taskRepo.updateNotificationIds(taskId, [notifId]);
      return '✓ "${latestReminder.title}" reminder repeated\n${DateHelper.formatTime(hhmm)}';
    }

    return "Nothing recent to repeat.";
  }
}
