import 'dart:async';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';
import '../../domain/services/broadcast_audio_publisher.dart';

/// Orchestre une session de diffusion locale : transition serveur, capture
/// microphone, rollback et politique premier plan (ADR 027).
///
/// Le dashboard conserve ainsi la présentation de la liste/SSE/statistiques,
/// tandis que les invariants « jamais live sans tentative audio » restent ici.
class BroadcastSessionController {
  BroadcastSessionController(this._repository, this._audioPublisher) {
    _audioSubscription = _audioPublisher?.states.listen(_onAudioState);
  }

  final BroadcastRepository _repository;
  final BroadcastAudioPublisher? _audioPublisher;

  String? _publishingStreamId;

  bool _backgroundStopRequested = false;
  StreamSubscription<BroadcastAudioState>? _audioSubscription;
  final StreamController<BroadcastAudioFailure> _audioFailures =
      StreamController<BroadcastAudioFailure>.broadcast();

  BroadcastAudioState get audioState =>
      _audioPublisher?.state ?? BroadcastAudioState.idle;
  Stream<BroadcastAudioState> get audioStates =>
      _audioPublisher?.states ?? const Stream.empty();
  String? get publishingStreamId => _publishingStreamId;

  /// Faux quand la plateforme ne sait pas diffuser : sans publisher injecté
  /// (tests de présentation), rien ne l'interdit.
  bool get audioSupported => _audioPublisher?.isSupported ?? true;

  /// Emet la fin d'un direct que la capture locale a fait échouer. La
  /// présentation s'en sert pour réaligner la liste et prévenir l'utilisateur ;
  /// l'arrêt serveur, lui, est déjà tenté ici.
  Stream<BroadcastAudioFailure> get audioFailures => _audioFailures.stream;

  bool isPublishing(String streamId) => _publishingStreamId == streamId;

  Future<BroadcastStream> start(String id) async {
    final publisher = _audioPublisher;
    if (publisher != null) await publisher.prepare();
    _throwIfBackgrounded();

    final live = await _repository.startStream(id);
    if (publisher == null) return live;

    try {
      _throwIfBackgrounded();
      final rawUrl = live.streamSourceUrl;
      if (rawUrl == null) {
        throw const ServerException('URL d\'ingest absente');
      }
      _publishingStreamId = id;
      await publisher.start(Uri.parse(rawUrl));
      _throwIfBackgrounded();
      return live;
    } catch (error, stackTrace) {
      await _stopAudio(expectedId: id, ignoreErrors: true);
      try {
        final rolledBack = await _repository.stopStream(id);
        throw BroadcastSessionStartException(
          cause: error,
          stackTrace: stackTrace,
          serverState: rolledBack,
        );
      } catch (rollbackError) {
        if (rollbackError is BroadcastSessionStartException) rethrow;
        throw BroadcastSessionStartException(
          cause: error,
          stackTrace: stackTrace,
          serverState: live,
          refreshRequired: true,
        );
      }
    }
  }

  Future<BroadcastStream> stop(String id) async {
    final ended = await _repository.stopStream(id);
    if (_publishingStreamId == id) await _stopAudio(expectedId: id);
    return ended;
  }

  Future<void> delete(String id) async {
    await _repository.deleteStream(id);
    if (_publishingStreamId == id) await _stopAudio(expectedId: id);
  }


  /// Termine le direct parce que l'application est **fermée** (ADR 049).
  ///
  /// Volontairement différent d'un passage en arrière-plan, qui ne coupe plus
  /// rien : le service de premier plan Android maintient la capture pendant que
  /// le diffuseur fait autre chose sur son téléphone. Ce service survivrait
  /// aussi au balayage depuis les récents — d'où l'arrêt explicite ici, doublé
  /// de `android:stopWithTask="true"` sur sa déclaration dans le manifeste.
  ///
  /// L'arrêt serveur est tenté d'abord, le micro relâché quoi qu'il arrive.
  Future<void> stopForAppClosed() async {
    _backgroundStopRequested = true;
    final id = _publishingStreamId;
    if (id == null) return;
    try {
      await _repository.stopStream(id);
    } finally {
      await _stopAudio(expectedId: id, ignoreErrors: true);
    }
  }

  void setActive(bool active) {
    if (active) _backgroundStopRequested = false;
  }

  /// Coupe une capture locale devenue orpheline après resynchronisation API.
  Future<void> reconcile(BroadcastStream? live) async {
    if (_publishingStreamId != null && live?.id != _publishingStreamId) {
      await _stopAudio(ignoreErrors: true);
    }
  }

