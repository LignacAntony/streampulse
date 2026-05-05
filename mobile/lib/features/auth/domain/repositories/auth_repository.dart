import '../entities/user.dart';

// Interface abstraite — Principe D (les couches supérieures dépendent de cette
// abstraction, pas des implémentations concrètes dans data/repositories/).
// Principe I : interface minimale, sera enrichie au fil des US.
abstract class AuthRepository {
  /// Crée un compte utilisateur via l'API et retourne l'entité [User] créée.
  ///
  /// Lève :
  ///   - `ValidationException` si l'API rejette les champs (400)
  ///   - `DuplicateAccountException` si email ou pseudo déjà utilisé (409)
  ///   - `NetworkException` si pas de connexion / timeout
  ///   - `ServerException` pour toute autre erreur
  Future<User> register({
    required String email,
    required String username,
    required String password,
  });
}
