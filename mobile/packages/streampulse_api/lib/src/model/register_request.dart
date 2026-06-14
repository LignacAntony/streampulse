//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'register_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class RegisterRequest {
  /// Returns a new [RegisterRequest] instance.
  RegisterRequest({
    required this.email,

    required this.username,

    required this.password,
  });

  @JsonKey(name: r'email', required: true, includeIfNull: false)
  final String email;

  @JsonKey(name: r'username', required: true, includeIfNull: false)
  final String username;

  @JsonKey(name: r'password', required: true, includeIfNull: false)
  final String password;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegisterRequest &&
          other.email == email &&
          other.username == username &&
          other.password == password;

  @override
  int get hashCode => email.hashCode + username.hashCode + password.hashCode;

  factory RegisterRequest.fromJson(Map<String, dynamic> json) =>
      _$RegisterRequestFromJson(json);

  Map<String, dynamic> toJson() => _$RegisterRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
