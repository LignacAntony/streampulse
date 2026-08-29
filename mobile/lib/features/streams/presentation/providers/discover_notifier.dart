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

  List<LiveStream> _streams = const [];
  List<PublicTrack> _publicTracks = const [];
  bool _isLoading = false;
  bool _hasError = false;

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
    try {
      final results = await Future.wait([
        _repository.listLiveStreams(limit: pageSize),
        _trackRepository.listPublicTracks(limit: pageSize),
      ]);
      _streams = results[0] as List<LiveStream>;
      _publicTracks = results[1] as List<PublicTrack>;
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    _isLoading = false;
    notifyListeners();
  }
}
