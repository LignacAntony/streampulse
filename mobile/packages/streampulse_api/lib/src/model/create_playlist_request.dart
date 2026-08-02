//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'create_playlist_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class CreatePlaylistRequest {
  /// Returns a new [CreatePlaylistRequest] instance.
  CreatePlaylistRequest({required this.name, this.description});

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'description', required: false, includeIfNull: false)
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CreatePlaylistRequest &&
          other.name == name &&
          other.description == description;

  @override
  int get hashCode =>
      name.hashCode + (description == null ? 0 : description.hashCode);

  factory CreatePlaylistRequest.fromJson(Map<String, dynamic> json) =>
      _$CreatePlaylistRequestFromJson(json);

  Map<String, dynamic> toJson() => _$CreatePlaylistRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
