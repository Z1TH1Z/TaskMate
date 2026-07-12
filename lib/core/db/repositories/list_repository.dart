import 'package:sqflite/sqflite.dart';
import '../../../models/task_list.dart';
import '../../../models/list_item.dart';

class ListRepository {
  final Database _db;
  ListRepository(this._db);

  /// Reserved category for the Daily Non-Negotiables sections. These live in the
  /// same `lists`/`list_items` tables but are owned by the Daily tab, so every
  /// user-facing list query below hides them (chat/LLM must never touch them).
  static const nonNegotiableCategory = 'nonnegotiable';

  Future<int> insertList(TaskList list) async {
    return _db.insert('lists', list.toMap());
  }

  Future<List<TaskList>> getLists() async {
    final maps = await _db.query(
      'lists',
      where: 'category != ?',
      whereArgs: [nonNegotiableCategory],
      orderBy: 'created_at DESC',
    );
    return maps.map(TaskList.fromMap).toList();
  }

  Future<TaskList?> getListByName(String name) async {
    final maps = await _db.query(
      'lists',
      where: 'LOWER(name) = LOWER(?) AND category != ?',
      whereArgs: [name, nonNegotiableCategory],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TaskList.fromMap(maps.first);
  }

  Future<List<TaskList>> searchLists(String query) async {
    final maps = await _db.query(
      'lists',
      where: '(LOWER(name) LIKE LOWER(?) OR LOWER(category) LIKE LOWER(?)) AND category != ?',
      whereArgs: ['%$query%', '%$query%', nonNegotiableCategory],
    );
    return maps.map(TaskList.fromMap).toList();
  }

  Future<int> insertItem(ListItem item) async {
    return _db.insert('list_items', item.toMap());
  }

  Future<List<ListItem>> getItems(int listId) async {
    final maps = await _db.query(
      'list_items',
      where: 'list_id = ?',
      whereArgs: [listId],
      orderBy: 'id ASC',
    );
    return maps.map(ListItem.fromMap).toList();
  }

  Future<void> markItemDone(int itemId) async {
    await _db.update(
      'list_items',
      {'is_done': 1},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  Future<void> deleteItem(int itemId) async {
    await _db.delete('list_items', where: 'id = ?', whereArgs: [itemId]);
  }

  Future<int> deleteItemsByTitle(int listId, String query) async {
    return _db.delete(
      'list_items',
      where: 'list_id = ? AND LOWER(title) LIKE LOWER(?)',
      whereArgs: [listId, '%$query%'],
    );
  }

  Future<void> deleteList(int listId) async {
    await _db.delete('list_items', where: 'list_id = ?', whereArgs: [listId]);
    await _db.delete('lists', where: 'id = ?', whereArgs: [listId]);
  }

  // ---- Daily Non-Negotiables ----

  /// The three fixed sections, in display order. The slug is a stable id used
  /// for prefs keys (reminder time / notification id); the name is what shows;
  /// the last field is the default daily reminder time ('HH:MM').
  static const nonNegotiableSections =
      <(String slug, String name, String defaultTime)>[
    ('intellectual', 'Intellectual', '09:00'),
    ('physical', 'Physical', '18:00'),
    ('spiritual', 'Spiritual', '21:00'),
  ];

  /// Ensure the three non-negotiable section lists exist (idempotent), then
  /// return them in the fixed [nonNegotiableSections] order.
  Future<List<TaskList>> ensureNonNegotiableSections() async {
    for (final (_, name, _) in nonNegotiableSections) {
      final existing = await _db.query(
        'lists',
        where: 'name = ? AND category = ?',
        whereArgs: [name, nonNegotiableCategory],
        limit: 1,
      );
      if (existing.isEmpty) {
        await _db.insert('lists', {
          'name': name,
          'category': nonNegotiableCategory,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
    final maps = await _db.query(
      'lists',
      where: 'category = ?',
      whereArgs: [nonNegotiableCategory],
    );
    final byName = {for (final m in maps) (m['name'] as String): TaskList.fromMap(m)};
    return [for (final (_, name, _) in nonNegotiableSections) byName[name]!];
  }

  /// Look up one non-negotiable section by its display name (case-insensitive).
  Future<TaskList?> getNonNegotiableByName(String name) async {
    final maps = await _db.query(
      'lists',
      where: 'LOWER(name) = LOWER(?) AND category = ?',
      whereArgs: [name, nonNegotiableCategory],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TaskList.fromMap(maps.first);
  }

  Future<void> setItemDone(int itemId, bool done) async {
    await _db.update(
      'list_items',
      {'is_done': done ? 1 : 0},
      where: 'id = ?',
      whereArgs: [itemId],
    );
  }

  /// Clear every done flag across all non-negotiable sections (the daily reset).
  Future<void> resetNonNegotiableDone() async {
    final lists = await _db.query(
      'lists',
      columns: ['id'],
      where: 'category = ?',
      whereArgs: [nonNegotiableCategory],
    );
    for (final l in lists) {
      await _db.update('list_items', {'is_done': 0},
          where: 'list_id = ?', whereArgs: [l['id']]);
    }
  }
}
