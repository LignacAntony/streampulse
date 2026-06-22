import 'package:flutter/foundation.dart';

import '../../domain/entities/broadcaster_request.dart';
import '../../domain/repositories/broadcaster_repository.dart';

class BroadcasterController extends ChangeNotifier {
  BroadcasterController(this._repository);

  final BroadcasterRepository _repository;

  BroadcasterRequest? _request;
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _loadFailed = false;

  BroadcasterRequest? get request => _request;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get loadFailed => _loadFailed;

  bool get hasPendingRequest => _request?.isPending ?? false;

  void reset() {
    _request = null;
    _isLoading = false;
    _isSubmitting = false;
    _loadFailed = false;
    notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _loadFailed = false;
    notifyListeners();
    try {
      _request = await _repository.getMyRequest();
    } catch (_) {
      _loadFailed = true;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> submit(String message) async {
    _isSubmitting = true;
    notifyListeners();
    try {
      _request = await _repository.requestBroadcaster(message: message);
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
