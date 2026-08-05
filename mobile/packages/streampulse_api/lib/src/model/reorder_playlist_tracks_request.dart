//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'reorder_playlist_tracks_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReorderPlaylistTracksRequest {
  /// Returns a new [ReorderPlaylistTracksRequest] instance.
  ReorderPlaylistTracksRequest({required this.trackIds});

  /// Complete, duplicate-free list of the playlist's track identifiers, in the wanted order (index 0 = first track).
  @JsonKey(name: r'track_ids', required: true, includeIfNull: false)
  final List<String> trackIds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReorderPlaylistTracksRequest && other.trackIds == trackIds;

  @override
  int get hashCode => trackIds.hashCode;

  factory ReorderPlaylistTracksRequest.fromJson(Map<String, dynamic> json) =>
      _$ReorderPlaylistTracksRequestFromJson(json);

  Map<String, dynamic> toJson() => _$ReorderPlaylistTracksRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
