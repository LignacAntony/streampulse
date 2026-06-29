import 'package:flutter/foundation.dart';

import '../../domain/repositories/auth_repository.dart';

/// Pilote l'écran de nouveau mot de passe : déclenche la réinitialisation
/// et expose l'état de chargement à l'UI.
class ResetPasswordController extends ChangeNotifier {
  /// Crée le contrôleur avec le dépôt d'authentification injecté.
  ResetPasswordController(this._repository);

  final AuthRepository _repository;

  bool _isLoading = false;

  /// Vrai tant que la réinitialisation est en cours.
  bool get isLoading => _isLoading;

  /// Réinitialise le mot de passe via le token. Laisse remonter
  /// l'exception en cas d'échec (gérée par l'écran).
  Future<void> submit({
    required String token,
    required String newPassword,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.resetPassword(token: token, newPassword: newPassword);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
