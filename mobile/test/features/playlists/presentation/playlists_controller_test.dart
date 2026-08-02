import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlists_controller.dart';

Playlist _playlist(String id, String name, {int trackCount = 0}) => Playlist(
      id: id,
      name: name,
      description: null,
      isPublic: false,
      trackCount: trackCount,
      createdAt: DateTime(2026, 1, 2),
      updatedAt: DateTime(2026, 1, 2),
    );

class _FakePlaylistRepository implements PlaylistRepository {
  List<Playlist> playlists = const [];
  Object? listError;

  Object? createError;
  Object? renameError;
  Object? deleteError;

  int listCalls = 0;
  int createCalls = 0;
  int renameCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<Playlist>> list() async {
    listCalls++;
    if (listError != null) throw listError!;
    return playlists;
  }

  @override
  Future<Playlist> create(String name, String? description) async {
    createCalls++;
    if (createError != null) throw createError!;
    final created = _playlist('new', name);
    playlists = [...playlists, created];
    return created;
  }

  @override
  Future<Playlist> rename(String id, String name, String? description) async {
    renameCalls++;
    if (renameError != null) throw renameError!;
    final updated = _playlist(id, name);
    playlists = playlists.map((p) => p.id == id ? updated : p).toList();
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
    playlists = playlists.where((p) => p.id != id).toList();
  }

  @override
  Future<List<PlaylistTrack>> tracks(String id) async => const [];
}

void main() {
  group('PlaylistsController.load', () {
    test('succès : expose la liste, loading remis à faux', () async {
      final repo = _FakePlaylistRepository()
        ..playlists = [_playlist('p-1', 'Rock', trackCount: 3)];
      final controller = PlaylistsController(repo);

      await controller.load();

      expect(controller.playlists, hasLength(1));
      expect(controller.playlists.single.trackCount, 3);
      expect(controller.loading, isFalse);
      expect(controller.error, isNull);
    });

    test('erreur réseau : error renseigné + isNetworkError', () async {
      final repo = _FakePlaylistRepository()..listError = const NetworkException();
      final controller = PlaylistsController(repo);

      await controller.load();

      expect(controller.error, isNotNull);
      expect(controller.isNetworkError, isTrue);
      expect(controller.playlists, isEmpty);
    });
  });

  group('mutations rechargent la liste', () {
    test('create appelle create puis list', () async {
      final repo = _FakePlaylistRepository();
      final controller = PlaylistsController(repo);

      await controller.create('Nouvelle', null);

      expect(repo.createCalls, 1);
      expect(repo.listCalls, 1);
      expect(controller.playlists.map((p) => p.name), contains('Nouvelle'));
    });

    test('rename appelle rename puis list', () async {
      final repo = _FakePlaylistRepository()
        ..playlists = [_playlist('p-1', 'Rock')];
      final controller = PlaylistsController(repo);

      await controller.rename('p-1', 'Metal', null);

      expect(repo.renameCalls, 1);
      expect(repo.listCalls, 1);
      expect(controller.playlists.single.name, 'Metal');
    });

    test('delete appelle delete puis list', () async {
      final repo = _FakePlaylistRepository()
        ..playlists = [_playlist('p-1', 'Rock')];
      final controller = PlaylistsController(repo);

      await controller.delete('p-1');

      expect(repo.deleteCalls, 1);
      expect(repo.listCalls, 1);
      expect(controller.playlists, isEmpty);
    });

    test('create en doublon relaie ConflictException sans avaler', () async {
      final repo = _FakePlaylistRepository()
        ..createError = const ConflictException('Une playlist porte déjà ce nom');
      final controller = PlaylistsController(repo);

      await expectLater(
        controller.create('My Favorites', null),
        throwsA(isA<ConflictException>()),
      );
    });
  });
}
