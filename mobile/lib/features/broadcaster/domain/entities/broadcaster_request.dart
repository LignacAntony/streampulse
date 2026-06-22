/// Statut d'une demande de rôle diffuseur, miroir du `CHECK` SQL côté backend.
enum BroadcasterRequestStatus { pending, approved, rejected }

/// Entité domaine d'une demande de passage au rôle diffuseur.
///
/// Pure (aucune dépendance Flutter/infra) : le mapping depuis le DTO généré
/// vit dans la couche data (`broadcaster_dto_mappers.dart`).
class BroadcasterRequest {
  const BroadcasterRequest({
    required this.id,
    required this.status,
    required this.message,
    required this.reviewNote,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
  });

  final String id;
  final BroadcasterRequestStatus status;
  final String message;
  final String reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Identifiant de l'admin ayant traité la demande (null tant que `pending`).
  final String? reviewedBy;

  bool get isPending => status == BroadcasterRequestStatus.pending;
  bool get isApproved => status == BroadcasterRequestStatus.approved;
  bool get isRejected => status == BroadcasterRequestStatus.rejected;
}
