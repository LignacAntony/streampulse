import 'package:flutter/foundation.dart';

import '../../domain/repositories/auth_repository.dart';

/// Pilote l'écran « mot de passe oublié » : déclenche l'envoi du lien
/// et expose l'état de chargement à l'UI.
class ForgotPasswordController extends ChangeNotifier {
  /// Crée le contrôleur avec le dépôt d'authentification injecté.
  ForgotPasswordController(this._repository);

  final AuthRepository _repository;

  bool _isLoading = false;

  /// Vrai tant que la demande d'envoi du lien est en cours.
  bool get isLoading => _isLoading;

  /// Demande l'envoi du lien de réinitialisation. Laisse remonter
  /// l'exception en cas d'échec (gérée par l'écran).
  Future<void> submit({required String email}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.requestPasswordReset(email: email);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
