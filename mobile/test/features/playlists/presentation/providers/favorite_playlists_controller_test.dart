import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/providers/favorite_playlists_controller.dart';

Playlist _pl(String id) => Playlist(
      id: id,
      name: id,
      description: null,
      isPublic: false,
      trackCount: 0,
      isFavorite: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

/// Fake minimal : seule `listFavorites` est utilisée par ce contrôleur.
class _FakeRepo implements PlaylistRepository {
  int favCalls = 0;
  List<Playlist> favorites = const [];
  Completer<List<Playlist>>? gate;
  Object? error;

  @override
  Future<List<Playlist>> listFavorites() async {
    favCalls++;
    if (gate != null) return gate!.future;
    if (error != null) throw error!;
    return favorites;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  // Membres non sollicités.
  @override
  Future<List<Playlist>> list() => throw UnimplementedError();
  @override
  Future<Playlist> create(String name, String? description) =>
      throw UnimplementedError();
  @override
  Future<Playlist> rename(String id, String name, String? description) =>
      throw UnimplementedError();
  @override
  Future<void> delete(String id) => throw UnimplementedError();
  @override
  Future<void> favorite(String id) => throw UnimplementedError();
  @override
  Future<void> unfavorite(String id) => throw UnimplementedError();
  @override
  Future<List<PlaylistTrack>> tracks(String id) => throw UnimplementedError();
  @override
  Future<List<Track>> libraryTracks() => throw UnimplementedError();
  @override
  Future<List<PlaylistTrack>> addTrack(String playlistId, String trackId) =>
      throw UnimplementedError();
  @override
  Future<void> removeTrack(String playlistId, String trackId) =>
      throw UnimplementedError();
  @override
  Future<List<PlaylistTrack>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  ) =>
      throw UnimplementedError();
}

void main() {
  test('load expose la liste des favoris', () async {
    final repo = _FakeRepo()..favorites = [_pl('p1'), _pl('p2')];
    final controller = FavoritePlaylistsController(repo);

    await controller.load();

    expect(controller.favorites.map((p) => p.id), ['p1', 'p2']);
  });

  test('load a une garde in-flight : un 2e appel concurrent est ignoré',
      () async {
    final repo = _FakeRepo()..gate = Completer<List<Playlist>>();
    final controller = FavoritePlaylistsController(repo);

    final first = controller.load(); // en vol (bloqué sur le gate)
    await controller.load(); // doit retourner tout de suite, sans 2e appel

    expect(repo.favCalls, 1);

    repo.gate!.complete([_pl('p1')]);
    await first;
    expect(controller.favorites.single.id, 'p1');
  });

  test('échec silencieux : pas d\'exception, liste vide', () async {
    final repo = _FakeRepo()..error = Exception('boom');
    final controller = FavoritePlaylistsController(repo);

    await controller.load();

    expect(controller.favorites, isEmpty);
  });

  test('reset vide la liste et réautorise ensureLoaded', () async {
    final repo = _FakeRepo()..favorites = [_pl('p1')];
    final controller = FavoritePlaylistsController(repo);

    await controller.ensureLoaded();
    expect(controller.favorites, isNotEmpty);
    expect(repo.favCalls, 1);

    controller.reset();
    expect(controller.favorites, isEmpty);

    // ensureLoaded refait un appel après reset (le no-op `_loaded` est levé).
    await controller.ensureLoaded();
    expect(repo.favCalls, 2);
  });
}
