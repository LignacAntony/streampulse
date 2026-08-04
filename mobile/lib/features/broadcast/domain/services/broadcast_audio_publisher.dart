/// Etat du chemin audio local, distinct du statut métier du flux côté API.
enum BroadcastAudioState { idle, connecting, live, reconnecting }

/// Capture le microphone et pousse l'audio vers l'URL d'ingest d'un direct.
///
/// Le découpage [prepare]/[start] est volontaire : le contrôleur peut demander
/// la permission et vérifier l'encodeur *avant* de passer le flux à `live`,
/// tout en n'ouvrant l'ingest qu'après la réponse de l'API.
abstract interface class BroadcastAudioPublisher {
  BroadcastAudioState get state;
  Stream<BroadcastAudioState> get states;

  /// Demande l'accès au micro et vérifie la disponibilité de l'AAC/ADTS.
  Future<void> prepare();

  /// Démarre la capture et rend la main lorsque le premier push est lancé.
  /// Les coupures ultérieures sont reprises en interne avec backoff.
  Future<void> start(Uri sourceUrl);

  /// Interrompt le push et libère le microphone.
  Future<void> stop();

  Future<void> dispose();
}

class MicrophonePermissionException implements Exception {
  const MicrophonePermissionException();
}

class AudioEncoderUnsupportedException implements Exception {
  const AudioEncoderUnsupportedException();
}

/// Repli des plateformes où un corps HTTP streamé n'est pas disponible.
/// L'échec survient pendant [prepare], donc avant le passage serveur à `live`.
class UnsupportedBroadcastAudioPublisher implements BroadcastAudioPublisher {
  const UnsupportedBroadcastAudioPublisher();

  @override
  BroadcastAudioState get state => BroadcastAudioState.idle;

  @override
  Stream<BroadcastAudioState> get states => const Stream.empty();

  @override
  Future<void> prepare() async {
    throw const AudioEncoderUnsupportedException();
  }

  @override
  Future<void> start(Uri sourceUrl) async {
    throw const AudioEncoderUnsupportedException();
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
