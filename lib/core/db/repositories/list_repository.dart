import 'package:sqflite/sqflite.dart';
import '../../../models/task_list.dart';
import '../../../models/list_item.dart';

class ListRepository {
  final Database _db;
  ListRepository(this._db);

  Future<int> insertList(TaskList list) async {
    return _db.insert('lists', list.toMap());
  }

  Future<List<TaskList>> getLists() async {
    final maps = await _db.query('lists', orderBy: 'created_at DESC');
    return maps.map(TaskList.fromMap).toList();
  }

  Future<TaskList?> getListByName(String name) async {
    final maps = await _db.query(
      'lists',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [name],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return TaskList.fromMap(maps.first);
  }

  Future<List<TaskList>> searchLists(String query) async {
    final maps = await _db.query(
      'lists',
      where: 'LOWER(name) LIKE LOWER(?) OR LOWER(category) LIKE LOWER(?)',
      whereArgs: ['%$query%', '%$query%'],
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

  Future<List<ListItem>> searchItemsByTitle(int listId, String query) async {
    final maps = await _db.query(
      'list_items',
      where: 'list_id = ? AND LOWER(title) LIKE LOWER(?)',
      whereArgs: [listId, '%$query%'],
    );
    return maps.map(ListItem.fromMap).toList();
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
}
