import 'package:flutter/foundation.dart';

import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

/// Pilote l'état des favoris (US-04-05) : ensemble des ids favoris pour l'état
/// du bouton cœur, et liste complète pour le futur écran « Favoris ».
///
/// Mises à jour optimistes : le set est modifié immédiatement puis l'appel
/// réseau est joué ; en cas d'échec on effectue un rollback et l'exception est
/// relayée pour que l'écran affiche un toast.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._repository);

  final StreamRepository _repository;

  final Set<String> _favoritedIds = {};
  List<LiveStream> _favorites = const [];
  bool _loaded = false;
  bool _isLoading = false;

  List<LiveStream> get favorites => List.unmodifiable(_favorites);
  bool get isLoading => _isLoading;

  bool isFavorited(String streamId) => _favoritedIds.contains(streamId);

  /// Charge la liste des favoris une seule fois (peuple ids + liste). Silencieux
  /// en cas d'échec (ex. invité non connecté) : le bouton reste « non favori ».
  Future<void> ensureLoaded() async {
    if (_loaded || _isLoading) return;
    await load();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final favorites = await _repository.listFavorites();
      _favorites = favorites;
      _favoritedIds
        ..clear()
        ..addAll(favorites.map((s) => s.id));
      _loaded = true;
    } catch (_) {
      // Échec silencieux : on ne bloque pas l'UI sur l'état des favoris.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Ajoute/retire le flux des favoris (optimiste). Relance l'exception en cas
  /// d'échec réseau après rollback.
  Future<void> toggle(LiveStream stream) async {
    if (isFavorited(stream.id)) {
      await _remove(stream);
    } else {
      await _add(stream);
    }
  }

  Future<void> _add(LiveStream stream) async {
    _favoritedIds.add(stream.id);
    _favorites = [stream, ..._favorites.where((s) => s.id != stream.id)];
    notifyListeners();
    try {
      await _repository.addFavorite(stream.id);
    } catch (e) {
      _favoritedIds.remove(stream.id);
      _favorites = _favorites.where((s) => s.id != stream.id).toList();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _remove(LiveStream stream) async {
    final previousList = _favorites;
    _favoritedIds.remove(stream.id);
    _favorites = _favorites.where((s) => s.id != stream.id).toList();
    notifyListeners();
    try {
      await _repository.removeFavorite(stream.id);
    } catch (e) {
      _favoritedIds.add(stream.id);
      _favorites = previousList;
      notifyListeners();
      rethrow;
    }
  }
}
