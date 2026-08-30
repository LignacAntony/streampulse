import 'package:equatable/equatable.dart';

import '../../../playlists/domain/entities/track.dart';

/// Piste recommandée à l'utilisateur (US-09-04), avec la raison lisible fournie
/// par le serveur (« Parce que vous écoutez souvent X »). Enveloppe une [Track]
/// partagée avec les autres features : la file de lecture consomme des `Track`,
/// donc une recommandation peut partir en lecture sans conversion.
class RecommendedTrack extends Equatable {
  const RecommendedTrack({required this.track, required this.reason});

  final Track track;
  final String reason;

  @override
  List<Object?> get props => [track, reason];
}
