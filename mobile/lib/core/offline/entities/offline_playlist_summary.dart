import 'package:equatable/equatable.dart';

/// Résumé d'une playlist téléchargée pour l'écoute hors ligne, lu depuis la
/// base locale (`offline_playlists` + `cached_tracks`). Sert à afficher la
/// Bibliothèque quand le réseau est indisponible : id, nom et nombre de
/// pistes suffisent à peupler une carte de playlist.
class OfflinePlaylistSummary extends Equatable {
  const OfflinePlaylistSummary({
    required this.id,
    required this.name,
    required this.trackCount,
  });

  final String id;
  final String name;
  final int trackCount;

  @override
  List<Object?> get props => [id, name, trackCount];
}
