import '../../domain/entities/user.dart';

// Couche data — sérialisation JSON depuis l'API. Convertit en User pur via toEntity().
class UserModel {
  const UserModel({
    required this.id,
    required this.email,
    required this.username,
    required this.role,
    required this.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
      role: json['role'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final String id;
  final String email;
  final String username;
  final String role;
  final DateTime createdAt;

  User toEntity() => User(
        id: id,
        email: email,
        username: username,
        role: role,
        createdAt: createdAt,
      );
}
