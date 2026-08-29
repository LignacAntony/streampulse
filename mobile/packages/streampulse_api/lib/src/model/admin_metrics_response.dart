//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:streampulse_api/src/model/admin_metrics_http.dart';
import 'package:streampulse_api/src/model/admin_metrics_users.dart';
import 'package:streampulse_api/src/model/admin_metrics_streams.dart';
import 'package:json_annotation/json_annotation.dart';

part 'admin_metrics_response.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminMetricsResponse {
  /// Returns a new [AdminMetricsResponse] instance.
  AdminMetricsResponse({
    required this.uptimeSeconds,

    required this.streams,

    required this.http,

    required this.users,
  });

  /// Seconds elapsed since the API process started.
  @JsonKey(name: r'uptime_seconds', required: true, includeIfNull: false)
  final int uptimeSeconds;

  @JsonKey(name: r'streams', required: true, includeIfNull: false)
  final AdminMetricsStreams streams;

  @JsonKey(name: r'http', required: true, includeIfNull: false)
  final AdminMetricsHTTP http;

  @JsonKey(name: r'users', required: true, includeIfNull: false)
  final AdminMetricsUsers users;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminMetricsResponse &&
          other.uptimeSeconds == uptimeSeconds &&
          other.streams == streams &&
          other.http == http &&
          other.users == users;

  @override
  int get hashCode =>
      uptimeSeconds.hashCode +
      streams.hashCode +
      http.hashCode +
      users.hashCode;

  factory AdminMetricsResponse.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsResponseFromJson(json);

  Map<String, dynamic> toJson() => _$AdminMetricsResponseToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
