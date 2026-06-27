//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/stream_response.dart';
import 'package:streampulse_api/src/model/stream_summary_response.dart';
import 'package:json_annotation/json_annotation.dart';

part 'get_stream200_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GetStream200Response {
  /// Returns a new [GetStream200Response] instance.
  GetStream200Response({
    required this.id,

    required this.userId,

    required this.title,

    required this.description,

    required this.category,

    required this.status,

    required this.isPublic,

    required this.streamKey,

    required this.streamSourceUrl,

    required this.startedAt,

    required this.endedAt,

    required this.createdAt,

    required this.updatedAt,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'user_id', required: true, includeIfNull: false)
  final String userId;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'description', required: true, includeIfNull: true)
  final String? description;

  @JsonKey(name: r'category', required: true, includeIfNull: true)
  final String? category;

  @JsonKey(name: r'status', required: true, includeIfNull: false)
  final GetStream200ResponseStatusEnum status;

  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  /// Secret push key for the source URL. Treat as a credential.
  @JsonKey(name: r'stream_key', required: true, includeIfNull: false)
  final String streamKey;

  @JsonKey(name: r'stream_source_url', required: true, includeIfNull: false)
  final String streamSourceUrl;

  @JsonKey(name: r'started_at', required: true, includeIfNull: true)
  final DateTime? startedAt;

  @JsonKey(name: r'ended_at', required: true, includeIfNull: true)
  final DateTime? endedAt;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'updated_at', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GetStream200Response &&
          other.id == id &&
          other.userId == userId &&
          other.title == title &&
          other.description == description &&
          other.category == category &&
          other.status == status &&
          other.isPublic == isPublic &&
          other.streamKey == streamKey &&
          other.streamSourceUrl == streamSourceUrl &&
          other.startedAt == startedAt &&
          other.endedAt == endedAt &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      id.hashCode +
      userId.hashCode +
      title.hashCode +
      (description == null ? 0 : description.hashCode) +
      (category == null ? 0 : category.hashCode) +
      status.hashCode +
      isPublic.hashCode +
      streamKey.hashCode +
      streamSourceUrl.hashCode +
      (startedAt == null ? 0 : startedAt.hashCode) +
      (endedAt == null ? 0 : endedAt.hashCode) +
      createdAt.hashCode +
      updatedAt.hashCode;

  factory GetStream200Response.fromJson(Map<String, dynamic> json) =>
      _$GetStream200ResponseFromJson(json);

  Map<String, dynamic> toJson() => _$GetStream200ResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum GetStream200ResponseStatusEnum {
  @JsonValue(r'idle')
  idle(r'idle'),
  @JsonValue(r'live')
  live(r'live'),
  @JsonValue(r'ended')
  ended(r'ended');

  const GetStream200ResponseStatusEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
