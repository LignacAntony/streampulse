//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//

// ignore_for_file: unused_element
import 'package:json_annotation/json_annotation.dart';

part 'admin_metrics_http.g.dart';

@JsonSerializable(
  checked: true,
  createToJson: true,
  disallowUnrecognizedKeys: false,
  explicitToJson: true,
)
class AdminMetricsHTTP {
  /// Returns a new [AdminMetricsHTTP] instance.
  AdminMetricsHTTP({
    required this.requestsTotal,

    required this.clientErrorsTotal,

    required this.serverErrorsTotal,

    required this.responseBytesTotal,

    required this.serverErrorRate,
  });

  /// HTTP requests served since process start.
  @JsonKey(name: r'requests_total', required: true, includeIfNull: false)
  final int requestsTotal;

  /// Responses with a 4xx status since process start.
  @JsonKey(name: r'client_errors_total', required: true, includeIfNull: false)
  final int clientErrorsTotal;

  /// Responses with a 5xx status since process start.
  @JsonKey(name: r'server_errors_total', required: true, includeIfNull: false)
  final int serverErrorsTotal;

  /// Response body bytes written to clients since process start. Inbound broadcaster ingest is not counted — it travels through the request body, which this counter does not observe.
  @JsonKey(name: r'response_bytes_total', required: true, includeIfNull: false)
  final int responseBytesTotal;

  /// server_errors_total divided by requests_total, since process start. Zero when no request has been served yet.
  @JsonKey(name: r'server_error_rate', required: true, includeIfNull: false)
  final double serverErrorRate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdminMetricsHTTP &&
          other.requestsTotal == requestsTotal &&
          other.clientErrorsTotal == clientErrorsTotal &&
          other.serverErrorsTotal == serverErrorsTotal &&
          other.responseBytesTotal == responseBytesTotal &&
          other.serverErrorRate == serverErrorRate;

  @override
  int get hashCode =>
      requestsTotal.hashCode +
      clientErrorsTotal.hashCode +
      serverErrorsTotal.hashCode +
      responseBytesTotal.hashCode +
      serverErrorRate.hashCode;

  factory AdminMetricsHTTP.fromJson(Map<String, dynamic> json) =>
      _$AdminMetricsHTTPFromJson(json);

  Map<String, dynamic> toJson() => _$AdminMetricsHTTPToJson(this);

  @override
  String toString() {
    return toJson().toString();
  }
}
