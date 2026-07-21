import 'package:flutter/foundation.dart';

import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';

/// Pilote la page « Découvrir » : liste de tous les flux publics en direct.
class DiscoverNotifier extends ChangeNotifier {
  DiscoverNotifier(this._repository);

  final StreamRepository _repository;

  static const int pageSize = 50;

  List<LiveStream> _streams = const [];
  bool _isLoading = false;
  bool _hasError = false;

  List<LiveStream> get streams => _streams;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  bool get isEmpty => !_isLoading && !_hasError && _streams.isEmpty;

  Future<void> load() async {
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    try {
      _streams = await _repository.listLiveStreams(limit: pageSize);
      _hasError = false;
    } catch (_) {
      _hasError = true;
    }
    _isLoading = false;
    notifyListeners();
  }
}
