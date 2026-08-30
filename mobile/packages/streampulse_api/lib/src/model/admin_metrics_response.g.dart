// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminMetricsResponse _$AdminMetricsResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'AdminMetricsResponse',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const ['uptime_seconds', 'streams', 'http', 'users'],
    );
    final val = AdminMetricsResponse(
      uptimeSeconds: $checkedConvert(
        'uptime_seconds',
        (v) => (v as num).toInt(),
      ),
      streams: $checkedConvert(
        'streams',
        (v) => AdminMetricsStreams.fromJson(v as Map<String, dynamic>),
      ),
      http: $checkedConvert(
        'http',
        (v) => AdminMetricsHTTP.fromJson(v as Map<String, dynamic>),
      ),
      users: $checkedConvert(
        'users',
        (v) => AdminMetricsUsers.fromJson(v as Map<String, dynamic>),
      ),
    );
    return val;
  },
  fieldKeyMap: const {'uptimeSeconds': 'uptime_seconds'},
);

Map<String, dynamic> _$AdminMetricsResponseToJson(
  AdminMetricsResponse instance,
) => <String, dynamic>{
  'uptime_seconds': instance.uptimeSeconds,
  'streams': instance.streams.toJson(),
  'http': instance.http.toJson(),
  'users': instance.users.toJson(),
};
