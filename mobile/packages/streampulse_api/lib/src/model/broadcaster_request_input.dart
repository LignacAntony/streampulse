//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'broadcaster_request_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class BroadcasterRequestInput {
  /// Returns a new [BroadcasterRequestInput] instance.
  BroadcasterRequestInput({this.message});

  /// Optional motivation message for the request.
  @JsonKey(name: r'message', required: false, includeIfNull: false)
  final String? message;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcasterRequestInput && other.message == message;

  @override
  int get hashCode => message.hashCode;

  factory BroadcasterRequestInput.fromJson(Map<String, dynamic> json) =>
      _$BroadcasterRequestInputFromJson(json);

  Map<String, dynamic> toJson() => _$BroadcasterRequestInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
