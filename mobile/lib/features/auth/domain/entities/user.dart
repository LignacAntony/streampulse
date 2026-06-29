import 'package:equatable/equatable.dart';

class User extends Equatable {
  const User({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String username;
  final String role;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, email, username, role, createdAt];
}
