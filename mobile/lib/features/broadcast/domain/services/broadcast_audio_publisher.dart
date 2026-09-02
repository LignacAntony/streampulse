/// Etat du chemin audio local, distinct du statut métier du flux côté API.
///
/// [failed] est terminal et n'est émis *que* de la propre initiative du
/// diffuseur audio, lorsqu'il renonce à se reconnecter. Un arrêt demandé passe
/// toujours par [idle] : le contrôleur peut donc distinguer une panne d'un
/// arrêt volontaire sans drapeau supplémentaire.
/// États de la capture micro. `failed` et `superseded` sont tous deux
/// terminaux, mais appellent des conduites opposées côté serveur :
///
///   - `failed` : la capture a renoncé après avoir épuisé ses reconnexions. Le
///     direct n'a plus de source, il faut le terminer (invariant « jamais de
///     live silencieux », ADR 027).
///   - `superseded` : une **autre source** alimente désormais ce direct — un
///     encodeur externe a pris la clé pendant une coupure réseau. Le direct est
///     bien vivant, simplement ce n'est plus nous. Le terminer couperait la
///     diffusion de quelqu'un d'autre.
///
/// Les confondre est exactement le défaut que ce type sépare.
enum BroadcastAudioState { idle, connecting, live, reconnecting, failed, superseded }

/// Capture le microphone et pousse l'audio vers l'URL d'ingest d'un direct.
///
/// Le découpage [prepare]/[start] est volontaire : le contrôleur peut demander
/// la permission et vérifier l'encodeur *avant* de passer le flux à `live`,
/// tout en n'ouvrant l'ingest qu'après la réponse de l'API.
abstract interface class BroadcastAudioPublisher {
  /// Faux quand la plateforme ne sait pas capturer et pousser l'audio. L'écran
  /// s'en sert pour neutraliser le démarrage en amont, plutôt que de laisser
  /// l'utilisateur découvrir l'indisponibilité après un tap.
  bool get isSupported;

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
  bool get isSupported => false;

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
