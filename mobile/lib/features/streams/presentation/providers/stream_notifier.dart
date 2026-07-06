import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

class StreamNotifier extends ChangeNotifier {
  StreamNotifier(this._repository);

  final StreamRepository _repository;

  static const Duration pollInterval = Duration(seconds: 10);

  List<LiveStream> _streams = const [];
  bool _isLoading = false;
  bool _hasError = false;
  Timer? _timer;

  List<LiveStream> get streams => _streams;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;

  bool get isEmpty => !_isLoading && !_hasError && _streams.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    await _fetch();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    try {
      _streams = await _repository.listLiveStreams();
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    notifyListeners();
  }

  void startPolling() {
    _timer ??= Timer.periodic(pollInterval, (_) => _fetch());
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
