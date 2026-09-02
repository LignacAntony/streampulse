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
      _hasError = false;
      notifyListeners();
    } catch (_) {
      // Ignoré : la liste précédente reste affichée.
    }
  }

  void startPolling() {
    if (_timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => refreshStreams());
    if (!_isLoading) refreshStreams();
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
