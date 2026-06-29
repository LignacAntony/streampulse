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

  /// Supprime définitivement le compte (RGPD art. 17).
  /// Lève [AuthException] si le mot de passe est incorrect.
  Future<void> deleteAccount({required String password});

  /// Déclenche l'envoi de l'email de réinitialisation.
  /// Ne lève jamais sur email inconnu (anti-énumération côté serveur).
  Future<void> requestPasswordReset({required String email});

  /// Valide le token et met à jour le mot de passe.
  /// Lève [ValidationException] si le token est invalide ou expiré.
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  });
}
