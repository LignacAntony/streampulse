//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'logout_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class LogoutRequest {
  /// Returns a new [LogoutRequest] instance.
  LogoutRequest({required this.refreshToken});

  @JsonKey(name: r'refresh_token', required: true, includeIfNull: false)
  final String refreshToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoutRequest && other.refreshToken == refreshToken;

  @override
  int get hashCode => refreshToken.hashCode;

  factory LogoutRequest.fromJson(Map<String, dynamic> json) =>
      _$LogoutRequestFromJson(json);

  Map<String, dynamic> toJson() => _$LogoutRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
