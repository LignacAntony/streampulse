import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/sse_client.dart';
import '../../../../core/utils/retry_backoff.dart';
import '../../domain/entities/broadcast_stats.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';
import '../../domain/services/broadcast_audio_publisher.dart';
import '../controllers/broadcast_session_controller.dart';

/// Pilote `DashboardScreen` : flux du diffuseur connecté, création, démarrage
/// et arrêt du direct (US-06-01, ADR 024).
///
/// Fraîcheur du statut : le dashboard ne poll pas. Tant qu'un flux est en
/// direct, une souscription SSE (`/api/streams/{id}/events`) signale son arrêt,
/// y compris lorsqu'il vient d'un administrateur (US-08-02) ou du nettoyage
/// des flux orphelins côté backend. Le flux SSE n'émettant que `ended` et ne
/// rejouant pas les évènements manqués, chaque **reconnexion** est suivie d'un
/// `refresh()` de resynchronisation — c'est ce qui rattrape un arrêt survenu
/// pendant une coupure réseau.
///
/// Comme `AdminStreamsProvider`, `load()` est réentrant et protégé par un
/// jeton de génération : sur deux chargements concurrents (double
/// pull-to-refresh), seul le plus récent écrit l'état. Les mutations
/// (`create`/`start`/`stop`) ne capturent PAS leurs erreurs : elles sont
/// relayées à l'écran, qui a un point d'appel unique où afficher un toast.
class BroadcastNotifier extends ChangeNotifier {
  BroadcastNotifier(
    BroadcastRepository repository, {
    SseConnector? sse,
    Duration Function(int attempt)? backoff,
    Duration pollInterval = const Duration(seconds: 15),
    Duration statsInterval = const Duration(seconds: 5),
    BroadcastAudioPublisher? audioPublisher,
  })  : _repository = repository,
        _sse = sse,
        _backoff = backoff ?? cappedExponentialBackoff,
        _pollInterval = pollInterval,
        _statsInterval = statsInterval,
        _sessionController = BroadcastSessionController(
          repository,
          audioPublisher,
        ) {
    _audioSubscription = _sessionController.audioStates.listen(
      (_) => _safeNotify(),
    );
    // Le contrôleur a déjà terminé le direct côté serveur : il reste à
    // réaligner la liste, dont la tuile est encore affichée « en direct ».
    // Une panne du micro va souvent de pair avec une panne réseau — on
    // privilégie donc l'état rendu par l'arrêt, et on ne recharge que s'il
    // manque.
    _audioFailureSubscription = _sessionController.audioFailures.listen((
      failure,
    ) {
      // Prise de relais par une autre source : le direct n'a pas bougé côté
      // serveur, seul notre micro s'est retiré. Recharger ne corrigerait rien
      // et ferait clignoter la liste (revue PR #382).
      if (failure.reason == BroadcastAudioEndReason.supersededByOtherSource) {
        _safeNotify();
        return;
      }
      final ended = failure.serverState;
      if (ended == null) {
        unawaited(refresh());
        return;
      }
      _replace(ended);
      _safeNotify();
      _syncSubscription();
    });
  }

  final BroadcastRepository _repository;

  /// Null quand la plateforme ne sait pas maintenir un flux HTTP ouvert — c'est
  /// le cas de Flutter web, dont l'adaptateur Dio ne supporte pas
  /// `ResponseType.stream`. Le notifier bascule alors sur un rafraîchissement
  /// périodique (cf. [_startPolling]) plutôt que d'échouer en boucle.
  final SseConnector? _sse;
  final Duration Function(int attempt) _backoff;
  final Duration _pollInterval;

  /// Cadence des statistiques d'audience. 5 s : c'est la fréquence de mise à
  /// jour demandée par l'AC de l'US-06-02.
  final Duration _statsInterval;
  final BroadcastSessionController _sessionController;

