import '../entities/admin_user.dart';

abstract class AdminRepository {
  /// Liste paginée des utilisateurs, avec recherche et filtres optionnels
  /// (admin uniquement). `total` est le nombre total de résultats filtrés,
  /// pour la pagination côté UI.
  Future<({List<AdminUser> users, int total})> listUsers({
    String? search,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  });

  /// Active ou désactive un compte utilisateur (admin uniquement).
  /// Rejette (409) une action sur son propre compte ou sur le dernier admin
  /// actif restant.
  Future<AdminUser> setUserActive(String id, bool active);

  /// Supprime définitivement un compte utilisateur (admin uniquement).
  /// Mêmes garde-fous 409 que [setUserActive].
  Future<void> deleteUser(String id);
}