  /// Le diffuseur audio ne passe à `failed` que de sa propre initiative, après
  /// avoir épuisé ses tentatives de reconnexion. Laisser le flux `live` sans
  /// audio violerait l'invariant « jamais de live silencieux » (ADR 027) : on
  /// termine donc le direct côté serveur, sans attendre l'expiration du bail.
  void _onAudioState(BroadcastAudioState state) {
    final id = _publishingStreamId;
    if (id == null) return;
    switch (state) {
      case BroadcastAudioState.failed:
        unawaited(_endAfterAudioFailure(id));
      case BroadcastAudioState.superseded:
        unawaited(_releaseToOtherSource(id));
      case BroadcastAudioState.idle:
      case BroadcastAudioState.connecting:
      case BroadcastAudioState.live:
      case BroadcastAudioState.reconnecting:
        break;
    }
  }

  /// Une autre source alimente désormais ce direct : on relâche l'état local
  /// **sans rien terminer côté serveur** — le direct est vivant, ce n'est
  /// simplement plus nous qui le portons.
  ///
  /// Sans ce chemin, la capture s'arrêtait en silence : la tuile continuait
  /// d'afficher « en direct » et `isPublishing` restait vrai, avec un micro
  /// mort et aucun message (revue PR #382).
  Future<void> _releaseToOtherSource(String id) async {
    await _stopAudio(expectedId: id, ignoreErrors: true);
    if (!_audioFailures.isClosed) {
      _audioFailures.add(
        BroadcastAudioFailure(
          streamId: id,
          reason: BroadcastAudioEndReason.supersededByOtherSource,
        ),
      );
    }
  }

  Future<void> _endAfterAudioFailure(String id) async {
    BroadcastStream? ended;
    try {
      ended = await _repository.stopStream(id);
    } catch (_) {
      // Réseau toujours coupé — le cas le plus probable quand le micro
      // renonce — ou direct déjà terminé par un administrateur : le bail
      // d'ingest du serveur s'en chargera. La panne est signalée sans état
      // serveur, à charge pour la présentation de resynchroniser.
    } finally {
      await _stopAudio(expectedId: id, ignoreErrors: true);
      if (!_audioFailures.isClosed) {
        _audioFailures.add(
          BroadcastAudioFailure(streamId: id, serverState: ended),
        );
      }
    }
  }

  Future<void> _stopAudio({
    String? expectedId,
    bool ignoreErrors = false,
  }) async {
    if (expectedId != null && _publishingStreamId != expectedId) return;
    if (_publishingStreamId == null) return;
    _publishingStreamId = null;
    try {
      await _audioPublisher?.stop();
    } catch (_) {
      if (!ignoreErrors) rethrow;
    }
  }

  void _throwIfBackgrounded() {
    if (_backgroundStopRequested) {
      throw StateError('Démarrage interrompu par la mise en arrière-plan');
    }
  }

  Future<void> dispose() async {
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _audioFailures.close();
    await _audioPublisher?.dispose();
  }
}

/// Pourquoi la capture locale s'est arrêtée sans que l'utilisateur le demande.
enum BroadcastAudioEndReason {
  /// La capture a renoncé après avoir épuisé ses reconnexions. Le direct a été
  /// terminé côté serveur dans la foulée.
  microphoneLost,

  /// Une autre source (encodeur externe) a pris l'ingest. Le direct **continue**
  /// sans nous ; rien n'a été terminé côté serveur.
  supersededByOtherSource,
}

/// Fin de la capture locale subie, avec sa raison. Les deux cas se ressemblent
/// vus de l'écran — le micro s'arrête — mais l'un laisse un direct mort et
/// l'autre un direct bien vivant : le message à afficher n'est pas le même.
class BroadcastAudioFailure {
  const BroadcastAudioFailure({
    required this.streamId,
    this.serverState,
    this.reason = BroadcastAudioEndReason.microphoneLost,
  });

  final String streamId;
  final BroadcastAudioEndReason reason;

  /// Flux tel que renvoyé par l'arrêt, ou null si cet arrêt a lui aussi échoué
  /// — la liste affichée est alors périmée et doit être rechargée.
  final BroadcastStream? serverState;
}

/// Transporte vers la présentation l'état serveur obtenu pendant le rollback,
/// sans lui faire réimplémenter l'orchestration de la session audio.
class BroadcastSessionStartException implements Exception {
  const BroadcastSessionStartException({
    required this.cause,
    required this.stackTrace,
    required this.serverState,
    this.refreshRequired = false,
  });

  final Object cause;
  final StackTrace stackTrace;
  final BroadcastStream serverState;
  final bool refreshRequired;
}

