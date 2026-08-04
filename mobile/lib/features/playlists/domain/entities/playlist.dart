import 'package:equatable/equatable.dart';

/// Playlist de l'utilisateur (US-05-02). Entité domaine pure : aucune
/// dépendance au client généré ou à l'infra.
class Playlist extends Equatable {
  const Playlist({
    required this.id,
    required this.name,
    required this.description,
    required this.isPublic,
    required this.trackCount,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final bool isPublic;
  final int trackCount;
  final DateTime createdAt;
  final DateTime updatedAt;

  Playlist copyWith({
    String? id,
    String? name,
    String? description,
    bool? isPublic,
    int? trackCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isPublic: isPublic ?? this.isPublic,
      trackCount: trackCount ?? this.trackCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        isPublic,
        trackCount,
        createdAt,
        updatedAt,
      ];
}
