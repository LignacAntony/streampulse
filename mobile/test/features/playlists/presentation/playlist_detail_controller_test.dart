import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_detail_controller.dart';

PlaylistTrack _track(String id, int position) => PlaylistTrack(
      id: id,
      title: 'Titre $id',
      artist: null,
      durationS: null,
      position: position,
    );

/// Fake orienté pistes : `tracks` renvoie l'état courant, les mutations le font
/// évoluer comme le ferait le serveur (positions recompactées).
class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository({List<PlaylistTrack>? initial})
      : _tracks = initial ?? [];

  List<PlaylistTrack> _tracks;
  List<Track> library = const [];

  Object? tracksError;
  Object? addError;
  Object? removeError;
  Object? reorderError;

  int reorderCalls = 0;
  List<String>? lastOrder;

  @override
  Future<List<PlaylistTrack>> tracks(String id) async {
    if (tracksError != null) throw tracksError!;
    return _tracks;
  }

  @override
  Future<List<Track>> libraryTracks() async => library;

  @override
  Future<List<PlaylistTrack>> addTrack(
    String playlistId,
    String trackId,
  ) async {
    if (addError != null) throw addError!;
    _tracks = [..._tracks, _track(trackId, _tracks.length)];
    return _tracks;
  }

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {
    if (removeError != null) throw removeError!;
    _tracks = _reindex(_tracks.where((t) => t.id != trackId).toList());
  }

  @override
  Future<List<PlaylistTrack>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    reorderCalls++;
    lastOrder = trackIds;
    if (reorderError != null) throw reorderError!;
    _tracks = _reindex(
      trackIds.map((id) => _tracks.firstWhere((t) => t.id == id)).toList(),
    );
    return _tracks;
  }

  List<PlaylistTrack> _reindex(List<PlaylistTrack> tracks) => [
        for (var i = 0; i < tracks.length; i++) _track(tracks[i].id, i),
      ];

  // Non sollicitées par l'écran de détail.
  @override
  Future<List<Playlist>> list() async => const [];

  @override
  Future<Playlist> create(String name, String? description) =>
      throw UnimplementedError();

  @override
  Future<Playlist> rename(String id, String name, String? description) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String id) => throw UnimplementedError();
}

void main() {
  group('PlaylistDetailController.load', () {
    test('expose les pistes triées et remet loading à faux', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1)],
      );
      final controller = PlaylistDetailController(repo, 'p1');

      await controller.load();

      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
    });

    test('erreur réseau : message dédié et drapeau isNetworkError', () async {
      final repo = _FakePlaylistRepository()..tracksError = const NetworkException();
      final controller = PlaylistDetailController(repo, 'p1');

      await controller.load();

      expect(controller.error, 'Pas de connexion réseau');
      expect(controller.isNetworkError, isTrue);
    });

    test('erreur réseau avec fallback hors ligne : pistes du cache', () async {
      final cached = [_track('c1', 0), _track('c2', 1)];
      final repo = _FakePlaylistRepository()
        ..tracksError = const NetworkException();
      final controller = PlaylistDetailController(
        repo,
        'p1',
        offlineFallback: (_) async => cached,
      );

      await controller.load();

      expect(controller.error, isNull);
      expect(controller.isOfflineFallback, isTrue);
      expect(controller.tracks.map((t) => t.id), ['c1', 'c2']);
    });

    test('erreur réseau avec fallback vide : affiche l\'erreur', () async {
      final repo = _FakePlaylistRepository()
        ..tracksError = const NetworkException();
      final controller = PlaylistDetailController(
        repo,
        'p1',
        offlineFallback: (_) async => [],
      );

      await controller.load();

      expect(controller.error, isNotNull);
      expect(controller.isOfflineFallback, isFalse);
    });

    test('succès réseau remet isOfflineFallback à faux', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0)],
      );
      final controller = PlaylistDetailController(
        repo,
        'p1',
        offlineFallback: (_) async => [_track('c1', 0)],
      );

      // Première charge échoue → fallback
      repo.tracksError = const NetworkException();
      await controller.load();
      expect(controller.isOfflineFallback, isTrue);

      // Deuxième charge réussit → plus en fallback
      repo.tracksError = null;
      await controller.load();
      expect(controller.isOfflineFallback, isFalse);
      expect(controller.tracks.map((t) => t.id), ['t1']);
    });
  });

  group('PlaylistDetailController.reorder', () {
    test('persiste l\'ordre complet et renumérote les positions', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1), _track('t3', 2)],
      );
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      // Déplacer la 3e piste en tête (newIndex exprimé avant retrait).
      await controller.reorder(2, 0);

      expect(repo.lastOrder, ['t3', 't1', 't2']);
      expect(controller.tracks.map((t) => t.id), ['t3', 't1', 't2']);
      expect(controller.tracks.map((t) => t.position), [0, 1, 2]);
    });

    test('descendre une piste tient compte du décalage de newIndex', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1), _track('t3', 2)],
      );
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      // ReorderableListView passe newIndex = 3 pour « mettre t1 en dernier ».
      await controller.reorder(0, 3);

      expect(repo.lastOrder, ['t2', 't3', 't1']);
    });

    test('déplacement nul : aucun appel réseau', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1)],
      );
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await controller.reorder(0, 1);

      expect(repo.reorderCalls, 0);
      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
    });

    test('échec réseau : l\'ordre précédent est restauré et l\'erreur relayée',
        () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1)],
      )..reorderError = const NetworkException();
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await expectLater(
        controller.reorder(1, 0),
        throwsA(isA<NetworkException>()),
      );
      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
    });

    test('409 : la liste est rechargée depuis le serveur', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1)],
      )..reorderError = const ConflictException();
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await expectLater(
        controller.reorder(1, 0),
        throwsA(isA<ConflictException>()),
      );
      // Le fake n'a pas muté : le rechargement redonne l'ordre serveur.
      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
    });
  });

  group('PlaylistDetailController.removeTrack', () {
    test('retire la piste et renumérote', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1), _track('t3', 2)],
      );
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await controller.removeTrack('t2');

      expect(controller.tracks.map((t) => t.id), ['t1', 't3']);
      expect(controller.tracks.map((t) => t.position), [0, 1]);
    });

    test('échec : la piste est remise en place', () async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 0), _track('t2', 1)],
      )..removeError = const NetworkException();
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await expectLater(
        controller.removeTrack('t2'),
        throwsA(isA<NetworkException>()),
      );
      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
    });
  });

  group('PlaylistDetailController.addTrack', () {
    test('ajoute la piste en fin de liste', () async {
      final repo = _FakePlaylistRepository(initial: [_track('t1', 0)]);
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await controller.addTrack('t2');

      expect(controller.tracks.map((t) => t.id), ['t1', 't2']);
    });

    test('409 relayé à l\'appelant', () async {
      final repo = _FakePlaylistRepository()
        ..addError = const ConflictException('Cette piste est déjà dans la playlist');
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      await expectLater(
        controller.addTrack('t1'),
        throwsA(isA<ConflictException>()),
      );
    });
  });

  group('PlaylistDetailController.availableTracks', () {
    test('exclut les pistes déjà présentes dans la playlist', () async {
      final repo = _FakePlaylistRepository(initial: [_track('t1', 0)])
        ..library = const [
          Track(id: 't1', title: 'A', artist: null, durationS: null),
          Track(id: 't2', title: 'B', artist: null, durationS: null),
        ];
      final controller = PlaylistDetailController(repo, 'p1');
      await controller.load();

      final available = await controller.availableTracks();

      expect(available.map((t) => t.id), ['t2']);
    });
  });
}
