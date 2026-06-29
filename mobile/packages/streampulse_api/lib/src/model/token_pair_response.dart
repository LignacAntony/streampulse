//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'token_pair_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class TokenPairResponse {
  /// Returns a new [TokenPairResponse] instance.
  TokenPairResponse({required this.accessToken, required this.refreshToken});

  @JsonKey(name: r'access_token', required: true, includeIfNull: false)
  final String accessToken;

  @JsonKey(name: r'refresh_token', required: true, includeIfNull: false)
  final String refreshToken;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenPairResponse &&
          other.accessToken == accessToken &&
          other.refreshToken == refreshToken;

  @override
  int get hashCode => accessToken.hashCode + refreshToken.hashCode;

  factory TokenPairResponse.fromJson(Map<String, dynamic> json) =>
      _$TokenPairResponseFromJson(json);

  Map<String, dynamic> toJson() => _$TokenPairResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
