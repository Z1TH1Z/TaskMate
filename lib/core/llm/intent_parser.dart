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

class IntentParser {
  String? _userMessage;

  List<BaseIntent> parse(List<Map<String, dynamic>> rawIntents, [String? userMessage]) {
    _userMessage = userMessage;
    final results = <BaseIntent>[];
    for (final map in rawIntents) {
      final parsed = _parseOne(map);
      if (parsed is List<BaseIntent>) {
        results.addAll(parsed);
      } else {
        results.add(parsed as BaseIntent);
      }
    }
    return results;
  }

  dynamic _parseOne(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    switch (type) {
      case 'alarm':
        return _parseAlarm(map);
      case 'reminder':
        final intent = ReminderIntent.fromMap(map);
        if (_userMessage != null) {
          final corrected = _correctRemindAt(intent.remindAt, _userMessage!);
          if (corrected != intent.remindAt) {
            return ReminderIntent(
              title: intent.title,
              remindAt: corrected,
              notes: intent.notes,
            );
          }
        }
        return intent;
      case 'recurring':
        return RecurringIntent.fromMap(map);
      case 'list':
        return ListIntent.fromMap(map);
      case 'todo':
        return TodoIntent.fromMap(map);
      case 'complete':
        return CompleteIntent.fromMap(map);
      case 'query':
        return QueryIntent.fromMap(map);
      case 'clarify':
        return ClarifyIntent.fromMap(map);
      case 'reschedule':
        return RescheduleIntent.fromMap(map);
      case 'repeat':
        return RepeatIntent.fromMap(map);
      default:
        return ClarifyIntent(message: "I didn't understand that part of your request.");
    }
  }

  dynamic _parseAlarm(Map<String, dynamic> map) {
    final targetTime = map['target_time'] as String?;
    final count = map['count'] as int?;

    if (targetTime != null && count != null && count > 1) {
      return _expandMultiAlarm(targetTime, count, map['label'] as String? ?? 'Alarm');
    }

    final rawTimes = List<String>.from(map['times'] as List? ?? []);
    if (rawTimes.isEmpty && targetTime != null) {
      rawTimes.add(targetTime);
    }

    final correctedTimes = _userMessage != null
        ? rawTimes.map((t) => _correctTime(t, _userMessage!)).toList()
        : rawTimes;

    return AlarmIntent(
      times: correctedTimes,
      label: map['label'] as String? ?? 'Alarm',
      recurrence: map['recurrence'] as String? ?? 'none',
    );
  }

  List<BaseIntent> _expandMultiAlarm(String targetTime, int count, String label) {
    final parts = targetTime.split(':');
    final targetHour = int.parse(parts[0]);
    final targetMinute = int.parse(parts[1]);
    final targetTotal = targetHour * 60 + targetMinute;

    final times = _computeAlarmTimes(targetTotal, count);
    final results = <BaseIntent>[];

    for (final totalMins in times) {
      final h = (totalMins ~/ 60) % 24;
      final m = totalMins % 60;
      final timeStr = '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      results.add(AlarmIntent(
        times: [timeStr],
        label: label,
        recurrence: 'none',
      ));
    }
    return results;
  }

  /// Distributes alarms before the target time, clustered close to it.
  /// Uses exponentially decreasing intervals so alarms get denser as the
  /// target approaches.
  static List<int> _computeAlarmTimes(int targetMinutes, int count) {
    if (count <= 0) return [];
    if (count == 1) return [targetMinutes - 5];

    // Determine span based on count: keep alarms within a reasonable window.
    int span;
    if (count <= 2) {
      span = 30;
    } else if (count <= 3) {
      span = 60;
    } else if (count <= 5) {
      span = 60;
    } else {
      span = (count * 10).clamp(60, 120);
    }

    final times = <int>[];

    if (count == 2) {
      times.add(targetMinutes - 30);
      times.add(targetMinutes - 10);
    } else if (count == 3) {
      times.add(targetMinutes - 60);
      times.add(targetMinutes - 30);
      times.add(targetMinutes - 15);
    } else if (count == 4) {
      times.add(targetMinutes - 60);
      times.add(targetMinutes - 40);
      times.add(targetMinutes - 20);
      times.add(targetMinutes - 5);
    } else if (count == 5) {
      times.add(targetMinutes - 60);
      times.add(targetMinutes - 45);
      times.add(targetMinutes - 30);
      times.add(targetMinutes - 15);
      times.add(targetMinutes - 5);
    } else {
      // For larger counts, distribute with decreasing gaps.
      // Last alarm is 5 min before target, first alarm is `span` min before.
      final totalGap = span - 5; // from first alarm to last alarm
      double ratio = 1.5;
      // Compute geometric series: gap_i = base * ratio^i
      // Sum = base * (ratio^(count-1) - 1) / (ratio - 1) = totalGap
      double sumRatios = 0;
      for (int i = 0; i < count - 1; i++) {
        sumRatios += _pow(ratio, i);
      }
      final baseGap = totalGap / sumRatios;

      double offset = span.toDouble();
      for (int i = 0; i < count; i++) {
        times.add(targetMinutes - offset.round());
        if (i < count - 1) {
          offset -= baseGap * _pow(ratio, i);
          if (offset < 5) offset = 5;
        }
      }
    }

    // Ensure all times are non-negative (wrap around midnight if needed).
    return times.map((t) => t < 0 ? t + 1440 : t).toList()..sort();
  }

  static double _pow(double base, int exp) {
    double result = 1;
    for (int i = 0; i < exp; i++) {
      result *= base;
    }
    return result;
  }

  /// Corrects an HH:MM time based on AM/PM in the user's message.
  static String _correctTime(String time, String userMessage) {
    final msg = userMessage.toLowerCase();
    final ampmMatch = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(am|pm)', caseSensitive: false)
        .firstMatch(msg);
    if (ampmMatch == null) return time;

    final userHour = int.parse(ampmMatch.group(1)!);
    final userMinute = int.tryParse(ampmMatch.group(2) ?? '') ?? 0;
    final period = ampmMatch.group(3)!.toLowerCase();

    final parts = time.split(':');
    final llmHour = int.parse(parts[0]);
    final llmMinute = int.parse(parts[1]);

    // Only correct if the LLM's minute matches (same time, wrong period).
    if (llmMinute != userMinute) return time;

    final expected = _to24Hour(userHour, userMinute, period);
    if (expected == llmHour) return time; // Already correct.

    // Check if the LLM returned the wrong period.
    final llm12 = llmHour % 12 == 0 ? 12 : llmHour % 12;
    if (llm12 == userHour) {
      return '${expected.toString().padLeft(2, '0')}:${parts[1]}';
    }

    return time;
  }

  /// Corrects a "YYYY-MM-DD HH:MM" datetime string.
  static String _correctRemindAt(String remindAt, String userMessage) {
    final spaceIdx = remindAt.indexOf(' ');
    if (spaceIdx < 0) return remindAt;
    final datePart = remindAt.substring(0, spaceIdx);
    final timePart = remindAt.substring(spaceIdx + 1);
    final corrected = _correctTime(timePart, userMessage);
    return '$datePart $corrected';
  }

  static int _to24Hour(int hour12, int minute, String period) {
    if (period == 'am') {
      return hour12 == 12 ? 0 : hour12;
    } else {
      return hour12 == 12 ? 12 : hour12 + 12;
    }
  }

  // Test helpers
  static String correctTimeForTest(String time, String msg) => _correctTime(time, msg);
  static List<int> computeAlarmTimesForTest(int target, int count) => _computeAlarmTimes(target, count);
}
