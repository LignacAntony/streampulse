//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'stream_summary_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class StreamSummaryResponse {
  /// Returns a new [StreamSummaryResponse] instance.
  StreamSummaryResponse({
    required this.id,

    required this.userId,

    required this.title,

    required this.description,

    required this.category,

    required this.status,

    required this.isPublic,

    required this.startedAt,

    required this.createdAt,
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
  final StreamSummaryResponseStatusEnum status;

  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  @JsonKey(name: r'started_at', required: true, includeIfNull: true)
  final DateTime? startedAt;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreamSummaryResponse &&
          other.id == id &&
          other.userId == userId &&
          other.title == title &&
          other.description == description &&
          other.category == category &&
          other.status == status &&
          other.isPublic == isPublic &&
          other.startedAt == startedAt &&
          other.createdAt == createdAt;

  @override
  int get hashCode =>
      id.hashCode +
      userId.hashCode +
      title.hashCode +
      (description == null ? 0 : description.hashCode) +
      (category == null ? 0 : category.hashCode) +
      status.hashCode +
      isPublic.hashCode +
      (startedAt == null ? 0 : startedAt.hashCode) +
      createdAt.hashCode;

  factory StreamSummaryResponse.fromJson(Map<String, dynamic> json) =>
      _$StreamSummaryResponseFromJson(json);

  Map<String, dynamic> toJson() => _$StreamSummaryResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum StreamSummaryResponseStatusEnum {
  @JsonValue(r'idle')
  idle(r'idle'),
  @JsonValue(r'live')
  live(r'live'),
  @JsonValue(r'ended')
  ended(r'ended');

  const StreamSummaryResponseStatusEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
