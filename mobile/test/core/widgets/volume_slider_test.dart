import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:streampulse/core/audio/playback_transport.dart';
import 'package:streampulse/core/audio/volume_store.dart';
import 'package:streampulse/core/widgets/volume_slider.dart';

import '../../support/fake_audio_playback_service.dart';

const _sliderKey = Key('volume_slider');
const _muteKey = Key('volume_mute_toggle');

Future<({FakeAudioPlaybackService transport, InMemoryVolumeStore store})> _pump(
  WidgetTester tester, {
  double initial = 1,
}) async {
  final transport = FakeAudioPlaybackService();
  await transport.setVolume(initial);
  final store = InMemoryVolumeStore();
  addTearDown(transport.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<PlaybackTransport>.value(value: transport),
        Provider<VolumeStore>.value(value: store),
      ],
      child: const MaterialApp(home: Scaffold(body: VolumeSlider())),
    ),
  );
  return (transport: transport, store: store);
}

/// Glisse la poignée jusqu'à l'extrémité gauche du curseur (volume nul).
Future<void> _dragToStart(WidgetTester tester) async {
  final box = tester.getRect(find.byKey(_sliderKey));
  await tester.dragFrom(box.center, Offset(-box.width, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'le curseur part du niveau courant du transport, pas d\'un défaut',
    (tester) async {
      // Le flux n'émet qu'aux changements : s'y fier seul laisserait le curseur à
      // 1 alors que la session précédente avait été restaurée à 0,3.
      await _pump(tester, initial: 0.3);

      final slider = tester.widget<Slider>(find.byKey(_sliderKey));
      expect(slider.value, closeTo(0.3, 1e-9));
      expect(find.text('30 %'), findsOneWidget);
    },
  );

  testWidgets('glisser applique le volume immédiatement', (tester) async {
    final ctx = await _pump(tester);

    await _dragToStart(tester);

    expect(ctx.transport.volume, 0);
  });

  // Un glissement émet des dizaines de valeurs : écrire à chaque tick userait
  // le magasin pour un résultat identique. Seule la valeur relâchée compte.
  testWidgets('le magasin n\'est écrit qu\'au relâchement', (tester) async {
    final ctx = await _pump(tester);

    // onChanged sans onChangeEnd : le transport bouge, le magasin non.
    final slider = tester.widget<Slider>(find.byKey(_sliderKey));
    slider.onChanged!(0.5);
    await tester.pump();
    expect(ctx.transport.volume, 0.5);
    expect(await ctx.store.read(), isNull);

    slider.onChangeEnd!(0.5);
    await tester.pump();
    expect(await ctx.store.read(), 0.5);
  });

  testWidgets('le transport pilote le curseur, pas l\'inverse', (tester) async {
    final ctx = await _pump(tester);

    // Un réglage venu d'ailleurs (restauration au démarrage) doit se voir.
    await ctx.transport.setVolume(0.25);
    await tester.pump();

    expect(
      tester.widget<Slider>(find.byKey(_sliderKey)).value,
      closeTo(0.25, 1e-9),
    );
  });

  testWidgets('l\'icône suit le niveau', (tester) async {
    final ctx = await _pump(tester, initial: 1);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await ctx.transport.setVolume(0.2);
    await tester.pump();
    expect(find.byIcon(Icons.volume_down), findsOneWidget);

    await ctx.transport.setVolume(0);
    await tester.pump();
    expect(find.byIcon(Icons.volume_off), findsOneWidget);
  });

  testWidgets('couper puis rétablir revient au niveau d\'avant', (
    tester,
  ) async {
    final ctx = await _pump(tester, initial: 0.7);

    await tester.tap(find.byKey(_muteKey));
    await tester.pumpAndSettle();
    expect(ctx.transport.volume, 0);

    await tester.tap(find.byKey(_muteKey));
    await tester.pumpAndSettle();
    expect(ctx.transport.volume, closeTo(0.7, 1e-9));
    expect(await ctx.store.read(), closeTo(0.7, 1e-9));
  });

  // L'auditeur a fermé l'application en sourdine : l'appui doit lui rendre du
  // son, pas ne rien faire.
  testWidgets('rétablir sans niveau mémorisé remonte à 100 %', (tester) async {
    final ctx = await _pump(tester, initial: 0);

    await tester.tap(find.byKey(_muteKey));
    await tester.pumpAndSettle();

    expect(ctx.transport.volume, 1);
  });

  testWidgets('le curseur est annoncé en pourcentage au lecteur d\'écran', (
    tester,
  ) async {
    await _pump(tester, initial: 0.42);

    final slider = tester.widget<Slider>(find.byKey(_sliderKey));
    expect(slider.semanticFormatterCallback!(0.42), 'Volume 42 %');
  });
}
