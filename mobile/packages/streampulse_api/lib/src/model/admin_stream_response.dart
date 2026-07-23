//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_stream_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminStreamResponse {
  /// Returns a new [AdminStreamResponse] instance.
  AdminStreamResponse({
    required this.id,

    required this.title,

    required this.isPublic,

    required this.startedAt,

    required this.userId,

    required this.username,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  @JsonKey(name: r'started_at', required: true, includeIfNull: true)
  final DateTime? startedAt;

  @JsonKey(name: r'user_id', required: true, includeIfNull: false)
  final String userId;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminStreamResponse &&
          other.id == id &&
          other.title == title &&
          other.isPublic == isPublic &&
          other.startedAt == startedAt &&
          other.userId == userId &&
          other.username == username;

  @override
  int get hashCode =>
      id.hashCode +
      title.hashCode +
      isPublic.hashCode +
      (startedAt == null ? 0 : startedAt.hashCode) +
      userId.hashCode +
      username.hashCode;

  factory AdminStreamResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminStreamResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AdminStreamResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
