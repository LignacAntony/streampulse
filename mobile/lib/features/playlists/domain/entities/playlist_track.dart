import 'package:equatable/equatable.dart';

import 'track.dart';

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

  /// Oublie la position pour ne garder que la piste (STR-231).
  ///
  /// La file d'attente joue des pistes, d'où qu'elles viennent : une playlist a
  /// un ordre, la bibliothèque non, et le lecteur n'a que faire de la
  /// différence. C'est [Track] qu'il reçoit dans les deux cas.
  Track toTrack() =>
      Track(id: id, title: title, artist: artist, durationS: durationS);

  @override
  List<Object?> get props => [id, title, artist, durationS, position];
}
