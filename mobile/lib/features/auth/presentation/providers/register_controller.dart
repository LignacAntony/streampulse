import 'package:flutter/foundation.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';

/// Pilote l'écran d'inscription : déclenche l'appel au dépôt et expose
/// l'état de chargement à l'UI.
class RegisterController extends ChangeNotifier {
  /// Crée le contrôleur avec le dépôt d'authentification injecté.
  RegisterController(this._repository);

  final AuthRepository _repository;

  bool _isLoading = false;

  /// Vrai tant qu'une requête d'inscription est en cours.
  bool get isLoading => _isLoading;

  /// Crée le compte. Renvoie le [User] créé, laisse remonter l'exception
  /// en cas d'échec (gérée par l'écran).
  Future<User> submit({
    required String email,
    required String username,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _repository.register(
        email: email,
        username: username,
        password: password,
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
