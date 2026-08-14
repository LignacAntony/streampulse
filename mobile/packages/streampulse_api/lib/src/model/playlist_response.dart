//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'playlist_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PlaylistResponse {
  /// Returns a new [PlaylistResponse] instance.
  PlaylistResponse({
    required this.id,

    required this.name,

    required this.description,

    required this.isPublic,

    required this.trackCount,

    required this.createdAt,

    required this.updatedAt,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'name', required: true, includeIfNull: false)
  final String name;

  @JsonKey(name: r'description', required: true, includeIfNull: true)
  final String? description;

  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  /// Number of tracks in the playlist.
  @JsonKey(name: r'track_count', required: true, includeIfNull: false)
  final int trackCount;

  @JsonKey(name: r'created_at', required: true, includeIfNull: false)
  final DateTime createdAt;

  @JsonKey(name: r'updated_at', required: true, includeIfNull: false)
  final DateTime updatedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistResponse &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.isPublic == isPublic &&
          other.trackCount == trackCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode =>
      id.hashCode +
      name.hashCode +
      (description == null ? 0 : description.hashCode) +
      isPublic.hashCode +
      trackCount.hashCode +
      createdAt.hashCode +
      updatedAt.hashCode;

  factory PlaylistResponse.fromJson(Map<String, dynamic> json) =>
      _$PlaylistResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PlaylistResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
