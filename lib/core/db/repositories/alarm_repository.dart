import 'package:sqflite/sqflite.dart';
import '../../../models/alarm_model.dart';

class AlarmRepository {
  final Database _db;
  AlarmRepository(this._db);

  Future<int> insert(AlarmModel alarm) async {
    return _db.insert('alarms', alarm.toMap());
  }

  Future<List<AlarmModel>> getActiveAlarms() async {
    final maps = await _db.query(
      'alarms',
      where: 'is_active = 1',
      orderBy: 'alarm_time ASC',
    );
    return maps.map(AlarmModel.fromMap).toList();
  }

  Future<AlarmModel?> getNextAlarm() async {
    final now = DateTime.now();
    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // Prefer the next one-shot or recurring alarm still ahead today.
    final todayMaps = await _db.query(
      'alarms',
      where: 'is_active = 1 AND alarm_time > ?',
      whereArgs: [currentTime],
      orderBy: 'alarm_time ASC',
      limit: 1,
    );
    if (todayMaps.isNotEmpty) return AlarmModel.fromMap(todayMaps.first);

    // Fall back to the earliest recurring alarm (it fires again tomorrow).
    final tomorrowMaps = await _db.query(
      'alarms',
      where: "is_active = 1 AND recurrence != 'none'",
      orderBy: 'alarm_time ASC',
      limit: 1,
    );
    if (tomorrowMaps.isEmpty) return null;
    return AlarmModel.fromMap(tomorrowMaps.first);
  }

  Future<void> deactivate(int androidAlarmId) async {
    await _db.update(
      'alarms',
      {'is_active': 0},
      where: 'android_alarm_id = ?',
      whereArgs: [androidAlarmId],
    );
  }

  Future<void> deactivateById(int id) async {
    await _db.update(
      'alarms',
      {'is_active': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateAndroidId(int id, int androidAlarmId) async {
    await _db.update(
      'alarms',
      {'android_alarm_id': androidAlarmId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<AlarmModel>> searchByLabel(String query) async {
    final maps = await _db.query(
      'alarms',
      where: 'is_active = 1 AND LOWER(label) LIKE LOWER(?)',
      whereArgs: ['%$query%'],
    );
    return maps.map(AlarmModel.fromMap).toList();
  }

  Future<AlarmModel?> getLatest() async {
    final maps = await _db.query(
      'alarms',
      where: 'is_active = 1',
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return AlarmModel.fromMap(maps.first);
  }

  Future<bool> existsAtTime(String alarmTime) async {
    final maps = await _db.query(
      'alarms',
      where: 'alarm_time = ? AND is_active = 1',
      whereArgs: [alarmTime],
      limit: 1,
    );
    return maps.isNotEmpty;
  }

  Future<void> delete(int id) async {
    await _db.delete('alarms', where: 'id = ?', whereArgs: [id]);
  }
}
