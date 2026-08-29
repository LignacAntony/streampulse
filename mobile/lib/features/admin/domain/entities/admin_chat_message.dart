class AdminChatMessage {
  const AdminChatMessage({
    required this.id,
    required this.streamId,
    required this.username,
    required this.content,
    required this.createdAt,
    required this.streamTitle,
  });

  final String id;
  final String streamId;
  final String username;
  final String content;
  final DateTime createdAt;
  final String streamTitle;
}
