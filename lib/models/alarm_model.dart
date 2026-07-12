class AlarmModel {
  final int? id;
  final String label;
  final String alarmTime; // HH:MM
  final String recurrence; // 'none' | 'daily' | 'weekdays'
  final bool isActive;
  final int? androidAlarmId;
  final String createdAt;

  AlarmModel({
    this.id,
    required this.label,
    required this.alarmTime,
    this.recurrence = 'none',
    this.isActive = true,
    this.androidAlarmId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'label': label,
    'alarm_time': alarmTime,
    'recurrence': recurrence,
    'is_active': isActive ? 1 : 0,
    'android_alarm_id': androidAlarmId,
    'created_at': createdAt,
  };

  factory AlarmModel.fromMap(Map<String, dynamic> map) => AlarmModel(
    id: map['id'] as int?,
    label: map['label'] as String,
    alarmTime: map['alarm_time'] as String,
    recurrence: map['recurrence'] as String? ?? 'none',
    isActive: (map['is_active'] as int? ?? 1) == 1,
    androidAlarmId: map['android_alarm_id'] as int?,
    createdAt: map['created_at'] as String,
  );

  /// The next [DateTime] this alarm will ring relative to [now]: later today if
  /// its time is still ahead, otherwise the next day (weekday alarms skip the
  /// weekend). `alarmTime` is always a well-formed 'HH:MM'; a malformed value
  /// falls back to 00:00 rather than throwing.
  DateTime nextFire(DateTime now) {
    final p = alarmTime.split(':');
    var dt = DateTime(
      now.year,
      now.month,
      now.day,
      int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0,
      int.tryParse(p.length > 1 ? p[1] : '') ?? 0,
    );
    if (!dt.isAfter(now)) dt = dt.add(const Duration(days: 1));
    if (recurrence == 'weekdays') {
      while (dt.weekday == DateTime.saturday ||
          dt.weekday == DateTime.sunday) {
        dt = dt.add(const Duration(days: 1));
      }
    }
    return dt;
  }
}
