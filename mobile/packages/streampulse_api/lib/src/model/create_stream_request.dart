//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'create_stream_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreateStreamRequest {
  /// Returns a new [CreateStreamRequest] instance.
  CreateStreamRequest({
    required this.title,

    this.description,

    this.category,

    required this.isPublic,
  });

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'description', required: false, includeIfNull: false)
  final String? description;

  @JsonKey(name: r'category', required: false, includeIfNull: false)
  final CreateStreamRequestCategoryEnum? category;

  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreateStreamRequest &&
          other.title == title &&
          other.description == description &&
          other.category == category &&
          other.isPublic == isPublic;

  @override
  int get hashCode =>
      title.hashCode +
      (description == null ? 0 : description.hashCode) +
      (category == null ? 0 : category.hashCode) +
      isPublic.hashCode;

  factory CreateStreamRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateStreamRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CreateStreamRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}

enum CreateStreamRequestCategoryEnum {
  @JsonValue(r'music')
  music(r'music'),
  @JsonValue(r'talk')
  talk(r'talk'),
  @JsonValue(r'technology')
  technology(r'technology'),
  @JsonValue(r'gaming')
  gaming(r'gaming'),
  @JsonValue(r'news')
  news(r'news'),
  @JsonValue(r'sport')
  sport(r'sport'),
  @JsonValue(r'other')
  other(r'other');

  const CreateStreamRequestCategoryEnum(this.value);

  final String value;

  @override
  String toString() => value;
}
