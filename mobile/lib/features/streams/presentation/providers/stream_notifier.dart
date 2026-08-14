import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

class StreamNotifier extends ChangeNotifier {
  StreamNotifier(this._repository);

  final StreamRepository _repository;

  static const Duration pollInterval = Duration(seconds: 10);
  static const int pageSize = 20;

  List<LiveStream> _streams = const [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isRefreshing = false;
  bool _hasError = false;
  bool _hasMore = false;
  Timer? _timer;

  List<LiveStream> get streams => _streams;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasError => _hasError;
  bool get hasMore => _hasMore;

  bool get isEmpty => !_isLoading && !_hasError && _streams.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    await _refreshLoaded();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => _refreshLoaded();

  Future<void> loadMore() async {
    if (_isLoadingMore || _isRefreshing || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _repository.listLiveStreams(
        limit: pageSize,
        offset: _streams.length,
      );
      _streams = [..._streams, ...page];
      _hasMore = page.length >= pageSize;
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> _refreshLoaded() async {
    if (_isLoadingMore) return;
    _isRefreshing = true;
    final limit = _streams.length < pageSize ? pageSize : _streams.length;
    try {
      final page = await _repository.listLiveStreams(limit: limit, offset: 0);
      _streams = page;
      _hasMore = page.length >= limit;
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    _isRefreshing = false;
    notifyListeners();
  }

  void startPolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => _refreshLoaded());
    // Rafraîchissement immédiat à l'armement : sans lui, revenir sur l'onglet
    // Accueil laisse la liste périmée jusqu'au premier tick, soit jusqu'à
    // `pollInterval`. Sauté quand un chargement est déjà en vol — c'est le cas
    // au démarrage de l'app, où `load()` part juste avant `startPolling()` —
    // pour ne pas doubler la requête initiale.
    if (!_isRefreshing) _refreshLoaded();
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
