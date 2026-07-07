import 'base_intent.dart';

class RescheduleIntent extends BaseIntent {
  final String searchTerm;
  final String? newTime;     // HH:MM — for alarms
  final String? newDatetime; // YYYY-MM-DD HH:MM — for reminders

  const RescheduleIntent({
    required this.searchTerm,
    this.newTime,
    this.newDatetime,
  }) : super('reschedule');

  factory RescheduleIntent.fromMap(Map<String, dynamic> map) => RescheduleIntent(
        searchTerm: map['search_term'] as String? ?? '',
        newTime: map['new_time'] as String?,
        newDatetime: map['new_datetime'] as String?,
      );
}
