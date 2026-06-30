//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'review_request_input.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class ReviewRequestInput {
  /// Returns a new [ReviewRequestInput] instance.
  ReviewRequestInput({this.reviewNote});

  /// Optional note explaining the admin decision.
  @JsonKey(name: r'review_note', required: false, includeIfNull: false)
  final String? reviewNote;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewRequestInput && other.reviewNote == reviewNote;

  @override
  int get hashCode => reviewNote.hashCode;

  factory ReviewRequestInput.fromJson(Map<String, dynamic> json) =>
      _$ReviewRequestInputFromJson(json);

  Map<String, dynamic> toJson() => _$ReviewRequestInputToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
