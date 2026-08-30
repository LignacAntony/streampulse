// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_metrics_streams.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminMetricsStreams _$AdminMetricsStreamsFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'AdminMetricsStreams',
      json,
      ($checkedConvert) {
        $checkKeys(json, requiredKeys: const ['live', 'listeners_estimated']);
        final val = AdminMetricsStreams(
          live: $checkedConvert('live', (v) => (v as num).toInt()),
          listenersEstimated: $checkedConvert(
            'listeners_estimated',
            (v) => (v as num).toInt(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {'listenersEstimated': 'listeners_estimated'},
    );

Map<String, dynamic> _$AdminMetricsStreamsToJson(
  AdminMetricsStreams instance,
) => <String, dynamic>{
  'live': instance.live,
  'listeners_estimated': instance.listenersEstimated,
};
