import '../entities/playlist.dart';
import '../entities/playlist_track.dart';
import '../entities/track.dart';

/// Contrat de la couche data pour la gestion des playlists (principe D).
/// L'implémentation vit dans `data/repositories/`.
abstract class PlaylistRepository {
  /// Playlists de l'utilisateur, triées par date de création décroissante.
  Future<List<Playlist>> list();

  /// Crée une playlist vide. 409 (nom déjà utilisé) remonte en exception typée.
  Future<Playlist> create(String name, String? description);

  /// Renomme/décrit une playlist. 404 si tiers, 409 si nom déjà utilisé.
  Future<Playlist> rename(String id, String name, String? description);

  /// Supprime définitivement une playlist.
  Future<void> delete(String id);

  /// Pistes d'une playlist, ordonnées par position.
  Future<List<PlaylistTrack>> tracks(String id);

  /// Bibliothèque de pistes de l'utilisateur (source du sélecteur d'ajout).
  Future<List<Track>> libraryTracks();

  /// Ajoute une piste en fin de playlist et retourne l'ordre résultant.
  /// 404 si la playlist ou la piste appartient à un tiers, 409 si la piste y est
  /// déjà.
  Future<List<PlaylistTrack>> addTrack(String playlistId, String trackId);

  /// Retire une piste de la playlist ; le serveur recompacte les positions.
  Future<void> removeTrack(String playlistId, String trackId);

  /// Remplace l'ordre complet de la playlist (index 0 = première piste) et
  /// retourne l'ordre persisté. 409 si l'ordre envoyé ne correspond plus à la
  /// playlist.
  Future<List<PlaylistTrack>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  );
}
