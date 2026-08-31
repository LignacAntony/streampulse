import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/offline/entities/offline_playlist_summary.dart';
import '../../../tracks/domain/repositories/track_repository.dart';
import '../../domain/entities/playlist.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/playlist_repository.dart';

/// Pilote `PlaylistsScreen` : playlists de l'utilisateur **et** sa bibliothèque
/// de pistes (affichée sous les playlists, US-05-01), plus les mutations
/// (création, renommage, suppression de playlist).
///
/// Les mutations ne sont PAS optimistes : elles appellent le repository puis
/// rechargent la liste, et relaient l'exception à l'appelant (l'écran) pour
/// afficher un toast — en particulier `ConflictException` (nom déjà utilisé).
/// Seul `load` expose `error`/`isNetworkError` en état (vue plein écran).
class PlaylistsController extends ChangeNotifier {
  PlaylistsController(
    this._repository,
    this._trackRepository, {
    Future<List<OfflinePlaylistSummary>> Function()? offlineFallback,
  }) : _offlineFallback = offlineFallback;

  final PlaylistRepository _repository;
  final TrackRepository _trackRepository;

  /// Playlists téléchargées, servies quand le réseau échoue (mode avion). Cf.
  /// `PlaylistDetailController._offlineFallback` : même patron de repli.
  final Future<List<OfflinePlaylistSummary>> Function()? _offlineFallback;

  List<Playlist> _playlists = const [];
  List<Track> _tracks = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;
  bool _isOfflineFallback = false;

  List<Playlist> get playlists => _playlists;
  List<Track> get tracks => _tracks;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  /// Vrai quand la liste affichée provient du cache hors ligne (réseau
  /// indisponible) : l'écran affiche alors un bandeau et masque les actions
  /// qui exigent le réseau (création, upload, « Mes pistes »).
  bool get isOfflineFallback => _isOfflineFallback;

  /// (Re)charge les playlists et la bibliothèque de pistes en parallèle. Les deux
  /// dépendent du même backend/auth : on les traite comme un seul chargement.
  Future<void> load() async {
    _loading = true;
    _clearError();
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.list(),
        _repository.libraryTracks(),
      ]);
      _playlists = results[0] as List<Playlist>;
      _tracks = results[1] as List<Track>;
      _isOfflineFallback = false;
    } catch (e) {
      await _handleLoadError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Repli hors ligne : si des playlists ont été téléchargées, les afficher au
  /// lieu de l'erreur plein écran ; sinon relayer l'erreur. La bibliothèque de
  /// pistes n'est pas cachée hors ligne (elle vit dans les playlists
  /// téléchargées), donc `_tracks` est vidé.
  Future<void> _handleLoadError(Object error) async {
    if (_offlineFallback != null) {
      try {
        final cached = await _offlineFallback();
        if (cached.isNotEmpty) {
          _playlists = cached.map(_toPlaylist).toList();
          _tracks = const [];
          _isOfflineFallback = true;
          _clearError();
          return;
        }
      } catch (_) {
        // Cache indisponible (web, test) : on retombe sur l'erreur d'origine.
      }
    }
    _setError(error);
  }

  /// Carte de playlist synthétisée depuis le cache : seuls id/nom/nombre de
  /// pistes sont connus hors ligne — les autres champs prennent une valeur
  /// neutre (jamais lue par la carte offline).
  Playlist _toPlaylist(OfflinePlaylistSummary summary) => Playlist(
        id: summary.id,
        name: summary.name,
        description: null,
        isPublic: false,
        trackCount: summary.trackCount,
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

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

  Future<void> deleteTrack(String id) async {
    try {
      await _trackRepository.deleteTrack(id);
    } finally {
      await load();
    }
  }

  Future<List<Playlist>> listPlaylists() => _repository.list();

  Future<void> addTrackToPlaylist(String playlistId, String trackId) async {
    try {
      await _repository.addTrack(playlistId, trackId);
    } finally {
      await load();
    }
  }

  Future<void> toggleTrackVisibility(String id, {required bool isPublic}) async {
    try {
      await _trackRepository.updateVisibility(id, isPublic: isPublic);
    } finally {
      await load();
    }
  }

  void _setError(Object error) {
    _error = _messageFor(error);
    _isNetworkError = error is NetworkException;
    _isOfflineFallback = false;
  }

  void _clearError() {
    _error = null;
    _isNetworkError = false;
  }

  String _messageFor(Object error) {
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Impossible de charger la bibliothèque';
  }
}
