import 'broadcaster_request.dart';

/// Demande de rôle diffuseur telle que vue par un **administrateur** (US-01,
/// route `GET /api/admin/broadcaster-requests`). Contrairement à
/// [BroadcasterRequest] (la demande « la mienne »), elle porte l'identité du
/// demandeur (`userId`/`email`/`username`) : l'admin doit savoir *qui* demande
/// avant d'approuver ou de refuser.
class AdminBroadcasterRequest {
  const AdminBroadcasterRequest({
    required this.id,
    required this.status,
    required this.message,
    required this.reviewNote,
    required this.userId,
    required this.email,
    required this.username,
    required this.createdAt,
    required this.updatedAt,
    this.reviewedBy,
  });

  final String id;
  final BroadcasterRequestStatus status;
  final String message;
  final String reviewNote;
  final String userId;
  final String email;
  final String username;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewedBy;

  bool get isPending => status == BroadcasterRequestStatus.pending;
  bool get isApproved => status == BroadcasterRequestStatus.approved;
  bool get isRejected => status == BroadcasterRequestStatus.rejected;

  AdminBroadcasterRequest copyWith({BroadcasterRequestStatus? status}) =>
      AdminBroadcasterRequest(
        id: id,
        status: status ?? this.status,
        message: message,
        reviewNote: reviewNote,
        userId: userId,
        email: email,
        username: username,
        reviewedBy: reviewedBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
