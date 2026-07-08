import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import '../scheduler/alarm_service.dart';

/// Exports and restores the user's task data as a single JSON file.
///
/// We deliberately export/import JSON rather than copying the raw SQLite file:
/// it's schema-version independent, doesn't fight the open DB handle or WAL
/// files, and stays readable. The four data tables are backed up (chat history
/// is intentionally excluded), along with the SharedPreferences keys the
/// schedulers need to re-arm reminders/recurring after a restore.
class BackupService {
  static const int _formatVersion = 1;

  /// Pref key prefixes that carry scheduling state tied to a notification id.
  static const _prefPrefixes = <String>[
    'reminder_title_',
    'reminder_body_',
    'recur_title_',
    'recur_skip_',
    'recur_end_',
    'recur_time_',
    'recur_freq_',
    'recur_weekday_',
  ];

  /// Build the backup JSON string from the current database + prefs.
  static Future<String> buildJson() async {
    final db = await DatabaseHelper.instance.database;
    final prefs = await SharedPreferences.getInstance();

    final payload = <String, dynamic>{
      'app': 'TaskMate',
      'format_version': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'tasks': await db.query('tasks'),
      'alarms': await db.query('alarms'),
      'lists': await db.query('lists'),
      'list_items': await db.query('list_items'),
      'prefs': _collectPrefs(prefs),
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  /// Write the backup to a file the app can share, returning its path. The file
  /// is written to the temp/cache directory, which share_plus's bundled
  /// FileProvider is configured to serve (the sqflite databases dir is not).
  static Future<String> writeBackupFile() async {
    final json = await buildJson();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}';
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'taskmate_backup_$stamp.json');
    await File(path).writeAsString(json);
    return path;
  }

  /// Restore from a backup file. REPLACES all current task data (chat history
  /// is left untouched), then re-arms alarms/reminders/recurring. Returns a
  /// short human-readable summary. Throws [FormatException] on an invalid file.
  static Future<String> restoreFromPath(String path) async {
    final raw = await File(path).readAsString();
    return restoreFromJson(raw);
  }

  static Future<String> restoreFromJson(String raw) async {
    late final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Not a TaskMate backup');
      }
      data = decoded;
    } catch (_) {
      throw const FormatException('That file is not a valid TaskMate backup.');
    }
    if (data['app'] != 'TaskMate' || data['tasks'] == null) {
      throw const FormatException('That file is not a valid TaskMate backup.');
    }

    final tasks = _rows(data['tasks']);
    final alarms = _rows(data['alarms']);
    final lists = _rows(data['lists']);
    final listItems = _rows(data['list_items']);

    final db = await DatabaseHelper.instance.database;

    // Cancel everything currently scheduled BEFORE wiping — otherwise old
    // native alarms (which ring straight from AlarmReceiver without consulting
    // the DB) would keep firing even though their rows are gone.
    await _cancelAllCurrentlyScheduled(db);

    // Replace the four data tables atomically. Insert lists before list_items
    // so the foreign key holds.
    await db.transaction((txn) async {
      await txn.delete('list_items');
      await txn.delete('lists');
      await txn.delete('tasks');
      await txn.delete('alarms');

      for (final row in lists) {
        await txn.insert('lists', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in listItems) {
        await txn.insert('list_items', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in tasks) {
        await txn.insert('tasks', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in alarms) {
        await txn.insert('alarms', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    // Restore scheduling prefs so recurring/reminder alarms can be re-armed.
    await _restorePrefs(data['prefs']);

    // Re-arm everything from the freshly restored data.
    await AlarmService().rearmAllFromDb();

    return 'Restored ${tasks.length} task(s), ${lists.length} list(s), '
        '${alarms.length} alarm(s).';
  }

  // ---- helpers ----

  /// Cancel every alarm/reminder/recurring the app currently has scheduled,
  /// based on the live DB, so a restore starts from a clean slate.
  static Future<void> _cancelAllCurrentlyScheduled(Database db) async {
    final alarmSvc = AlarmService();
    try {
      final alarms = await db.query('alarms', where: 'is_active = 1');
      for (final a in alarms) {
        final aid = a['android_alarm_id'] as int?;
        if (aid != null) await alarmSvc.cancelAlarm(aid);
      }
    } catch (_) {}
    try {
      final tasks = await db.query('tasks', where: 'is_completed = 0');
      for (final t in tasks) {
        final ids = (jsonDecode((t['notification_ids'] as String?) ?? '[]')
                as List)
            .map((e) => e as int);
        for (final id in ids) {
          await alarmSvc.cancelReminder(id);
        }
      }
    } catch (_) {}
  }

  static List<Map<String, Object?>> _rows(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((m) => m.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  static Map<String, dynamic> _collectPrefs(SharedPreferences prefs) {
    final out = <String, dynamic>{};
    for (final key in prefs.getKeys()) {
      if (_prefPrefixes.any(key.startsWith)) {
        out[key] = prefs.get(key);
      }
    }
    return out;
  }

  static Future<void> _restorePrefs(dynamic raw) async {
    if (raw is! Map) return;
    final prefs = await SharedPreferences.getInstance();
    raw.forEach((key, value) {
      final k = key.toString();
      if (!_prefPrefixes.any(k.startsWith)) return;
      if (value is bool) {
        prefs.setBool(k, value);
      } else if (value is int) {
        prefs.setInt(k, value);
      } else if (value is String) {
        prefs.setString(k, value);
      }
    });
  }
}
