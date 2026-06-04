import 'package:flutter/foundation.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

class RegisterController extends ChangeNotifier {
  RegisterController(this._repository);

  final AuthRepository _repository;

  bool isLoading = false;

  /// Crée le compte. Renvoie le [User] créé, laisse remonter l'exception
  /// en cas d'échec (gérée par l'écran).
  Future<User> submit({
    required String email,
    required String username,
    required String password,
  }) async {
    isLoading = true;
    notifyListeners();
    try {
      return await _repository.register(
        email: email,
        username: username,
        password: password,
      );
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