  List<BroadcastStream> _streams = const [];
  bool _loading = false;
  bool _creating = false;
  String? _mutatingId;
  String? _error;
  bool _isNetworkError = false;

  /// Cf. `AdminStreamsProvider._loadGeneration` : incrémenté par `load()`
  /// uniquement, il permet de jeter une réponse (succès OU échec) devenue
  /// obsolète sans laisser le spinner figé.
  int _loadGeneration = 0;

  /// Faux quand l'écran n'est plus visible (onglet quitté, application en
  /// arrière-plan) : coupe la souscription SSE plutôt que de maintenir une
  /// connexion HTTP ouverte pour rien.
  bool _active = false;

  StreamSubscription<SseEvent>? _sseSubscription;
  StreamSubscription<BroadcastAudioState>? _audioSubscription;
  StreamSubscription<BroadcastAudioFailure>? _audioFailureSubscription;
  Timer? _reconnectTimer;
  Timer? _pollTimer;
  Timer? _statsTimer;
  BroadcastStats? _stats;
  String? _statsStreamId;
  String? _sseStreamId;
  int _reconnectAttempt = 0;

  /// Vrai après [dispose]. Une requête encore en vol au moment où l'écran est
  /// détruit (déconnexion pendant un `start`, par exemple) finirait sinon par
  /// notifier un notifier disposé — assertion en debug, silencieux en release.
  bool _disposed = false;

  List<BroadcastStream> get streams => _streams;
  bool get loading => _loading;
  bool get creating => _creating;

  /// Identifiant du flux dont un `start`/`stop`/`delete` est en vol, ou null.
  /// Sert à n'afficher un indicateur que sur la tuile concernée et à empêcher
  /// deux mutations simultanées.
  String? get mutatingId => _mutatingId;

  /// Vrai dès qu'une mutation quelconque est en vol. L'écran s'en sert pour
  /// neutraliser les actions des AUTRES tuiles : tant que `start(A)` n'a pas
  /// répondu, A est encore `idle` localement, donc rien n'empêcherait sinon de
  /// lancer `start(B)` — qui serait rejeté silencieusement.
  bool get isMutating => _mutatingId != null;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  /// Etat du micro de cet appareil. Un flux peut être `live` sans être capturé
  /// localement s'il a été démarré depuis un autre téléphone ou un encodeur.
  BroadcastAudioState get audioState => _sessionController.audioState;

  /// Faux sur une plateforme incapable de capturer et pousser l'audio (web) :
  /// l'écran désactive alors le démarrage plutôt que de laisser l'utilisateur
  /// découvrir l'indisponibilité après un tap.
  bool get audioSupported => _sessionController.audioSupported;

  /// Direct terminé parce que la capture locale a renoncé à se reconnecter.
  /// L'écran s'y abonne pour le signaler ; la liste, elle, est réalignée ici
  /// même.
  Stream<BroadcastAudioFailure> get audioFailures =>
      _sessionController.audioFailures;

  bool isPublishingAudio(String streamId) =>
      _sessionController.isPublishing(streamId);

  /// Flux actuellement en direct, ou null. Le backend garantit qu'il y en a au
  /// plus un par diffuseur (migration `000016_streams_one_live`).
  BroadcastStream? get liveStream {
    for (final stream in _streams) {
      if (stream.isLive) return stream;
    }
    return null;
  }

  bool get hasLiveStream => liveStream != null;

  /// Audience du direct en cours, ou null tant qu'aucune mesure n'est arrivée
  /// (ou si aucun flux n'est en direct). Rafraîchie toutes les [_statsInterval].
  BroadcastStats? get stats => _stats;

