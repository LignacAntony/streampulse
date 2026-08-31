import '../entities/admin_broadcaster_request.dart';

/// Revue admin des demandes de rôle diffuseur (routes `/api/admin/
/// broadcaster-requests`). Interface étroite (ISP) : uniquement ce dont
/// l'écran d'administration a besoin.
abstract class AdminBroadcasterRepository {
  /// Liste les demandes, filtrées par statut si [status] est fourni
  /// (`pending`/`approved`/`rejected`).
  Future<List<AdminBroadcasterRequest>> list({String? status});

  /// Approuve la demande [id] (promeut l'utilisateur) ; [note] optionnelle.
  /// Relaie l'exception (409 si déjà traitée).
  Future<void> approve(String id, {String? note});

  /// Refuse la demande [id] ; [note] optionnelle. Relaie l'exception.
  Future<void> reject(String id, {String? note});
}
