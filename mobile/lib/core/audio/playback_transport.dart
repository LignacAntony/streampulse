import 'package:just_audio/just_audio.dart' show PlayerState;

/// État applicatif du lecteur, mappé depuis just_audio et exposé à l'UI.
/// `reconnecting` = une erreur transitoire est en cours de reprise automatique
/// (STR-118) ; `error` = échec définitif (après épuisement des tentatives).
///
/// Partagé par les deux usages du lecteur — le direct HLS (STR-108) et la file
/// d'attente d'une playlist (US-05-04) — pour que le mini-player n'ait qu'un
/// seul vocabulaire d'état à comprendre.
enum PlaybackStatus {
  idle,
  loading,
  buffering,
  playing,
  paused,
  reconnecting,
  ended,
  error,
}

/// Commandes et signaux communs à toute lecture, quelle qu'en soit la source.
///
/// L'application n'héberge **qu'un seul** lecteur natif (cf. ADR 031) : direct
/// et file d'attente s'excluent donc mutuellement, et partagent ce transport.
/// Ce qui les distingue — charger un manifeste live d'un côté, une file de
/// pistes de l'autre — vit dans les interfaces dérivées ([AudioPlaybackService],
/// [QueuePlaybackService]), pour qu'aucun appelant ne dépende de méthodes qui ne
/// le concernent pas (principe I).
abstract class PlaybackTransport {
  /// État natif du lecteur (mappé en état applicatif par les contrôleurs).
  Stream<PlayerState> get playerStateStream;

  /// Erreurs de lecture (perte réseau, flux terminé, source injoignable) —
  /// l'arbitrage de la reprise appartient au contrôleur, pas au transport.
  Stream<Object> get playbackErrors;

  bool get playing;

  Future<void> play();
  Future<void> pause();

  /// Arrête la lecture et retire la notification.
  Future<void> stop();
}
