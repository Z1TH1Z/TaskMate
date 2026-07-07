class ListItem {
  final int? id;
  final int listId;
  final String title;
  final String? notes;
  final bool isDone;

  ListItem({
    this.id,
    required this.listId,
    required this.title,
    this.notes,
    this.isDone = false,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'list_id': listId,
    'title': title,
    'notes': notes,
    'is_done': isDone ? 1 : 0,
    'extra': '{}',
  };

  factory ListItem.fromMap(Map<String, dynamic> map) => ListItem(
    id: map['id'] as int?,
    listId: map['list_id'] as int,
    title: map['title'] as String,
    notes: map['notes'] as String?,
    isDone: (map['is_done'] as int? ?? 0) == 1,
  );
}
