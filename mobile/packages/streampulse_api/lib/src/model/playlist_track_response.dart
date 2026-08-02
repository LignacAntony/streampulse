//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'playlist_track_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class PlaylistTrackResponse {
  /// Returns a new [PlaylistTrackResponse] instance.
  PlaylistTrackResponse({
    required this.id,

    required this.title,

    required this.artist,

    required this.durationS,

    required this.position,
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

  /// Zero-based position of the track within the playlist.
  @JsonKey(name: r'position', required: true, includeIfNull: false)
  final int position;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlaylistTrackResponse &&
          other.id == id &&
          other.title == title &&
          other.artist == artist &&
          other.durationS == durationS &&
          other.position == position;

  @override
  int get hashCode =>
      id.hashCode +
      title.hashCode +
      (artist == null ? 0 : artist.hashCode) +
      (durationS == null ? 0 : durationS.hashCode) +
      position.hashCode;

  factory PlaylistTrackResponse.fromJson(Map<String, dynamic> json) =>
      _$PlaylistTrackResponseFromJson(json);

  Map<String, dynamic> toJson() => _$PlaylistTrackResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
