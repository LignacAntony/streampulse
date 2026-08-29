//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'public_track_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PublicTrackResponse {
  /// Returns a new [PublicTrackResponse] instance.
  PublicTrackResponse({
    required this.id,

    required this.title,

    required this.artist,

    required this.durationS,

    required this.ownerName,
  });

  @JsonKey(name: r'id', required: true, includeIfNull: false)
  final String id;

  @JsonKey(name: r'title', required: true, includeIfNull: false)
  final String title;

  @JsonKey(name: r'artist', required: true, includeIfNull: true)
  final String? artist;

  /// Track duration in seconds.
  @JsonKey(name: r'duration_s', required: true, includeIfNull: true)
  final int? durationS;

  /// Username of the track owner.
  @JsonKey(name: r'owner_name', required: true, includeIfNull: false)
  final String ownerName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicTrackResponse &&
          other.id == id &&
          other.title == title &&
          other.artist == artist &&
          other.durationS == durationS &&
          other.ownerName == ownerName;

  @override
  int get hashCode =>
      id.hashCode +
      title.hashCode +
      (artist == null ? 0 : artist.hashCode) +
      (durationS == null ? 0 : durationS.hashCode) +
      ownerName.hashCode;

  factory PublicTrackResponse.fromJson(Map<String, dynamic> json) =>
      _$PublicTrackResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PublicTrackResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
