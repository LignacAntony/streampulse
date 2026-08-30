//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'global_ban_user_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GlobalBanUserRequest {
  /// Returns a new [GlobalBanUserRequest] instance.
  GlobalBanUserRequest({this.reason});

  @JsonKey(name: r'reason', required: false, includeIfNull: false)
  final String? reason;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalBanUserRequest && other.reason == reason;

  @override
  int get hashCode => (reason == null ? 0 : reason.hashCode);

  factory GlobalBanUserRequest.fromJson(Map<String, dynamic> json) =>
      _$GlobalBanUserRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GlobalBanUserRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
