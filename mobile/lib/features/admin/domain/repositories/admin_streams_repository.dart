import '../entities/admin_stream.dart';

/// Supervision des flux en direct (admin uniquement) — interface SÉPARÉE de
/// `AdminRepository` (ISP) : gestion des flux, distincte de la gestion des
/// comptes utilisateurs.
abstract class AdminStreamsRepository {
  /// Liste paginée des flux actuellement en direct, publics et privés, avec
  /// l'identité du diffuseur (admin uniquement). `total` est le nombre total
  /// de flux live, pour la pagination côté UI.
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  });

  /// Arrête de force un flux en direct (admin uniquement), sans vérification
  /// de propriété. Action de modération, journalisée côté serveur.
  Future<void> stopStream(String id);
}
