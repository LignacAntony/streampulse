import '../entities/playlist.dart';
import '../entities/playlist_track.dart';

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
}
