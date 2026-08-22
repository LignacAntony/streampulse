class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.userId,
    required this.username,
    required this.content,
    required this.createdAt,
    this.isDeleted = false,
  });

  final String id;
  final String userId;
  final String username;
  final String content;
  final DateTime createdAt;
  final bool isDeleted;

  ChatMessage copyWith({bool? isDeleted}) {
    return ChatMessage(
      id: id,
      userId: userId,
      username: username,
      content: content,
      createdAt: createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }
}
