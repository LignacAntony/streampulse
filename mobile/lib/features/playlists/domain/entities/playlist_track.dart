import 'package:equatable/equatable.dart';

/// Piste au sein d'une playlist (US-05-02). artist et durationS sont nullables
/// (la table tracks les autorise nuls).
class PlaylistTrack extends Equatable {
  const PlaylistTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationS,
    required this.position,
  });

  final String id;
  final String title;
  final String? artist;
  final int? durationS;
  final int position;

  @override
  List<Object?> get props => [id, title, artist, durationS, position];
}
