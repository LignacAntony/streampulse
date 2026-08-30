//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_chat_message.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminChatMessage {
  /// Returns a new [AdminChatMessage] instance.
  AdminChatMessage({
    required this.id,

    required this.streamId,

    required this.username,

    required this.content,

    required this.createdAt,

    required this.streamTitle,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'stream_id', required: true, includeIfNull: false)
  final String streamId;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @JsonKey(name: r'content', required: true, includeIfNull: false)
  final String content;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'stream_title', required: true, includeIfNull: false)
  final String streamTitle;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminChatMessage &&
          other.id == id &&
          other.streamId == streamId &&
          other.username == username &&
          other.content == content &&
          other.createdAt == createdAt &&
          other.streamTitle == streamTitle;

  @override
  int get hashCode =>
      id.hashCode +
      streamId.hashCode +
      username.hashCode +
      content.hashCode +
      createdAt.hashCode +
      streamTitle.hashCode;

  factory AdminChatMessage.fromJson(Map<String, dynamic> json) =>
      _$AdminChatMessageFromJson(json);

  Map<String, dynamic> toJson() => _$AdminChatMessageToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
