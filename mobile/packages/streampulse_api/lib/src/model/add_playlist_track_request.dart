//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'add_playlist_track_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AddPlaylistTrackRequest {
  /// Returns a new [AddPlaylistTrackRequest] instance.
  AddPlaylistTrackRequest({required this.trackId});

  /// Identifier of one of the user's own tracks.
  @JsonKey(name: r'track_id', required: true, includeIfNull: false)
  final String trackId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AddPlaylistTrackRequest && other.trackId == trackId;

  @override
  int get hashCode => trackId.hashCode;

  factory AddPlaylistTrackRequest.fromJson(Map<String, dynamic> json) =>
      _$AddPlaylistTrackRequestFromJson(json);

  Map<String, dynamic> toJson() => _$AddPlaylistTrackRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