  /// (Re)charge les flux du diffuseur.
  /// `reset: true` vide la liste avant le fetch ; `reset: false` la conserve
  /// affichée pendant le rechargement (resynchronisation SSE, pull-to-refresh).
  Future<void> load({bool reset = true}) async {
    final generation = ++_loadGeneration;
    if (reset) _streams = const [];
    _loading = true;
    _clearError();
    _safeNotify();
    try {
      final result = await _repository.listMyStreams();
      if (generation != _loadGeneration) return; // résultat obsolète
      _streams = _sorted(result);
    } catch (e) {
      if (generation != _loadGeneration) return; // échec obsolète
      _setError(e);
    } finally {
      // Seul le chargement le plus récent possède `_loading` : un chargement
      // obsolète qui l'éteindrait figerait l'état du plus récent.
      if (generation == _loadGeneration) {
        _loading = false;
        _safeNotify();
        _syncSubscription();
      }
    }
  }

  /// Pull-to-refresh : recharge sans vider la liste affichée, pour éviter un
  /// clignotement de l'écran à chaque resynchronisation.
  Future<void> refresh() => load(reset: false);

  /// Crée un flux `idle` et l'ajoute en tête de liste. Les erreurs de
  /// validation (400) et réseau sont relayées à l'appelant.
  Future<BroadcastStream> create({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async {
    _creating = true;
    _safeNotify();
    try {
      final created = await _repository.createStream(
        title: title,
        isPublic: isPublic,
        description: description,
        category: category,
      );
      _streams = _sorted([created, ..._streams]);
      _clearError();
      return created;
    } finally {
      _creating = false;
      _safeNotify();
    }
  }

  /// Démarre le direct. Retourne `false` sans rien faire si une autre mutation
  /// est déjà en vol — l'appelant DOIT tester ce retour avant d'annoncer un
  /// succès, sinon un second tap concurrent afficherait « Vous êtes en direct »
  /// alors que rien n'a démarré.
  ///
  /// Le 409 « you already have a live stream » reste possible sur une course
  /// entre deux appareils et remonte alors à l'appelant.
  Future<bool> start(String id) async {
    if (_mutatingId != null) return false;
    _mutatingId = id;
    _safeNotify();
    try {
      final updated = await _sessionController.start(id);
      _replace(updated);
      _clearError();
      return true;
    } on BroadcastSessionStartException catch (error) {
      _replace(error.serverState);
      if (error.refreshRequired) unawaited(refresh());
      Error.throwWithStackTrace(error.cause, error.stackTrace);
    } finally {
      _mutatingId = null;
      _safeNotify();
      _syncSubscription();
    }
  }

  /// Arrête le direct. Même contrat de retour que [start]. Un 409 signifie que
  /// le flux n'était déjà plus en direct (arrêt par un administrateur, par
  /// exemple) : l'écran le traite en rechargeant plutôt qu'en affichant un
  /// échec sec.
  Future<bool> stop(String id) async {
    if (_mutatingId != null) return false;
    _mutatingId = id;
    _safeNotify();
    try {
      final updated = await _sessionController.stop(id);
      _replace(updated);
      _clearError();
      return true;
    } finally {
      _mutatingId = null;
      _safeNotify();
      _syncSubscription();
    }
  }

  /// Fermeture de l'application (balayage depuis les récents) : le direct est
  /// terminé côté serveur et le micro relâché (ADR 049).
  ///
  /// C'est le pendant de « quitter l'application ne coupe rien » : personne ne
  /// veut diffuser depuis une application qu'il vient de fermer, et un service
  /// de premier plan survivrait à la fermeture si on ne faisait rien.
  ///
  /// Best-effort par nature : le processus est en train de mourir, l'appel peut
  /// ne jamais partir. Le bail d'ingest du serveur reste le filet.
  Future<void> stopForAppClosed() async {
    try {
      await _sessionController.stopForAppClosed();
    } catch (_) {
      // L'OS coupe souvent le réseau avant la fin de la requête. Le micro est
      // relâché par le contrôleur, et le bail terminera le direct.
    } finally {
      _safeNotify();
    }
  }

  /// Remet une clé d'ingest neuve et invalide l'ancienne (US-06-04). Même
  /// contrat de retour que [start].
  ///
  /// Pas de `_syncSubscription()` ici, contrairement aux autres mutations : la
  /// rotation ne change pas le statut du flux, donc ni le direct suivi en SSE
  /// ni la remontée d'audience ne bougent. Seule la tuile est réécrite.
  Future<bool> rotateKey(String id) async {
    if (_mutatingId != null) return false;
    _mutatingId = id;
    _safeNotify();
    try {
      final updated = await _repository.rotateStreamKey(id);
      _replace(updated);
      _clearError();
      return true;
    } finally {
      _mutatingId = null;
      _safeNotify();
    }
  }

  /// Archive le flux et le retire de la liste. Même contrat de retour que
  /// [start]. Sur un flux en direct, le backend termine la diffusion au
  /// passage — l'écran doit l'avoir annoncé avant d'appeler ceci.
  Future<bool> delete(String id) async {
    if (_mutatingId != null) return false;
    _mutatingId = id;
    _safeNotify();
    try {
      await _sessionController.delete(id);
      _streams = List.unmodifiable(
        _streams.where((stream) => stream.id != id).toList(),
      );
      _clearError();
      return true;
    } finally {
      _mutatingId = null;
      _safeNotify();
      // Le flux supprimé était peut-être le direct suivi en SSE : resynchroniser
      // la souscription évite de rester branché sur un flux qui n'existe plus.
      _syncSubscription();
    }
  }

  void _replace(BroadcastStream updated) {
    _streams = _sorted([
      for (final stream in _streams)
        if (stream.id == updated.id) updated else stream,
    ]);
  }

  /// Signale que l'écran est visible ou non. Appelé au montage/démontage et
  /// sur changement de cycle de vie de l'application : une connexion SSE ne
  /// doit pas survivre à la mise en arrière-plan.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    _sessionController.setActive(active);
    // `_syncSubscription` traite les deux sens : à faux, il coupe la
    // souscription SSE **et** le polling. Les séparer avait laissé le timer de
    // polling tourner en arrière-plan.
    _syncSubscription();
  }

  /// Branche ou débranche le suivi temps réel selon l'état courant : il n'a de
  /// sens que sur un flux en direct (l'endpoint SSE répond 409 sinon).
  void _syncSubscription() {
    final live = liveStream;
    unawaited(_sessionController.reconcile(live));
    _syncStats(live);
    if (!_active || live == null) {
      _cancelSubscription();
      _cancelPolling();
      return;
    }
    if (_sse == null) {
      _startPolling();
      return;
    }
    if (_sseStreamId == live.id && _sseSubscription != null) return;
    _cancelSubscription();
    _sseStreamId = live.id;
    _reconnectAttempt = 0;
    _openSubscription();
  }

  /// Repli des plateformes sans streaming HTTP : on interroge périodiquement
  /// l'API tant qu'un flux est en direct. Moins réactif qu'un `ended` SSE, mais
  /// l'écran finit toujours par converger — et surtout, on n'enchaîne pas des
  /// connexions vouées à échouer.
  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => unawaited(refresh()));
  }

  void _cancelPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Arme, réarme ou coupe la remontée d'audience selon le direct en cours.
  /// Distincte du repli SSE : elle tourne sur toutes les plateformes, et à une
  /// cadence propre (5 s) imposée par l'AC.
  void _syncStats(BroadcastStream? live) {
    if (!_active || live == null) {
      _cancelStats();
      return;
    }
    if (_statsStreamId == live.id && _statsTimer != null) return;
    _cancelStats();
    _statsStreamId = live.id;
    // Première mesure tout de suite : attendre 5 s laisserait la carte sans
    // chiffre juste après le démarrage, au moment où on la regarde le plus.
    unawaited(_fetchStats());
    _statsTimer = Timer.periodic(
      _statsInterval,
      (_) => unawaited(_fetchStats()),
    );
  }

  /// Récupère l'audience. Un échec est ignoré volontairement : l'audience est
  /// une information d'appoint, une coupure réseau ne doit pas faire clignoter
  /// une erreur sur un tableau de bord par ailleurs fonctionnel. La dernière
  /// valeur connue reste affichée.
  Future<void> _fetchStats() async {
    final id = _statsStreamId;
    if (id == null) return;
    try {
      final stats = await _repository.streamStats(id);
      if (_disposed || _statsStreamId != id) return; // flux changé entre-temps
      // Ne notifier que sur changement réel : l'audience bouge rarement entre
      // deux mesures, inutile de reconstruire l'écran toutes les 5 s pour
      // réafficher les mêmes chiffres.
      if (_stats == stats) return;
      _stats = stats;
      _safeNotify();
    } catch (_) {
      // Silencieux : cf. doc ci-dessus.
    }
  }

  void _cancelStats() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _statsStreamId = null;
    if (_stats != null) {
      _stats = null;
      _safeNotify();
    }
  }

  void _openSubscription() {
    final id = _sseStreamId;
    final sse = _sse;
    if (id == null || sse == null) return;
    _sseSubscription = sse.connect('${ApiConstants.streams}/$id/events').listen(
          _onSseEvent,
          onError: (Object _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _onSseEvent(SseEvent event) {
    // Recevoir quoi que ce soit prouve que la connexion est saine : le backoff
    // repart de zéro pour la prochaine coupure.
    _reconnectAttempt = 0;
    if (event.name != 'ended') return;
    _cancelSubscription();
    unawaited(refresh());
  }

  /// Reprogramme une connexion après une coupure, avec un délai croissant
  /// plafonné. La resynchronisation qui suit la reconnexion est ce qui
  /// rattrape un `ended` émis pendant la coupure.
  void _scheduleReconnect() {
    _sseSubscription = null;
    if (!_active || _sseStreamId == null) return;
    final delay = _backoff(_reconnectAttempt);
    _reconnectAttempt++;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_active || _sseStreamId == null) return;
      _openSubscription();
      unawaited(refresh());
    });
  }

  void _cancelSubscription() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sseSubscription?.cancel();
    _sseSubscription = null;
    _sseStreamId = null;
  }

  /// Notifie seulement si le notifier est encore vivant. Une requête en vol au
  /// moment où l'écran est détruit finirait sinon dans `notifyListeners()`
  /// après `dispose()`.
  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Direct en tête, puis les flux prêts à démarrer, puis les terminés : le
  /// diffuseur a besoin de l'état actionnable en premier.
  ///
  /// `List.sort` de Dart n'étant pas stable, l'ordre relatif de deux flux de
  /// même rang varierait d'un rafraîchissement à l'autre — d'où le départage
  /// explicite par date de création décroissante, qui reproduit l'ordre du
  /// backend et rend la liste visuellement stable.
  List<BroadcastStream> _sorted(List<BroadcastStream> streams) {
    final sorted = [...streams];
    sorted.sort((a, b) {
      final byRank = _rank(a).compareTo(_rank(b));
      if (byRank != 0) return byRank;
      return b.createdAt.compareTo(a.createdAt);
    });
    return List.unmodifiable(sorted);
  }

  int _rank(BroadcastStream stream) {
    if (stream.isLive) return 0;
    if (stream.isIdle) return 1;
    return 2;
  }

  void _setError(Object error) {
    _error = error is NetworkException
        ? 'Pas de connexion réseau'
        : 'Impossible de charger vos flux';
    _isNetworkError = error is NetworkException;
  }

  void _clearError() {
    _error = null;
    _isNetworkError = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSubscription();
    _cancelPolling();
    _statsTimer?.cancel();
    _audioSubscription?.cancel();
    _audioFailureSubscription?.cancel();
    unawaited(_sessionController.dispose());
    super.dispose();
  }
}
