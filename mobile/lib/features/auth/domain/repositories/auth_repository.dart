import '../entities/token_pair.dart';
import '../entities/user.dart';

abstract class AuthRepository {
  Future<User> register({
    required String email,
    required String username,
    required String password,
  });

  Future<TokenPair> login({
    required String email,
    required String password,
  });

  /// Révoque le refresh token côté serveur (best-effort) et purge le stockage local.
  /// Ne lève jamais : un échec réseau ne doit pas bloquer la déconnexion locale.
  Future<void> logout();
}
