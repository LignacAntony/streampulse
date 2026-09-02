//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'google_login_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class GoogleLoginRequest {
  /// Returns a new [GoogleLoginRequest] instance.
  GoogleLoginRequest({required this.idToken});

  /// Google ID token (JWT) obtained on the device via Sign in with Google.
  @JsonKey(name: r'id_token', required: true, includeIfNull: false)
  final String idToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GoogleLoginRequest && other.idToken == idToken;

  @override
  int get hashCode => idToken.hashCode;

  factory GoogleLoginRequest.fromJson(Map<String, dynamic> json) =>
      _$GoogleLoginRequestFromJson(json);

  Map<String, dynamic> toJson() => _$GoogleLoginRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
