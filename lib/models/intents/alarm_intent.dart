import 'base_intent.dart';

class AlarmIntent extends BaseIntent {
  final List<String> times;
  final String label;
  final String recurrence;

  const AlarmIntent({
    required this.times,
    required this.label,
    required this.recurrence,
  }) : super('alarm');

  factory AlarmIntent.fromMap(Map<String, dynamic> map) => AlarmIntent(
    times: List<String>.from(map['times'] as List),
    label: map['label'] as String? ?? 'Alarm',
    recurrence: map['recurrence'] as String? ?? 'none',
  );
}
