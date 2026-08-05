import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/screens/playlist_detail_screen.dart';

PlaylistTrack _track(String id, String title, int position) => PlaylistTrack(
      id: id,
      title: title,
      artist: 'Neon Lights',
      durationS: 214,
      position: position,
    );

class _FakePlaylistRepository implements PlaylistRepository {
  _FakePlaylistRepository({List<PlaylistTrack>? initial})
      : _tracks = initial ?? [];

  List<PlaylistTrack> _tracks;
  List<Track> library = const [];

  Object? reorderError;
  List<String>? lastOrder;
  int removeCalls = 0;
  String? addedTrackId;

  @override
  Future<List<PlaylistTrack>> tracks(String id) async => _tracks;

  @override
  Future<List<Track>> libraryTracks() async => library;

  @override
  Future<List<PlaylistTrack>> addTrack(
    String playlistId,
    String trackId,
  ) async {
    addedTrackId = trackId;
    _tracks = [..._tracks, _track(trackId, 'Ajoutée', _tracks.length)];
    return _tracks;
  }

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {
    removeCalls++;
    _tracks = _tracks.where((t) => t.id != trackId).toList();
  }

  @override
  Future<List<PlaylistTrack>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  ) async {
    lastOrder = trackIds;
    if (reorderError != null) throw reorderError!;
    _tracks = [
      for (var i = 0; i < trackIds.length; i++)
        _track(
          trackIds[i],
          _tracks.firstWhere((t) => t.id == trackIds[i]).title,
          i,
        ),
    ];
    return _tracks;
  }

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

Widget _harness(PlaylistRepository repository) {
  return ToastificationWrapper(
    child: MaterialApp(
      home: PlaylistDetailScreen(
        playlistId: 'p-1',
        playlistName: 'My Favorites',
        repository: repository,
      ),
    ),
  );
}

/// Saisit la poignée de la 2e ligne et la remonte au-dessus de la 1re.
/// Le déplacement est fait par petits pas : `ReorderableListView` recalcule la
/// cible à chaque frame, un saut unique ne déclenche pas le réordonnancement.
Future<void> _dragSecondRowUp(WidgetTester tester) async {
  final handle = find.byIcon(Icons.drag_handle).last;
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await tester.pump(const Duration(milliseconds: 200));
  for (var i = 0; i < 8; i++) {
    await gesture.moveBy(const Offset(0, -12));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Purge les timers d'auto-fermeture des toasts avant la fin du test.
Future<void> _dismissToasts(WidgetTester tester) async {
  toastification.dismissAll(delayForAnimation: false);
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  group('PlaylistDetailScreen', () {
    testWidgets('affiche les pistes numérotées dans l\'ordre', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('My Favorites'), findsOneWidget);
      expect(find.text('Midnight Drive'), findsOneWidget);
      expect(find.text('Sunrise'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byKey(const Key('playlist_tracks_list')), findsOneWidget);
    });

    testWidgets('playlist vide : message dédié', (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist_tracks_empty')), findsOneWidget);
    });

    testWidgets('le drag-and-drop persiste le nouvel ordre', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      // Saisir la poignée de la 2e ligne et la remonter au-dessus de la 1re.
      await _dragSecondRowUp(tester);

      expect(repo.lastOrder, ['t2', 't1']);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('échec du réordonnancement : toast d\'erreur', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      )..reorderError = const ConflictException('La playlist a changé');
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await _dragSecondRowUp(tester);

      expect(find.text('La playlist a changé'), findsOneWidget);
      await _dismissToasts(tester);
    });

    testWidgets('retirer une piste appelle le repository', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_track_remove_t1')));
      await tester.pumpAndSettle();

      expect(repo.removeCalls, 1);
      expect(find.text('Midnight Drive'), findsNothing);
      await _dismissToasts(tester);
    });

    testWidgets('le sélecteur n\'affiche que les pistes absentes',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0)],
      )..library = const [
          Track(id: 't1', title: 'Midnight Drive', artist: null, durationS: null),
          Track(id: 't2', title: 'Sunrise', artist: null, durationS: null),
        ];
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_add_track_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_picker_item_t2')), findsOneWidget);
      expect(find.byKey(const Key('track_picker_item_t1')), findsNothing);

      await tester.tap(find.byKey(const Key('track_picker_item_t2')));
      await tester.pumpAndSettle();

      expect(repo.addedTrackId, 't2');
      await _dismissToasts(tester);
    });

    testWidgets('bibliothèque vide : le sélecteur le dit', (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_add_track_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('track_picker_empty')), findsOneWidget);
    });
  });
}
