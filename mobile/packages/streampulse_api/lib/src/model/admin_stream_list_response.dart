//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/admin_stream_response.dart';
import 'package:json_annotation/json_annotation.dart';

part 'admin_stream_list_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminStreamListResponse {
  /// Returns a new [AdminStreamListResponse] instance.
  AdminStreamListResponse({required this.streams, required this.total});

  @JsonKey(name: r'streams', required: true, includeIfNull: false)
  final List<AdminStreamResponse> streams;

  /// Total number of live streams currently in the moderation list.
  @JsonKey(name: r'total', required: true, includeIfNull: false)
  final int total;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminStreamListResponse &&
          other.streams == streams &&
          other.total == total;

  @override
  int get hashCode => streams.hashCode + total.hashCode;

  factory AdminStreamListResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminStreamListResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AdminStreamListResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
