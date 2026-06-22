import 'package:flutter/foundation.dart';

import '../../domain/entities/broadcaster_request.dart';
import '../../domain/repositories/broadcaster_repository.dart';

/// Pilote l'écran « Devenir diffuseur » : charge la demande existante et en
/// soumet une nouvelle. Partagé via `ChangeNotifierProvider` (niveau 3).
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

  /// Vrai s'il existe une demande en attente : on masque alors le formulaire.
  bool get hasPendingRequest => _request?.isPending ?? false;

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

  /// Soumet une demande. Relaie l'exception (ex. `ConflictException`) pour que
  /// l'écran affiche un toast ; le `finally` réinitialise toujours l'état.
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
