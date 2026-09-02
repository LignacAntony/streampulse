import 'package:flutter/foundation.dart';

import '../../domain/entities/playlist.dart';
import '../../domain/repositories/playlist_repository.dart';

/// Pilote la vitrine « playlists favorites » de l'accueil (STR-250).
///
/// App-level, même patron que [FavoritesController] (flux) : une liste chargée
/// via l'endpoint dédié `GET /api/playlists/favorites` (pas de sur-lecture de
/// toutes les playlists), rechargée à l'arrivée sur l'accueil, et **remise à
/// zéro au logout** — sinon la vitrine garderait les favoris du compte
/// déconnecté et `ensureLoaded` serait un no-op au login suivant.
///
/// L'épinglage se fait ailleurs (Bibliothèque, détail) : ce contrôleur ne fait
/// que lire. Il se resynchronise au retour sur l'accueil.
class FavoritePlaylistsController extends ChangeNotifier {
  FavoritePlaylistsController(this._repository);

  final PlaylistRepository _repository;

  List<Playlist> _favorites = const [];
  bool _loaded = false;
  bool _isLoading = false;

  List<Playlist> get favorites => List.unmodifiable(_favorites);
  bool get isLoading => _isLoading;

  void reset() {
    _favorites = const [];
    _loaded = false;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    if (_loaded || _isLoading) return;
    await load();
  }

  /// (Re)charge les playlists favorites. Silencieux en cas d'échec (invité, ou
  /// réseau KO) : la vitrine est un ornement, elle ne bloque pas l'accueil.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _favorites = await _repository.listFavorites();
      _loaded = true;
    } catch (_) {
      // Échec silencieux : on n'affiche simplement rien.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
