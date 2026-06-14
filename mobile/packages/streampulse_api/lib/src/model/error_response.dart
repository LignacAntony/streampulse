//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/error_detail.dart';
import 'package:json_annotation/json_annotation.dart';

part 'error_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ErrorResponse {
  /// Returns a new [ErrorResponse] instance.
  ErrorResponse({required this.error});

  @JsonKey(name: r'error', required: true, includeIfNull: false)
  final ErrorDetail error;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ErrorResponse && other.error == error;

  @override
  int get hashCode => error.hashCode;

  factory ErrorResponse.fromJson(Map<String, dynamic> json) =>
      _$ErrorResponseFromJson(json);

  Map<String, dynamic> toJson() => _$ErrorResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
