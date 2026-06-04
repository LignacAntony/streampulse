import 'package:flutter/foundation.dart';

import '../../domain/entities/token_pair.dart';
import '../../domain/repositories/auth_repository.dart';

class LoginController extends ChangeNotifier {
  LoginController(this._repository);

  final AuthRepository _repository;

  bool isLoading = false;

  /// Lance la connexion. Renvoie le [TokenPair] en cas de succès,
  /// laisse remonter l'exception en cas d'échec (gérée par l'écran).
  Future<TokenPair> submit({
    required String email,
    required String password,
  }) async {
    isLoading = true;
    notifyListeners();
    try {
      return await _repository.login(email: email, password: password);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
