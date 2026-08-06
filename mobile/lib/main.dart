import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/audio/stream_audio_handler.dart';

// StreamPulseApp pose le MultiProvider racine (injection de dépendances)
// au-dessus de l'arbre de widgets.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Service de lecture partagé, hébergé dans un service de premier plan pour la
  // lecture en arrière-plan / écran verrouillé (STR-109, ADR 030). Créé une
  // seule fois au démarrage et injecté dans l'arbre.
  final audioHandler = await AudioService.init(
    builder: StreamAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'fr.streampulse.streampulse.audio',
      androidNotificationChannelName: 'Lecture StreamPulse',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  runApp(
    StreamPulseApp(
      audioService: audioHandler,
      child: const App(),
    ),
  );
}
