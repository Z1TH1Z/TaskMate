import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._();
  static Database? _db;

  DatabaseHelper._();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'taskmate.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tasks (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        title             TEXT    NOT NULL,
        type              TEXT    NOT NULL,
        due_date          TEXT,
        recurrence        TEXT,
        recurrence_end    TEXT,
        skip_weekends     INTEGER DEFAULT 0,
        is_completed      INTEGER DEFAULT 0,
        notification_ids  TEXT    DEFAULT '[]',
        created_at        TEXT    NOT NULL,
        priority          TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS alarms (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        label            TEXT    NOT NULL,
        alarm_time       TEXT    NOT NULL,
        recurrence       TEXT    DEFAULT 'none',
        is_active        INTEGER DEFAULT 1,
        android_alarm_id INTEGER,
        created_at       TEXT    NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS lists (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL,
        category   TEXT DEFAULT 'general',
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS list_items (
        id      INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER NOT NULL REFERENCES lists(id) ON DELETE CASCADE,
        title   TEXT    NOT NULL,
        notes   TEXT,
        is_done INTEGER DEFAULT 0,
        extra   TEXT    DEFAULT '{}'
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_history (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        role       TEXT NOT NULL,
        content    TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }
}
