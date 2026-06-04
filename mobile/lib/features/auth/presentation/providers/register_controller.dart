import 'package:flutter/foundation.dart';

import '../../../../core/state/async_state.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class RegisterController extends ChangeNotifier {
  RegisterController(this._repository);

  final AuthRepository _repository;

  AsyncState<User?> _state = const AsyncState.idle();
  AsyncState<User?> get state => _state;

  Future<void> submit({
    required String email,
    required String username,
    required String password,
  }) async {
    _state = const AsyncState.loading();
    notifyListeners();
    try {
      final user = await _repository.register(
        email: email,
        username: username,
        password: password,
      );
      _state = AsyncState.data(user);
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
