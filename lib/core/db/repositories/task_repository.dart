import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../../models/task.dart';

class TaskRepository {
  final Database _db;
  TaskRepository(this._db);

  Future<int> insert(Task task) async {
    return _db.insert('tasks', task.toMap());
  }

  Future<List<Task>> getAll() async {
    final maps = await _db.query('tasks', orderBy: 'created_at DESC');
    return maps.map(Task.fromMap).toList();
  }

  Future<List<Task>> getActive() async {
    final maps = await _db.query(
      'tasks',
      where: 'is_completed = 0',
      orderBy: 'created_at DESC',
    );
    return maps.map(Task.fromMap).toList();
  }

  Future<List<Task>> getTasksDueToday() async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final maps = await _db.query(
      'tasks',
      where: "due_date LIKE ? AND is_completed = 0",
      whereArgs: ['$dateStr%'],
    );
    return maps.map(Task.fromMap).toList();
  }

  Future<List<Task>> getOverdue() async {
    final today = DateTime.now();
    final dateStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final maps = await _db.query(
      'tasks',
      where: "due_date < ? AND is_completed = 0 AND due_date IS NOT NULL",
      whereArgs: [dateStr],
    );
    return maps.map(Task.fromMap).toList();
  }

  Future<List<Task>> searchByTitle(String term) async {
    final maps = await _db.query(
      'tasks',
      where: 'title LIKE ? AND is_completed = 0',
      whereArgs: ['%$term%'],
    );
    return maps.map(Task.fromMap).toList();
  }

  Future<void> markComplete(int id) async {
    await _db.update(
      'tasks',
      {'is_completed': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markActive(int id) async {
    await _db.update(
      'tasks',
      {'is_completed': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateNotificationIds(int id, List<int> ids) async {
    await _db.update(
      'tasks',
      {'notification_ids': jsonEncode(ids)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearTodayNotifications(int id) async {
    await _db.update(
      'tasks',
      {'notification_ids': '[]'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Task>> getByType(String type) async {
    final maps = await _db.query(
      'tasks',
      where: 'type = ? AND is_completed = 0',
      whereArgs: [type],
      orderBy: 'due_date ASC',
    );
    return maps.map(Task.fromMap).toList();
  }

  Future<Task?> getLatestByType(String type) async {
    final maps = await _db.query(
      'tasks',
      where: 'type = ? AND is_completed = 0',
      whereArgs: [type],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Task.fromMap(maps.first);
  }

  Future<void> updateDueDate(int id, String newDueDate) async {
    await _db.update(
      'tasks',
      {'due_date': newDueDate},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    await _db.delete('tasks', where: 'id = ?', whereArgs: [id]);
  }
}
