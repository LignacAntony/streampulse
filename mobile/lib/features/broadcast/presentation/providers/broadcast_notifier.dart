import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/sse_client.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';

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
    this._repository, {
    SseConnector? sse,
    Duration Function(int attempt)? backoff,
  })  : _sse = sse,
        _backoff = backoff ?? _defaultBackoff;

  final BroadcastRepository _repository;

  /// Null en test unitaire pur : le notifier fonctionne alors sans temps réel.
  final SseConnector? _sse;
  final Duration Function(int attempt) _backoff;

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
  Timer? _reconnectTimer;
  String? _sseStreamId;
  int _reconnectAttempt = 0;

  List<BroadcastStream> get streams => _streams;
  bool get loading => _loading;
  bool get creating => _creating;

  /// Identifiant du flux dont un `start`/`stop` est en vol, ou null. Sert à
  /// n'afficher un indicateur que sur la tuile concernée et à empêcher deux
  /// mutations simultanées.
  String? get mutatingId => _mutatingId;
  String? get error => _error;
  bool get isNetworkError => _isNetworkError;

  /// Flux actuellement en direct, ou null. Le backend garantit qu'il y en a au
  /// plus un par diffuseur (migration `000016_streams_one_live`).
  BroadcastStream? get liveStream {
    for (final stream in _streams) {
      if (stream.isLive) return stream;
    }
    return null;
  }

  bool get hasLiveStream => liveStream != null;

  /// (Re)charge les flux du diffuseur.
  /// `reset: true` vide la liste avant le fetch ; `reset: false` la conserve
  /// affichée pendant le rechargement (resynchronisation SSE, pull-to-refresh).
  Future<void> load({bool reset = true}) async {
    final generation = ++_loadGeneration;
    if (reset) _streams = const [];
    _loading = true;
    _clearError();
    notifyListeners();
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
        notifyListeners();
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
    notifyListeners();
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
      notifyListeners();
    }
  }

  /// Démarre le direct. No-op si une autre mutation est déjà en vol.
  ///
  /// L'écran désactive déjà le bouton quand un autre flux est en direct ; le
  /// 409 « you already have a live stream » reste possible sur une course
  /// entre deux appareils et remonte alors à l'appelant.
  Future<void> start(String id) => _mutate(id, _repository.startStream);

  /// Arrête le direct. Un 409 signifie que le flux n'était déjà plus en
  /// direct (arrêt par un administrateur, par exemple) : l'écran le traite en
  /// rechargeant plutôt qu'en affichant un échec sec.
  Future<void> stop(String id) => _mutate(id, _repository.stopStream);

  Future<void> _mutate(
    String id,
    Future<BroadcastStream> Function(String id) action,
  ) async {
    if (_mutatingId != null) return;
    _mutatingId = id;
    notifyListeners();
    try {
      final updated = await action(id);
      _streams = _sorted([
        for (final stream in _streams)
          if (stream.id == updated.id) updated else stream,
      ]);
      _clearError();
    } finally {
      _mutatingId = null;
      notifyListeners();
      _syncSubscription();
    }
  }

  /// Signale que l'écran est visible ou non. Appelé au montage/démontage et
  /// sur changement de cycle de vie de l'application : une connexion SSE ne
  /// doit pas survivre à la mise en arrière-plan.
  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    if (active) {
      _syncSubscription();
    } else {
      _cancelSubscription();
    }
  }

  /// Branche ou débranche le SSE selon l'état courant : une souscription n'a
  /// de sens que sur un flux en direct (l'endpoint répond 409 sinon).
  void _syncSubscription() {
    final live = liveStream;
    if (!_active || _sse == null || live == null) {
      _cancelSubscription();
      return;
    }
    if (_sseStreamId == live.id && _sseSubscription != null) return;
    _cancelSubscription();
    _sseStreamId = live.id;
    _reconnectAttempt = 0;
    _openSubscription();
  }

  void _openSubscription() {
    final id = _sseStreamId;
    final sse = _sse;
    if (id == null || sse == null) return;
    _sseSubscription = sse
        .connect('${ApiConstants.streams}/$id/events')
        .listen(
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

  /// Direct en tête, puis les flux prêts à démarrer, puis les terminés : le
  /// diffuseur a besoin de l'état actionnable en premier.
  List<BroadcastStream> _sorted(List<BroadcastStream> streams) {
    final sorted = [...streams];
    sorted.sort((a, b) => _rank(a).compareTo(_rank(b)));
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

  static Duration _defaultBackoff(int attempt) {
    const maxSeconds = 30;
    // 1, 2, 4, 8, 16 puis palier à 30 s. Le décalage est borné avant le shift
    // pour ne pas déborder sur une coupure très longue.
    final seconds = attempt >= 5 ? maxSeconds : 1 << attempt;
    return Duration(seconds: seconds > maxSeconds ? maxSeconds : seconds);
  }

  @override
  void dispose() {
    _cancelSubscription();
    super.dispose();
  }
}
