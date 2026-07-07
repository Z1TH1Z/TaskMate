import 'base_intent.dart';

class ListIntentItem {
  final String title;
  final String? notes;
  const ListIntentItem({required this.title, this.notes});
  factory ListIntentItem.fromMap(Map<String, dynamic> map) =>
      ListIntentItem(title: map['title'] as String, notes: map['notes'] as String?);
}

class ListIntent extends BaseIntent {
  final String action; // 'create' | 'add'
  final String listName;
  final String category;
  final List<ListIntentItem> items;

  const ListIntent({
    required this.action,
    required this.listName,
    required this.category,
    required this.items,
  }) : super('list');

  factory ListIntent.fromMap(Map<String, dynamic> map) => ListIntent(
    action: map['action'] as String? ?? 'add',
    listName: map['list_name'] as String,
    category: map['category'] as String? ?? 'general',
    items: (map['items'] as List? ?? [])
        .map((i) => ListIntentItem.fromMap(i as Map<String, dynamic>))
        .toList(),
  );
}
