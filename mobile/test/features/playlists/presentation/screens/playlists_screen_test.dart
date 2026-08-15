import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';

import '../../../../support/fake_offline_playlist_controller.dart';
import '../../../../support/fake_queue_playback_service.dart';
import 'package:streampulse/features/playlists/presentation/providers/offline_playlist_controller.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/screens/playlists_screen.dart';

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
  _FakePlaylistRepository({List<Playlist>? initial}) : playlists = initial ?? [];

  List<Playlist> playlists;
  List<Track> libraryTracksList = const [];
  Object? createError;
  Object? deleteError;
  Object? renameError;

  int createCalls = 0;
  int renameCalls = 0;
  int deleteCalls = 0;

  @override
  Future<List<Playlist>> list() async => playlists;

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

  @override
  Future<List<Track>> libraryTracks() async => libraryTracksList;

  @override
  Future<List<PlaylistTrack>> addTrack(String playlistId, String trackId) async =>
      const [];

  @override
  Future<void> removeTrack(String playlistId, String trackId) async {}

  @override
  Future<List<PlaylistTrack>> reorderTracks(
    String playlistId,
    List<String> trackIds,
  ) async =>
      const [];
}

Widget _harness(
  PlaylistRepository repository, {
  bool isAuthenticated = true,
  PlaylistQueueController? queue,
}) {
  // L'écran lit la file d'attente app-level (STR-231) : lancer une piste de la
  // bibliothèque et souligner celle en cours passent par elle.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: queue ?? _queueController(FakeQueuePlaybackService()),
      ),
      ChangeNotifierProvider<OfflinePlaylistController>.value(
        value: FakeOfflinePlaylistController(),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        home: PlaylistsScreen(
          repository: repository,
          isAuthenticated: isAuthenticated,
        ),
      ),
    ),
  );
}

PlaylistQueueController _queueController(FakeQueuePlaybackService service) {
  return PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async => 'jwt',
  );
}

void main() {
  group('PlaylistsScreen', () {
    testWidgets('affiche les cartes avec le nombre de titres', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_playlist('p-1', 'My Favorites', trackCount: 3)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('My Favorites'), findsOneWidget);
      expect(find.text('3 titres'), findsOneWidget);
      expect(find.byKey(const Key('playlist_card_p-1')), findsOneWidget);
    });

    testWidgets('état vide quand ni playlist ni piste', (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      expect(
        find.text('Rien dans ta bibliothèque\nCrée une playlist ou uploade une piste'),
        findsOneWidget,
      );
    });

    testWidgets('affiche la bibliothèque de pistes sous les playlists',
        (tester) async {
      final repo = _FakePlaylistRepository()
        ..libraryTracksList = const [
          Track(id: 't-1', title: 'Midnight Drive', artist: 'Neon', durationS: 214),
        ];
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(find.text('Mes pistes'), findsOneWidget);
      expect(find.byKey(const Key('track_tile_t-1')), findsOneWidget);
      expect(find.text('Midnight Drive'), findsOneWidget);
    });

    testWidgets('un appui sur une piste lance toute la bibliothèque (STR-231)',
        (tester) async {
      final repo = _FakePlaylistRepository()
        ..libraryTracksList = const [
          Track(id: 't-1', title: 'Midnight Drive', artist: 'Neon', durationS: 214),
          Track(id: 't-2', title: 'Sunrise', artist: 'Neon', durationS: 187),
          Track(id: 't-3', title: 'Afterglow', artist: 'Neon', durationS: 201),
        ];
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('track_tile_t-2')));
      await tester.pumpAndSettle();

      // Toute la bibliothèque part en file : une file d'un élément rendrait
      // précédent/suivant et les modes de lecture sans objet.
      expect(service.lastItems.map((i) => i.id).toList(), ['t-1', 't-2', 't-3']);
      expect(service.lastInitialIndex, 1);
      expect(queue.sourceName, 'Ma bibliothèque');
      expect(queue.playlistId, isNull,
          reason: 'la bibliothèque n\'est pas une playlist');
    });

    testWidgets('la piste en cours est repérable dans la bibliothèque',
        (tester) async {
      final repo = _FakePlaylistRepository()
        ..libraryTracksList = const [
          Track(id: 't-1', title: 'Midnight Drive', artist: 'Neon', durationS: 214),
          Track(id: 't-2', title: 'Sunrise', artist: 'Neon', durationS: 187),
        ];
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('track_tile_t-2')));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    });

    testWidgets('invité : pas de bouton +, invitation à se connecter',
        (tester) async {
      await tester.pumpWidget(
        _harness(_FakePlaylistRepository(), isAuthenticated: false),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist_create_button')), findsNothing);
      expect(find.byKey(const Key('playlists_guest_view')), findsOneWidget);
      expect(
        find.text('Connecte-toi pour créer et gérer tes playlists'),
        findsOneWidget,
      );
    });

    testWidgets('connecté : le bouton + est présent', (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist_create_button')), findsOneWidget);
    });

    testWidgets('création via le bouton +', (tester) async {
      final repo = _FakePlaylistRepository();
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_create_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('playlist_name_field')),
        'Road Trip',
      );
      // La sheet est plus haute que la fenêtre de test : faire défiler le
      // bouton dans la vue avant de le taper.
      await tester.ensureVisible(find.byKey(const Key('playlist_form_submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_form_submit')));
      await tester.pumpAndSettle();

      expect(repo.createCalls, 1);
      expect(find.text('Road Trip'), findsOneWidget);

      // Purge le timer d'auto-fermeture du toast succès avant la fin du test.
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('renommage : sheet pré-remplie puis mise à jour',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_playlist('p-1', 'Rock')],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_menu_p-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_action_rename')));
      await tester.pumpAndSettle();

      // Le nom courant est pré-rempli dans la sheet.
      expect(find.widgetWithText(TextFormField, 'Rock'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('playlist_name_field')),
        'Metal',
      );
      await tester.ensureVisible(find.byKey(const Key('playlist_form_submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_form_submit')));
      await tester.pumpAndSettle();

      expect(repo.renameCalls, 1);
      expect(find.text('Metal'), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('suppression demande confirmation puis supprime',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_playlist('p-1', 'Rock')],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_menu_p-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_action_delete')));
      await tester.pumpAndSettle();

      // Le dialog de confirmation est affiché ; on confirme.
      expect(find.byKey(const Key('playlist_confirm_delete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('playlist_confirm_delete')));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      expect(find.byKey(const Key('playlist_card_p-1')), findsNothing);

      // Purge le timer d'auto-fermeture du toast succès avant la fin du test.
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('annuler la confirmation ne supprime pas', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_playlist('p-1', 'Rock')],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_menu_p-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_action_delete')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 0);
      expect(find.byKey(const Key('playlist_card_p-1')), findsOneWidget);
    });
  });
}
