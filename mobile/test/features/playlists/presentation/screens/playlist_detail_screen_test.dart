import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/offline/entities/cached_track_status.dart';
import 'package:streampulse/core/offline/entities/offline_playlist_summary.dart';
import 'package:streampulse/core/offline/offline_cache_repository.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist.dart';
import 'package:streampulse/features/playlists/domain/entities/playlist_track.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/domain/repositories/playlist_repository.dart';
import 'package:streampulse/features/playlists/presentation/providers/offline_playlist_controller.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/screens/playlist_detail_screen.dart';

import '../../../../support/fake_offline_playlist_controller.dart';
import '../../../../support/fake_queue_playback_service.dart';
import 'package:streampulse/core/widgets/accessible_icon_button.dart';
import '../../../../support/accessibility.dart';

class _FakeCacheRepository implements OfflineCacheRepository {
  @override
  Future<Set<String>> offlinePlaylistIds() async => {};
  @override
  Future<List<OfflinePlaylistSummary>> offlinePlaylists() async => [];
  @override
  Future<bool> isOffline(String playlistId) async => false;
  @override
  Future<void> enableOffline(String id, String name, List<PlaylistTrack> t) async {}
  @override
  Future<void> disableOffline(String id) async {}
  @override
  Future<List<PlaylistTrack>> cachedTracks(String id) async => [];
  @override
  Future<List<CachedTrackStatus>> downloadStatuses(String id) async => [];
  @override
  Future<void> updateTrackStatus(String t, String p, {required TrackCacheStatus status, String? filePath, int? fileSize}) async {}
  @override
  Future<String?> cachedFilePath(String t) async => null;
  @override
  Future<int> totalCacheSize() async => 0;
  @override
  Future<void> clearAll() async {}
}

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

  Object? tracksError;
  Object? reorderError;
  List<String>? lastOrder;
  int removeCalls = 0;
  String? addedTrackId;

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

  @override
  Future<void> favorite(String id) => throw UnimplementedError();

  @override
  Future<void> unfavorite(String id) => throw UnimplementedError();
}

/// Contrôleur de file d'attente pour les tests d'écran : le service est un fake,
/// le token une constante (l'écran ne fait que déclencher la lecture).
PlaylistQueueController _queueController(FakeQueuePlaybackService service) {
  return PlaylistQueueController(
    service: service,
    token: ({bool forceRefresh = false}) async => 'jwt',
  );
}

