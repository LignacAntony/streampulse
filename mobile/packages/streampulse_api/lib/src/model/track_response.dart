//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'track_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class TrackResponse {
  /// Returns a new [TrackResponse] instance.
  TrackResponse({
    required this.id,

    required this.title,

    required this.artist,

    required this.durationS,
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrackResponse &&
          other.id == id &&
          other.title == title &&
          other.artist == artist &&
          other.durationS == durationS;

  @override
  int get hashCode =>
      id.hashCode +
      title.hashCode +
      (artist == null ? 0 : artist.hashCode) +
      (durationS == null ? 0 : durationS.hashCode);

  factory TrackResponse.fromJson(Map<String, dynamic> json) =>
      _$TrackResponseFromJson(json);

  Map<String, dynamic> toJson() => _$TrackResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
