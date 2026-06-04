import 'package:flutter/foundation.dart';

import '../../domain/repositories/auth_repository.dart';

class ForgotPasswordController extends ChangeNotifier {
  ForgotPasswordController(this._repository);

  final AuthRepository _repository;

  bool isLoading = false;

  /// Demande l'envoi du lien de réinitialisation. Laisse remonter
  /// l'exception en cas d'échec (gérée par l'écran).
  Future<void> submit({required String email}) async {
    isLoading = true;
    notifyListeners();
    try {
      await _repository.requestPasswordReset(email: email);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
