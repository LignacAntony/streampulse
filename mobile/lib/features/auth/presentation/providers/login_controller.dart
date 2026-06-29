import 'package:flutter/foundation.dart';

import '../../domain/entities/token_pair.dart';
import '../../domain/repositories/auth_repository.dart';

/// Pilote l'écran de connexion : déclenche l'appel au dépôt et expose
/// l'état de chargement à l'UI.
class LoginController extends ChangeNotifier {
  /// Crée le contrôleur avec le dépôt d'authentification injecté.
  LoginController(this._repository);

  final AuthRepository _repository;

  bool _isLoading = false;

  /// Vrai tant qu'une requête de connexion est en cours.
  bool get isLoading => _isLoading;

  /// Lance la connexion. Renvoie le [TokenPair] en cas de succès,
  /// laisse remonter l'exception en cas d'échec (gérée par l'écran).
  Future<TokenPair> submit({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    notifyListeners();
    try {
      return await _repository.login(email: email, password: password);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
