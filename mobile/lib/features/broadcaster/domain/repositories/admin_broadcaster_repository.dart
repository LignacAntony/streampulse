import '../entities/admin_broadcaster_request.dart';
import '../entities/broadcaster_request.dart';

/// Revue admin des demandes de rôle diffuseur (routes `/api/admin/
/// broadcaster-requests`). Interface étroite (ISP) : uniquement ce dont
/// l'écran d'administration a besoin.
abstract class AdminBroadcasterRepository {
  /// Liste les demandes, filtrées par [status] si fourni. Typé avec l'enum
  /// domaine (pas une chaîne) : la conversion vers la valeur réseau
  /// (`.name`) se fait au bord, dans l'implémentation.
  Future<List<AdminBroadcasterRequest>> list({BroadcasterRequestStatus? status});

  /// Approuve la demande [id] (promeut l'utilisateur) ; [note] optionnelle.
  /// Relaie l'exception (409 si déjà traitée).
  Future<void> approve(String id, {String? note});

  /// Refuse la demande [id] ; [note] optionnelle. Relaie l'exception.
  Future<void> reject(String id, {String? note});
}
