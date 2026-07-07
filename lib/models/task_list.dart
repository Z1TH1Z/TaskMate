class TaskList {
  final int? id;
  final String name;
  final String category; // 'movies' | 'anime' | 'books' | 'general'
  final String createdAt;

  TaskList({
    this.id,
    required this.name,
    this.category = 'general',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'category': category,
    'created_at': createdAt,
  };

  factory TaskList.fromMap(Map<String, dynamic> map) => TaskList(
    id: map['id'] as int?,
    name: map['name'] as String,
    category: map['category'] as String? ?? 'general',
    createdAt: map['created_at'] as String,
  );
}
