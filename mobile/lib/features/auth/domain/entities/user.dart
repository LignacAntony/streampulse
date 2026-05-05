import 'package:equatable/equatable.dart';

// Entité pure — aucune dépendance infrastructure (Principe D + S).
// Les rôles possibles : 'anonymous' | 'user' | 'broadcaster' | 'admin'
class User extends Equatable {
  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String username;
  final String role;
  final String? avatarUrl;

  @override
  List<Object?> get props => [id, email, username, role, avatarUrl];
}
