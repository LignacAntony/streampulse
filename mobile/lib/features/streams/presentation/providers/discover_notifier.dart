import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../tracks/domain/entities/public_track.dart';
import '../../../tracks/domain/repositories/track_repository.dart';
import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

class DiscoverNotifier extends ChangeNotifier {
  DiscoverNotifier(this._repository, this._trackRepository);

  final StreamRepository _repository;
  final TrackRepository _trackRepository;

  static const int pageSize = 50;

  static const Duration pollInterval = Duration(seconds: 15);

  List<LiveStream> _streams = const [];
  List<PublicTrack> _publicTracks = const [];
  bool _isLoading = false;
  bool _hasError = false;
  Timer? _timer;

  /// Horodatage du dernier fetch **réussi** des flux. Sert à ne pas refaire un
  /// fetch immédiat au démarrage du polling si `load()` vient de peupler la
  /// liste (sinon deux appels réseau quasi simultanés à chaque arrivée).
  DateTime? _lastStreamsAt;

  List<LiveStream> get streams => _streams;
  List<PublicTrack> get publicTracks => _publicTracks;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get isEmpty =>
      !_isLoading && !_hasError && _streams.isEmpty && _publicTracks.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();

    var streamsFailed = false;
    var tracksFailed = false;
    try {
      _streams = await _repository.listLiveStreams(limit: pageSize);
      _lastStreamsAt = DateTime.now();
    } catch (_) {
      streamsFailed = true;
    }

    try {
      _publicTracks = await _trackRepository.listPublicTracks(limit: pageSize);
    } catch (_) {
      tracksFailed = true;
      _publicTracks = const [];
    }

    _hasError = streamsFailed && tracksFailed;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refreshStreams() async {
    try {
      _streams = await _repository.listLiveStreams(limit: pageSize);
      _lastStreamsAt = DateTime.now();
      _hasError = false;
      notifyListeners();
    } catch (_) {
      // Ignoré : la liste précédente reste affichée.
    }
  }

  void startPolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => refreshStreams());
    // Refresh immédiat seulement si les flux n'ont pas été fetchés récemment :
    // à l'entrée sur l'écran, `load()` vient de peupler la liste, un second
    // appel serait redondant. Au retour après une longue absence, la liste est
    // périmée → on rafraîchit sans attendre le prochain tick.
    if (!_isLoading && _streamsAreStale()) refreshStreams();
  }

  bool _streamsAreStale() {
    final last = _lastStreamsAt;
    return last == null || DateTime.now().difference(last) >= pollInterval;
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
