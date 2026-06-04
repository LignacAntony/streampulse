import 'package:flutter/foundation.dart';

import '../../../../core/state/async_state.dart';
import '../../domain/repositories/auth_repository.dart';

class ForgotPasswordController extends ChangeNotifier {
  ForgotPasswordController(this._repository);

  final AuthRepository _repository;

  AsyncState<bool> _state = const AsyncState.idle();
  AsyncState<bool> get state => _state;

  Future<void> submit({required String email}) async {
    _state = const AsyncState.loading();
    notifyListeners();
    try {
      await _repository.requestPasswordReset(email: email);
      _state = const AsyncState.data(true);
    } catch (error) {
      _state = AsyncState.error(error);
    }
    notifyListeners();
  }

  void reset() {
    _state = const AsyncState.idle();
    notifyListeners();
  }
}
