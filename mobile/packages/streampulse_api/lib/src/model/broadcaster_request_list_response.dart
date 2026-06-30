//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/broadcaster_request_admin.dart';
import 'package:json_annotation/json_annotation.dart';

part 'broadcaster_request_list_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class BroadcasterRequestListResponse {
  /// Returns a new [BroadcasterRequestListResponse] instance.
  BroadcasterRequestListResponse({required this.requests});

  @JsonKey(name: r'requests', required: true, includeIfNull: false)
  final List<BroadcasterRequestAdmin> requests;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcasterRequestListResponse && other.requests == requests;

  @override
  int get hashCode => requests.hashCode;

  factory BroadcasterRequestListResponse.fromJson(Map<String, dynamic> json) =>
      _$BroadcasterRequestListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$BroadcasterRequestListResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
