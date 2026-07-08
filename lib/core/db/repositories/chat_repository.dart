import 'package:sqflite/sqflite.dart';
import '../../../models/chat_message.dart';

class ChatRepository {
  final Database _db;
  ChatRepository(this._db);

  Future<void> insert(ChatMessage message) async {
    await _db.insert('chat_history', message.toMap());
    await pruneOld();
  }

  Future<List<ChatMessage>> getRecent(int limit) async {
    final maps = await _db.query(
      'chat_history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return maps.map(ChatMessage.fromMap).toList().reversed.toList();
  }

  Future<void> pruneOld() async {
    await _db.rawDelete('''
      DELETE FROM chat_history
      WHERE id NOT IN (
        SELECT id FROM chat_history ORDER BY created_at DESC LIMIT 50
      )
    ''');
  }
}
