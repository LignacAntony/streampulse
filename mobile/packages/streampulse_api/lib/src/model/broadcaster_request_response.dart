//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'broadcaster_request_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class BroadcasterRequestResponse {
  /// Returns a new [BroadcasterRequestResponse] instance.
  BroadcasterRequestResponse({
    required this.id,

    required this.status,

    required this.message,

    required this.reviewNote,

    required this.reviewedBy,

    required this.createdAt,

    required this.updatedAt,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final BroadcasterRequestResponseStatusEnum status;

  @JsonKey(name: r'message', required: true, includeIfNull: false)
  final String message;

  @JsonKey(name: r'review_note', required: true, includeIfNull: false)
  final String reviewNote;

  @JsonKey(name: r'reviewed_by', required: true, includeIfNull: true)
  final String? reviewedBy;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'updated_at', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcasterRequestResponse &&
          other.id == id &&
          other.status == status &&
          other.message == message &&
          other.reviewNote == reviewNote &&
          other.reviewedBy == reviewedBy &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      id.hashCode +
      status.hashCode +
      message.hashCode +
      reviewNote.hashCode +
      (reviewedBy == null ? 0 : reviewedBy.hashCode) +
      createdAt.hashCode +
      updatedAt.hashCode;

  factory BroadcasterRequestResponse.fromJson(Map<String, dynamic> json) =>
      _$BroadcasterRequestResponseFromJson(json);

  Map<String, dynamic> toJson() => _$BroadcasterRequestResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum BroadcasterRequestResponseStatusEnum {
  @JsonValue(r'pending')
  pending(r'pending'),
  @JsonValue(r'approved')
  approved(r'approved'),
  @JsonValue(r'rejected')
  rejected(r'rejected');

  const BroadcasterRequestResponseStatusEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
