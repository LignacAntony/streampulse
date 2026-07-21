import 'package:equatable/equatable.dart';

/// Utilisateur tel que vu par un administrateur (`GET /api/admin/users`).
class AdminUser extends Equatable {
  const AdminUser({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String username;
  final String role;
  final bool isActive;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, email, username, role, isActive, createdAt];
}
