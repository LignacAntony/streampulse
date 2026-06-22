enum BroadcasterRequestStatus { pending, approved, rejected }

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
  final String? reviewedBy;

  bool get isPending => status == BroadcasterRequestStatus.pending;
  bool get isApproved => status == BroadcasterRequestStatus.approved;
  bool get isRejected => status == BroadcasterRequestStatus.rejected;
}
