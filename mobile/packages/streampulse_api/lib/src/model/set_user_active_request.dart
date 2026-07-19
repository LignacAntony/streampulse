//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'set_user_active_request.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class SetUserActiveRequest {
  /// Returns a new [SetUserActiveRequest] instance.
  SetUserActiveRequest({required this.isActive});

  @JsonKey(name: r'is_active', required: true, includeIfNull: false)
  final bool isActive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetUserActiveRequest && other.isActive == isActive;

  @override
  int get hashCode => isActive.hashCode;

  factory SetUserActiveRequest.fromJson(Map<String, dynamic> json) =>
      _$SetUserActiveRequestFromJson(json);

  Map<String, dynamic> toJson() => _$SetUserActiveRequestToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
