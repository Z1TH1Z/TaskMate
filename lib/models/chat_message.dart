class ChatMessage {
  final int? id;
  final String role; // 'user' | 'assistant'
  final String content;
  final String createdAt;

  ChatMessage({
    this.id,
    required this.role,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'role': role,
    'content': content,
    'created_at': createdAt,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> map) => ChatMessage(
    id: map['id'] as int?,
    role: map['role'] as String,
    content: map['content'] as String,
    createdAt: map['created_at'] as String,
  );

  Map<String, String> toGroqFormat() => {'role': role, 'content': content};
}
