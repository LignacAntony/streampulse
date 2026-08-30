class BannedUser {
  const BannedUser({
    required this.userId,
    required this.username,
    this.reason,
    required this.createdAt,
  });

  final String userId;
  final String username;
  final String? reason;
  final DateTime createdAt;
}
