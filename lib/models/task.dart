import 'dart:convert';

class Task {
  final int? id;
  final String title;
  final String type; // 'reminder' | 'recurring' | 'todo' | 'alarm'
  final String? dueDate;
  final String? recurrence;
  final String? recurrenceEnd;
  final bool skipWeekends;
  final bool isCompleted;
  final List<int> notificationIds;
  final String createdAt;
  final String? priority;

  Task({
    this.id,
    required this.title,
    required this.type,
    this.dueDate,
    this.recurrence,
    this.recurrenceEnd,
    this.skipWeekends = false,
    this.isCompleted = false,
    this.notificationIds = const [],
    required this.createdAt,
    this.priority,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'type': type,
    'due_date': dueDate,
    'recurrence': recurrence,
    'recurrence_end': recurrenceEnd,
    'skip_weekends': skipWeekends ? 1 : 0,
    'is_completed': isCompleted ? 1 : 0,
    'notification_ids': jsonEncode(notificationIds),
    'created_at': createdAt,
    'priority': priority,
  };

  factory Task.fromMap(Map<String, dynamic> map) => Task(
    id: map['id'] as int?,
    title: map['title'] as String,
    type: map['type'] as String,
    dueDate: map['due_date'] as String?,
    recurrence: map['recurrence'] as String?,
    recurrenceEnd: map['recurrence_end'] as String?,
    skipWeekends: (map['skip_weekends'] as int? ?? 0) == 1,
    isCompleted: (map['is_completed'] as int? ?? 0) == 1,
    notificationIds: List<int>.from(jsonDecode(map['notification_ids'] as String? ?? '[]')),
    createdAt: map['created_at'] as String,
    priority: map['priority'] as String?,
  );
}
