import 'base_intent.dart';

class RecurringIntent extends BaseIntent {
  final String title;
  final List<String> notifyTimes;
  final String recurrence;
  final String? endDate;

  const RecurringIntent({
    required this.title,
    required this.notifyTimes,
    required this.recurrence,
    this.endDate,
  }) : super('recurring');

  factory RecurringIntent.fromMap(Map<String, dynamic> map) => RecurringIntent(
    title: map['title'] as String,
    notifyTimes: List<String>.from(map['notify_times'] as List? ?? ['09:00']),
    recurrence: map['recurrence'] as String? ?? 'daily',
    endDate: map['end_date'] as String?,
  );
}
