import 'base_intent.dart';

class TodoIntent extends BaseIntent {
  final String title;
  final String? dueDate;
  final String priority;

  const TodoIntent({
    required this.title,
    this.dueDate,
    this.priority = 'medium',
  }) : super('todo');

  factory TodoIntent.fromMap(Map<String, dynamic> map) => TodoIntent(
    title: map['title'] as String,
    dueDate: map['due_date'] as String?,
    priority: map['priority'] as String? ?? 'medium',
  );
}
