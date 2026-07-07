import 'base_intent.dart';

class ReminderIntent extends BaseIntent {
  final String title;
  final String remindAt; // 'YYYY-MM-DD HH:MM'
  final String? notes;

  const ReminderIntent({
    required this.title,
    required this.remindAt,
    this.notes,
  }) : super('reminder');

  factory ReminderIntent.fromMap(Map<String, dynamic> map) => ReminderIntent(
    title: map['title'] as String,
    remindAt: map['remind_at'] as String,
    notes: map['notes'] as String?,
  );
}
