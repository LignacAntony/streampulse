import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_providers.dart';
import 'core/audio/stream_audio_handler.dart';

// StreamPulseApp pose le MultiProvider racine (injection de dépendances)
// au-dessus de l'arbre de widgets.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Service de lecture partagé, hébergé dans un service de premier plan pour la
  // lecture en arrière-plan / écran verrouillé (STR-109, ADR 031). Créé une
  // seule fois au démarrage et injecté dans l'arbre.
  final audioHandler = await AudioService.init(
    builder: StreamAudioHandler.new,
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'fr.streampulse.streampulse.audio',
      androidNotificationChannelName: 'Lecture StreamPulse',
      // `ongoing` impose `stopForegroundOnPause` (assert d'audio_service). On
      // reste sur le défaut recommandé : à la pause, le service repasse en
      // arrière-plan (démotable). Sur un live, une reprise rejoint de toute
      // façon le bord du direct — pas de « position » à perdre.
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );

  // Configuration de la session + gestion des interruptions (STR-110, ADR 033) :
  // ordonnée explicitement après l'init, et l'échec (ex. plateforme sans plugin)
  // ne doit pas empêcher l'app de démarrer.
  try {
    await audioHandler.configureSession();
  } catch (e) {
    if (kDebugMode) {
      debugPrint('main: configuration de la session audio échouée: $e');
    }
  }

  runApp(
    StreamPulseApp(
      // Le même handler sous ses deux rôles : direct (STR-109) et file d'attente
      // (US-05-04) partagent un unique lecteur natif, donc un unique service.
      audioService: audioHandler,
      queueService: audioHandler,
      child: const App(),
    ),
  );
}
