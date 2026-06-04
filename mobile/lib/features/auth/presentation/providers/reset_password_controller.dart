import 'package:flutter/foundation.dart';

import '../../domain/repositories/auth_repository.dart';

class ResetPasswordController extends ChangeNotifier {
  ResetPasswordController(this._repository);

  final AuthRepository _repository;

  bool isLoading = false;

  /// Réinitialise le mot de passe via le token. Laisse remonter
  /// l'exception en cas d'échec (gérée par l'écran).
  Future<void> submit({
    required String token,
    required String newPassword,
  }) async {
    isLoading = true;
    notifyListeners();
    try {
      await _repository.resetPassword(token: token, newPassword: newPassword);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
