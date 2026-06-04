import 'package:flutter/foundation.dart';

import '../../../../core/state/async_state.dart';
import '../../domain/entities/token_pair.dart';
import '../../domain/repositories/auth_repository.dart';

class LoginController extends ChangeNotifier {
  LoginController(this._repository);

  final AuthRepository _repository;

  AsyncState<TokenPair?> _state = const AsyncState.idle();
  AsyncState<TokenPair?> get state => _state;

  Future<void> submit({
    required String email,
    required String password,
  }) async {
    _state = const AsyncState.loading();
    notifyListeners();
    try {
      final tokens = await _repository.login(email: email, password: password);
      _state = AsyncState.data(tokens);
    } catch (error) {
      _state = AsyncState.error(error);
    }
    notifyListeners();
  }

  /// Réinitialise l'état (équivalent de `ref.invalidate`).
  void reset() {
    _state = const AsyncState.idle();
    notifyListeners();
  }
}
