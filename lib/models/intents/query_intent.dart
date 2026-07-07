import 'base_intent.dart';

class QueryIntent extends BaseIntent {
  final String filter; // 'today' | 'week' | 'all' | 'overdue' | 'list'
  final String? listName; // set when filter == 'list'

  const QueryIntent({required this.filter, this.listName}) : super('query');

  factory QueryIntent.fromMap(Map<String, dynamic> map) => QueryIntent(
        filter: map['filter'] as String? ?? 'today',
        listName: map['list_name'] as String?,
      );
}
