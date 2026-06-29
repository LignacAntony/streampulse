import 'package:streampulse_api/streampulse_api.dart';

import '../../domain/entities/broadcaster_request.dart';

extension BroadcasterRequestResponseMapper on BroadcasterRequestResponse {
  BroadcasterRequest toEntity() => BroadcasterRequest(
        id: id,
        status: _statusFromDto(status),
        message: message,
        reviewNote: reviewNote,
        reviewedBy: reviewedBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

BroadcasterRequestStatus _statusFromDto(BroadcasterRequestResponseStatusEnum s) {
  switch (s) {
    case BroadcasterRequestResponseStatusEnum.pending:
      return BroadcasterRequestStatus.pending;
    case BroadcasterRequestResponseStatusEnum.approved:
      return BroadcasterRequestStatus.approved;
    case BroadcasterRequestResponseStatusEnum.rejected:
      return BroadcasterRequestStatus.rejected;
  }
}
