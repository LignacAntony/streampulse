import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/broadcaster_request.dart';

/// Conversion DTO généré (package `streampulse_api`) → entité domaine.
/// Confine la dépendance au client généré à la couche data : l'enum de statut
/// généré ne fuit pas hors d'ici, on renvoie le `BroadcasterRequestStatus` pur.
extension BroadcasterRequestResponseMapper on BroadcasterRequestResponse {
  BroadcasterRequest toEntity() => BroadcasterRequest(
        id: id,
        status: _statusFromValue(status.value),
        message: message,
        reviewNote: reviewNote,
        reviewedBy: reviewedBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

BroadcasterRequestStatus _statusFromValue(String value) {
  switch (value) {
    case 'approved':
      return BroadcasterRequestStatus.approved;
    case 'rejected':
      return BroadcasterRequestStatus.rejected;
    case 'pending':
    default:
      return BroadcasterRequestStatus.pending;
  }
}
