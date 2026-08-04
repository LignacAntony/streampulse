import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/repositories/playlist_repository.dart';

/// Pilote `PlaylistsScreen` : liste des playlists de l'utilisateur et mutations
/// (création, renommage, suppression).
///
/// Les mutations ne sont PAS optimistes : elles appellent le repository puis
/// rechargent la liste, et relaient l'exception à l'appelant (l'écran) pour
/// afficher un toast — en particulier `ConflictException` (nom déjà utilisé).
/// Seul `load` expose `error`/`isNetworkError` en état (vue plein écran).
class PlaylistsController extends ChangeNotifier {
  PlaylistsController(this._repository);

  final PlaylistRepository _repository;

  List<Playlist> _playlists = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  List<Playlist> get playlists => _playlists;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  /// (Re)charge la liste des playlists.
  Future<void> load() async {
    _loading = true;
    _clearError();
    notifyListeners();
    try {
      _playlists = await _repository.list();
    } catch (e) {
      _setError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Crée une playlist puis recharge la liste. Relaie l'exception à l'appelant.
  ///
  /// Le `finally { load() }` garantit un rafraîchissement même en cas d'échec :
  /// une mutation qui échoue (ex. 404 si la ressource a été supprimée depuis un
  /// autre appareil) ne doit pas laisser la liste dans un état périmé (carte
  /// fantôme). L'exception est tout de même propagée pour le toast.
  Future<void> create(String name, String? description) async {
    try {
      await _repository.create(name, description);
    } finally {
      await load();
    }
  }

  /// Renomme une playlist puis recharge la liste. Relaie l'exception.
  Future<void> rename(String id, String name, String? description) async {
    try {
      await _repository.rename(id, name, description);
    } finally {
      await load();
    }
  }

  /// Supprime une playlist puis recharge la liste. Relaie l'exception.
  Future<void> delete(String id) async {
    try {
      await _repository.delete(id);
    } finally {
      await load();
    }
  }

  void _setError(Object error) {
    _error = _messageFor(error);
    _isNetworkError = error is NetworkException;
  }

  void _clearError() {
    _error = null;
    _isNetworkError = false;
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Impossible de charger les playlists';
  }
}
