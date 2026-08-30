//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'update_track_visibility_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class UpdateTrackVisibilityRequest {
  /// Returns a new [UpdateTrackVisibilityRequest] instance.
  UpdateTrackVisibilityRequest({required this.isPublic});

  /// Whether the track should be public.
  @JsonKey(name: r'is_public', required: true, includeIfNull: false)
  final bool isPublic;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UpdateTrackVisibilityRequest && other.isPublic == isPublic;

  @override
  int get hashCode => isPublic.hashCode;

  factory UpdateTrackVisibilityRequest.fromJson(Map<String, dynamic> json) =>
      _$UpdateTrackVisibilityRequestFromJson(json);

  Map<String, dynamic> toJson() => _$UpdateTrackVisibilityRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
