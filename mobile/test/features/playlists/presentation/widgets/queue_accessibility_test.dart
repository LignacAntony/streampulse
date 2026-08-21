import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:provider/provider.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/playlists/presentation/providers/playlist_queue_controller.dart';
import 'package:streampulse/features/playlists/presentation/widgets/queue_mini_player.dart';

import '../../../../support/accessibility.dart';
import '../../../../support/fake_queue_playback_service.dart';

/// Les contrôles du lecteur sont la surface la plus utilisée de l'application,
/// et la plus dépendante d'icônes sans texte : c'est là qu'un défaut
/// d'accessibilité coûte le plus (STR-246).
void main() {
  testWidgets(
    'le bandeau de file d\'attente est utilisable au lecteur d\'écran',
    (tester) async {
      final handle = tester.ensureSemantics();
      final service = FakeQueuePlaybackService();
      final controller = PlaylistQueueController(
        service: service,
        token: ({bool forceRefresh = false}) async => 'jwt',
      );
      addTearDown(controller.dispose);
      addTearDown(service.dispose);

      await controller.play(
        tracks: [
          const Track(
            id: 't1',
            title: 'Midnight Drive',
            artist: 'Neon Lights',
            durationS: 214,
          ),
          const Track(
            id: 't2',
            title: 'Sunrise',
            artist: 'Neon Lights',
            durationS: 198,
          ),
        ],
        sourceName: 'My Favorites',
        playlistId: 'p-1',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<PlaylistQueueController>.value(
          value: controller,
          child: const MaterialApp(home: Scaffold(body: QueueMiniPlayer())),
        ),
      );
      service.emitState(PlayerState(true, ProcessingState.ready));
      await tester.pump();

      await expectMeetsAccessibilityGuidelines(tester);
      // Plus strict que la garde de Flutter : un tooltip seul laisserait ces
      // boutons anonymes pour VoiceOver.
      expectNoTooltipOnlyTapTargets(tester);

      // Les libellés disent l'ACTION, pas l'icône ni l'état.
      expect(find.bySemanticsLabel('Piste précédente'), findsOneWidget);
      expect(find.bySemanticsLabel('Piste suivante'), findsOneWidget);
      expect(find.bySemanticsLabel('Arrêter la lecture'), findsOneWidget);
      expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);

      handle.dispose();
    },
  );

  testWidgets('le bouton de lecture annonce l\'action, pas l\'état courant', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final service = FakeQueuePlaybackService();
    final controller = PlaylistQueueController(
      service: service,
      token: ({bool forceRefresh = false}) async => 'jwt',
    );
    addTearDown(controller.dispose);
    addTearDown(service.dispose);

    await controller.play(
      tracks: [
        const Track(
          id: 't1',
          title: 'Midnight Drive',
          artist: null,
          durationS: null,
        ),
      ],
      sourceName: 'My Favorites',
      playlistId: 'p-1',
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<PlaylistQueueController>.value(
        value: controller,
        child: const MaterialApp(home: Scaffold(body: QueueMiniPlayer())),
      ),
    );

    service.emitState(PlayerState(false, ProcessingState.ready));
    await tester.pump();
    // À l'arrêt, l'appui LANCE la lecture : annoncer « Pause » ici — ce que
    // faisait le tooltip d'origine — dit exactement l'inverse de ce qui va
    // se produire.
    expect(find.bySemanticsLabel('Lire'), findsOneWidget);

    service.emitState(PlayerState(true, ProcessingState.ready));
    await tester.pump();
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);

    handle.dispose();
  });
}
