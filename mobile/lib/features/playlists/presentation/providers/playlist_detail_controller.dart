import 'package:flutter/foundation.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/playlist_track.dart';
import '../../domain/entities/track.dart';
import '../../domain/repositories/playlist_repository.dart';

/// Pilote `PlaylistDetailScreen` : pistes d'une playlist et leurs mutations
/// (ajout, retrait, réordonnancement par drag-and-drop) — US-05-03.
///
/// Le réordonnancement et le retrait sont **optimistes** : la liste locale est
/// mise à jour avant l'appel réseau (le doigt de l'utilisateur a déjà déplacé la
/// ligne, attendre le serveur rendrait le geste saccadé), puis remplacée par la
/// réponse serveur. En cas d'échec l'ordre précédent est **restauré** et
/// l'exception est relayée à l'écran pour le toast — laisser l'écran afficher un
/// ordre qui n'existe pas en base serait pire qu'un retour visuel brutal.
class PlaylistDetailController extends ChangeNotifier {
  PlaylistDetailController(this._repository, this.playlistId);

  final PlaylistRepository _repository;
  final String playlistId;

  List<PlaylistTrack> _tracks = const [];
  bool _loading = false;
  String? _error;
  bool _isNetworkError = false;

  List<PlaylistTrack> get tracks => _tracks;
  bool get loading => _loading;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  /// (Re)charge les pistes de la playlist.
  Future<void> load() async {
    _loading = true;
    _clearError();
    notifyListeners();
    try {
      _tracks = await _repository.tracks(playlistId);
    } catch (e) {
      _setError(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => load();

  /// Bibliothèque de pistes de l'utilisateur, moins celles déjà présentes :
  /// proposer une piste qui renverrait un 409 n'a pas d'intérêt.
  Future<List<Track>> availableTracks() async {
    final library = await _repository.libraryTracks();
    final present = _tracks.map((t) => t.id).toSet();
    return library.where((t) => !present.contains(t.id)).toList();
  }

  /// Ajoute une piste en fin de playlist. Non optimiste : c'est le serveur qui
  /// attribue la position. Relaie l'exception (409 si déjà présente).
  Future<void> addTrack(String trackId) async {
    _tracks = await _repository.addTrack(playlistId, trackId);
    notifyListeners();
  }

  /// Retire une piste (optimiste + rollback). Le serveur recompacte les
  /// positions : on les recalcule localement pour rester cohérent sans recharger.
  Future<void> removeTrack(String trackId) async {
    final previous = _tracks;
    _tracks = _reindex(_tracks.where((t) => t.id != trackId).toList());
    notifyListeners();
    try {
      await _repository.removeTrack(playlistId, trackId);
    } catch (e) {
      _tracks = previous;
      notifyListeners();
      rethrow;
    }
  }

  /// Déplace la piste de [oldIndex] vers [newIndex] (optimiste + rollback) puis
  /// persiste l'ordre complet.
  ///
  /// [newIndex] suit la convention de `ReorderableListView` : il est exprimé
  /// **avant** retrait de l'élément déplacé, d'où le décalage quand on descend.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final previous = _tracks;
    final reordered = List<PlaylistTrack>.of(_tracks);
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (oldIndex == target) return;

    reordered.insert(target, reordered.removeAt(oldIndex));
    _tracks = _reindex(reordered);
    notifyListeners();

    try {
      _tracks = await _repository.reorderTracks(
        playlistId,
        reordered.map((t) => t.id).toList(),
      );
      notifyListeners();
    } catch (e) {
      // 409 : la playlist a changé ailleurs. Recharger donne l'état réel ;
      // pour toute autre erreur, l'ordre précédent reste la meilleure vérité
      // connue.
      if (e is ConflictException) {
        await load();
      } else {
        _tracks = previous;
        notifyListeners();
      }
      rethrow;
    }
  }

  /// Réattribue les positions 0..n-1 après une mutation locale (le serveur fait
  /// de même : les positions restent contiguës).
  List<PlaylistTrack> _reindex(List<PlaylistTrack> tracks) {
    return [
      for (var i = 0; i < tracks.length; i++)
        PlaylistTrack(
          id: tracks[i].id,
          title: tracks[i].title,
          artist: tracks[i].artist,
          durationS: tracks[i].durationS,
          position: i,
        ),
    ];
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
    return 'Impossible de charger les pistes';
  }
}
