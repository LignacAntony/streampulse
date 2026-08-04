//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'update_playlist_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UpdatePlaylistRequest {
  /// Returns a new [UpdatePlaylistRequest] instance.
  UpdatePlaylistRequest({required this.name, this.description});

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'description', required: false, includeIfNull: false)
  final String? description;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdatePlaylistRequest &&
          other.name == name &&
          other.description == description;

  @override
  int get hashCode =>
      name.hashCode + (description == null ? 0 : description.hashCode);

  factory UpdatePlaylistRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdatePlaylistRequestFromJson(json);

  Map<String, dynamic> toJson() => _$UpdatePlaylistRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
