import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/app/app.dart';
import 'package:streampulse/app/app_providers.dart';

import 'support/fake_audio_playback_service.dart';

void main() {
  testWidgets('App démarre sans erreur', (WidgetTester tester) async {
    final audioService = FakeAudioPlaybackService();
    addTearDown(audioService.dispose);

    await tester.pumpWidget(
      StreamPulseApp(audioService: audioService, child: const App()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
