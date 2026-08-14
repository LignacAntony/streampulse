import 'package:equatable/equatable.dart';

/// Flux en direct tel que vu par un administrateur (`GET /api/admin/streams`) :
/// tous les flux live, publics et privés, avec l'identité du diffuseur.
class AdminStream extends Equatable {
  const AdminStream({
    required this.id,
    required this.title,
    required this.isPublic,
    required this.startedAt,
    required this.userId,
    required this.username,
  });

  final String id;
  final String title;
  final bool isPublic;
  final DateTime? startedAt;
  final String userId;
  final String username;

  @override
  List<Object?> get props => [
    id,
    title,
    isPublic,
    startedAt,
    userId,
    username,
  ];
}
