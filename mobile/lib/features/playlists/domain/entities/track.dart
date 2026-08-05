import 'package:equatable/equatable.dart';

/// Piste de la bibliothèque de l'utilisateur (US-05-03), telle que proposée par
/// le sélecteur « ajouter une piste ». Contrairement à [PlaylistTrack], elle
/// n'appartient à aucune playlist et n'a donc pas de position.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationS,
  });

  final String id;
  final String title;
  final String? artist;
  final int? durationS;

  @override
  List<Object?> get props => [id, title, artist, durationS];
}
