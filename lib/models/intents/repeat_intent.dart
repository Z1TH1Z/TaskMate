import 'base_intent.dart';

class RepeatIntent extends BaseIntent {
  final int offsetMinutes; // reschedule from now + this many minutes

  const RepeatIntent({required this.offsetMinutes}) : super('repeat');

  factory RepeatIntent.fromMap(Map<String, dynamic> map) => RepeatIntent(
        offsetMinutes: map['offset_minutes'] as int? ?? 30,
      );
}
