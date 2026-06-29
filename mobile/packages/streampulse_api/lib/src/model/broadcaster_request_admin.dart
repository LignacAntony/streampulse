//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'broadcaster_request_admin.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class BroadcasterRequestAdmin {
  /// Returns a new [BroadcasterRequestAdmin] instance.
  BroadcasterRequestAdmin({
    required this.id,

    required this.status,

    required this.message,

    required this.reviewNote,

    required this.reviewedBy,

    required this.createdAt,

    required this.updatedAt,

    required this.userId,

    required this.email,

    required this.username,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final BroadcasterRequestAdminStatusEnum status;

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

  @JsonKey(name: r'user_id', required: true, includeIfNull: false)
  final String userId;

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcasterRequestAdmin &&
          other.id == id &&
          other.status == status &&
          other.message == message &&
          other.reviewNote == reviewNote &&
          other.reviewedBy == reviewedBy &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt &&
          other.userId == userId &&
          other.email == email &&
          other.username == username;

  @override
  int get hashCode =>
      id.hashCode +
      status.hashCode +
      message.hashCode +
      reviewNote.hashCode +
      (reviewedBy == null ? 0 : reviewedBy.hashCode) +
      createdAt.hashCode +
      updatedAt.hashCode +
      userId.hashCode +
      email.hashCode +
      username.hashCode;

  factory BroadcasterRequestAdmin.fromJson(Map<String, dynamic> json) =>
      _$BroadcasterRequestAdminFromJson(json);

  Map<String, dynamic> toJson() => _$BroadcasterRequestAdminToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum BroadcasterRequestAdminStatusEnum {
  @JsonValue(r'pending')
  pending(r'pending'),
  @JsonValue(r'approved')
  approved(r'approved'),
  @JsonValue(r'rejected')
  rejected(r'rejected');

  const BroadcasterRequestAdminStatusEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
