import 'package:just_audio/just_audio.dart' show PlayerState;

/// Métadonnées du flux en cours, exposées à l'UI (mini-player, plein écran) et
/// publiées comme `MediaItem` pour la notification / l'écran verrouillé (STR-109).
class NowPlaying {
  const NowPlaying({
    required this.streamId,
    required this.title,
    this.broadcaster,
  });

  final String streamId;
  final String title;
  final String? broadcaster;
}

/// Service de lecture audio **partagé au niveau application** (DIP) : le
/// [AudioPlayerController] en dépend, jamais directement de `just_audio` ni
/// d'`audio_service`. L'implémentation de production ([StreamAudioHandler])
/// enveloppe un lecteur natif hébergé dans un service de premier plan, ce qui
/// permet la lecture en arrière-plan / écran verrouillé et les contrôles
/// système (STR-109). Les tests injectent un fake léger.
abstract class AudioPlaybackService {
  /// État natif du lecteur (mappé en état applicatif par le contrôleur).
  Stream<PlayerState> get playerStateStream;

  /// Erreurs de lecture (perte réseau, flux terminé) — pilotent la reprise
  /// automatique bornée du contrôleur (STR-118).
  Stream<Object> get playbackErrors;

  bool get playing;

  /// Charge le manifeste [url] et publie les métadonnées [now] pour la
  /// notification. Ne démarre pas la lecture (le contrôleur enchaîne).
  Future<void> loadUri(String url, {required NowPlaying now});

  Future<void> play();
  Future<void> pause();

  /// Arrête la lecture et retire la notification (fin de direct / fermeture).
  Future<void> stop();
}
