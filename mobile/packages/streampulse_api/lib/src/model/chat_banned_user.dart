//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'chat_banned_user.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ChatBannedUser {
  /// Returns a new [ChatBannedUser] instance.
  ChatBannedUser({
    required this.userId,

    required this.username,

    this.reason,

    required this.createdAt,
  });

  @JsonKey(name: r'user_id', required: true, includeIfNull: false)
  final String userId;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @JsonKey(name: r'reason', required: false, includeIfNull: false)
  final String? reason;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatBannedUser &&
          other.userId == userId &&
          other.username == username &&
          other.reason == reason &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      userId.hashCode +
      username.hashCode +
      (reason == null ? 0 : reason.hashCode) +
      createdAt.hashCode;

  factory ChatBannedUser.fromJson(Map<String, dynamic> json) =>
      _$ChatBannedUserFromJson(json);

  Map<String, dynamic> toJson() => _$ChatBannedUserToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
