// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_http.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminMetricsHTTP _$AdminMetricsHTTPFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminMetricsHTTP',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'requests_total',
            'client_errors_total',
            'server_errors_total',
            'response_bytes_total',
            'server_error_rate',
          ],
        );
        final val = AdminMetricsHTTP(
          requestsTotal: $checkedConvert(
            'requests_total',
            (v) => (v as num).toInt(),
          ),
          clientErrorsTotal: $checkedConvert(
            'client_errors_total',
            (v) => (v as num).toInt(),
          ),
          serverErrorsTotal: $checkedConvert(
            'server_errors_total',
            (v) => (v as num).toInt(),
          ),
          responseBytesTotal: $checkedConvert(
            'response_bytes_total',
            (v) => (v as num).toInt(),
          ),
          serverErrorRate: $checkedConvert(
            'server_error_rate',
            (v) => (v as num).toDouble(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'requestsTotal': 'requests_total',
        'clientErrorsTotal': 'client_errors_total',
        'serverErrorsTotal': 'server_errors_total',
        'responseBytesTotal': 'response_bytes_total',
        'serverErrorRate': 'server_error_rate',
      },
    );

Map<String, dynamic> _$AdminMetricsHTTPToJson(AdminMetricsHTTP instance) =>
    <String, dynamic>{
      'requests_total': instance.requestsTotal,
      'client_errors_total': instance.clientErrorsTotal,
      'server_errors_total': instance.serverErrorsTotal,
      'response_bytes_total': instance.responseBytesTotal,
      'server_error_rate': instance.serverErrorRate,
    };