Widget _harness(
  PlaylistRepository repository, {
  TargetPlatform? platform,
  PlaylistQueueController? queue,
}) {
  // L'écran lit la file d'attente app-level (US-05-04) pour lancer la lecture et
  // souligner la piste en cours : elle doit exister au-dessus de lui.
  return MultiProvider(
    providers: [
      Provider<OfflineCacheRepository>.value(value: _FakeCacheRepository()),
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: queue ?? _queueController(FakeQueuePlaybackService()),
      ),
      ChangeNotifierProvider<OfflinePlaylistController>.value(
        value: FakeOfflinePlaylistController(),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        // `ReorderableListView` choisit ses poignées par défaut d'après
        // `Theme.of(context).platform` : le forcer permet de tester le rendu
        // desktop.
        theme: platform == null ? null : ThemeData(platform: platform),
        home: PlaylistDetailScreen(
          playlistId: 'p-1',
          playlistName: 'My Favorites',
          repository: repository,
        ),
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

    testWidgets(
        'un retrait depuis la file d\'attente resynchronise le détail (STR-250)',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [
          _track('t1', 'Midnight Drive', 0),
          _track('t2', 'Sunrise', 1),
          _track('t3', 'Afterglow', 2),
        ],
      );
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      // La file joue CETTE playlist (même id que le détail affiché).
      await queue.play(
        tracks: const [
          Track(id: 't1', title: 'Midnight Drive', artist: 'A', durationS: 214),
          Track(id: 't2', title: 'Sunrise', artist: 'A', durationS: 214),
          Track(id: 't3', title: 'Afterglow', artist: 'A', durationS: 214),
        ],
        sourceName: 'My Favorites',
        playlistId: 'p-1',
      );

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      expect(find.text('Afterglow'), findsOneWidget);

      // Retrait « depuis la file » : d'abord en base (ce que fait la feuille),
      // puis de la file en cours.
      await repo.removeTrack('p-1', 't3');
      await queue.removeFromQueue(2);
      await tester.pumpAndSettle();

      // Le détail s'est rechargé seul, sans pull-to-refresh manuel.
      expect(find.text('Afterglow'), findsNothing);
      expect(find.text('Midnight Drive'), findsOneWidget);
      expect(find.text('Sunrise'), findsOneWidget);
    });

    testWidgets('le bouton Lire lance la playlist depuis le début (US-05-04)',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_play_button')));
      await tester.pumpAndSettle();

      expect(service.lastItems.map((i) => i.id).toList(), ['t1', 't2']);
      expect(service.lastInitialIndex, 0);
      expect(queue.sourceName, 'My Favorites');
      // La ligne en cours est repérable : son numéro cède la place à l'icône.
      expect(find.byIcon(Icons.graphic_eq), findsOneWidget);
    });

    testWidgets('un appui sur une piste démarre la file à cette piste',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sunrise'));
      await tester.pumpAndSettle();

      // Toute la playlist est chargée — on démarre juste plus loin dedans.
      expect(service.lastItems.map((i) => i.id).toList(), ['t1', 't2']);
      expect(service.lastInitialIndex, 1);
      expect(queue.currentIndex, 1);
    });

    testWidgets('playlist vide : ni bouton Lire, ni file lancée',
        (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist_play_button')), findsNothing);
    });

    testWidgets('« Lire en aléatoire » lance la file mélangée (US-05-05)',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      final service = FakeQueuePlaybackService();
      final queue = _queueController(service);
      addTearDown(queue.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_harness(repo, queue: queue));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('playlist_shuffle_play_button')));
      await tester.pumpAndSettle();

      expect(queue.shuffleEnabled, isTrue);
      expect(service.shuffleEnabled, isTrue);
      // Toute la playlist est chargée ; seul l'ordre de lecture change.
      expect(service.lastItems.map((i) => i.id).toList(), ['t1', 't2']);
    });

    testWidgets('playlist vide : « Lire en aléatoire » est neutralisé',
        (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      final button = tester.widget<AccessibleIconButton>(
        find.byKey(const Key('playlist_shuffle_play_button')),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('playlist vide : message dédié + appel à l\'action',
        (tester) async {
      await tester.pumpWidget(_harness(_FakePlaylistRepository()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('playlist_tracks_empty')), findsOneWidget);

      // Le CTA ouvre le même sélecteur que le « + » de l'AppBar.
      await tester.tap(find.widgetWithText(FilledButton, 'Ajouter une piste'));
      await tester.pumpAndSettle();
      expect(find.text('Ajouter une piste'), findsWidgets);
      expect(find.byKey(const Key('track_picker_empty')), findsOneWidget);
    });

    testWidgets('une seule poignée de drag par ligne, y compris sur desktop',
        (tester) async {
      // Plateforme desktop forcée : c'est là que ReorderableListView ajoute sa
      // propre poignée. Sans `buildDefaultDragHandles: false`, elle s'empile sur
      // celle de la ligne et le test voit deux icônes.
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0)],
      );
      await tester.pumpWidget(
        _harness(repo, platform: TargetPlatform.macOS),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.drag_handle), findsOneWidget);
    });

    testWidgets('échec d\'un pull-to-refresh sur liste non vide : toast',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      repo.tracksError = const NetworkException();
      await tester.fling(
        find.byKey(const Key('playlist_tracks_list')),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      // La liste reste affichée (la vue d'erreur ne remplace pas une liste
      // non vide) : sans toast, l'échec passerait inaperçu.
      expect(find.text('Midnight Drive'), findsOneWidget);
      expect(find.text('Pas de connexion réseau'), findsOneWidget);
      await _dismissToasts(tester);
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

    testWidgets('retirer une piste demande confirmation puis retire',
        (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_track_remove_t1')));
      await tester.pumpAndSettle();

      // Rien n'est retiré tant que la confirmation n'est pas donnée.
      expect(find.text('Retirer « Midnight Drive » de la playlist ?'),
          findsOneWidget);
      expect(repo.removeCalls, 0);

      await tester.tap(find.byKey(const Key('playlist_track_confirm_remove')));
      await tester.pumpAndSettle();

      expect(repo.removeCalls, 1);
      expect(find.text('Midnight Drive'), findsNothing);
      await _dismissToasts(tester);
    });

    testWidgets('annuler la confirmation ne retire rien', (tester) async {
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0), _track('t2', 'Sunrise', 1)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('playlist_track_remove_t1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.removeCalls, 0);
      expect(find.text('Midnight Drive'), findsOneWidget);
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
  group('PlaylistDetailScreen — accessibilité (STR-244)', () {
    testWidgets('une ligne de piste est annoncée UNE fois, en une phrase',
        (tester) async {
      final handle = tester.ensureSemantics();
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      // La phrase composée est bien posée…
      expect(
        find.bySemanticsLabel(RegExp(r'Piste 1, .*')),
        findsOneWidget,
      );

      // …et le titre n'apparaît pas EN PLUS dans un nœud séparé.
      //
      // C'est le défaut relevé en revue (#332) : le `Semantics` conteneur ne
      // masquait pas ses enfants, et la ListTile étant tapable, ses title et
      // subtitle formaient leur propre nœud. Un lecteur d'écran annonçait la
      // phrase entière PUIS « Midnight Drive, … » — la lecture fragmentée que
      // le changement prétendait supprimer, plus un doublon.
      const titre = 'Midnight Drive';
      // …et le titre ne forme pas un nœud à lui seul.
      //
      // Défaut relevé en revue (#332) : le `Semantics` conteneur ne masquait pas
      // ses enfants, et la ListTile étant tapable, ses title/subtitle formaient
      // leur propre nœud. Un lecteur d'écran annonçait la phrase composée PUIS
      // « Midnight Drive, Neon Lights 3:34 » — la lecture fragmentée que le
      // changement prétendait supprimer, plus un doublon.
      //
      // On vise le titre SEUL : « Retirer Midnight Drive de la playlist » est le
      // bouton d'action, il a son propre libellé et doit rester distinct.
      final labels = semanticLabelsMentioning(tester, titre);
      expect(
        labels.where((l) => l == titre || l.startsWith('\$titre,')),
        isEmpty,
        reason: 'le titre ne doit pas former de nœud séparé, il appartient à '
            'la phrase composée. Nœuds trouvés : \$labels',
      );
      expect(labels.any((l) => l.startsWith('Piste 1, ')), isTrue);

      handle.dispose();
    });

    testWidgets('la ligne expose une action tap, pas seulement un rôle',
        (tester) async {
      final handle = tester.ensureSemantics();
      final repo = _FakePlaylistRepository(
        initial: [_track('t1', 'Midnight Drive', 0)],
      );
      await tester.pumpWidget(_harness(repo));
      await tester.pumpAndSettle();

      expect(buttonsWithoutTapAction(tester), isEmpty);
      handle.dispose();
    });
  });

}
