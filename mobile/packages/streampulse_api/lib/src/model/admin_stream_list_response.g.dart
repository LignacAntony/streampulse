// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'admin_stream_list_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AdminStreamListResponse _$AdminStreamListResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('AdminStreamListResponse', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['streams', 'total']);
  final val = AdminStreamListResponse(
    streams: $checkedConvert(
      'streams',
      (v) => (v as List<dynamic>)
          .map((e) => AdminStreamResponse.fromJson(e as Map<String, dynamic>))
          .toList(),
    ),
    total: $checkedConvert('total', (v) => (v as num).toInt()),
  );
  return val;
});

Map<String, dynamic> _$AdminStreamListResponseToJson(
  AdminStreamListResponse instance,
) => <String, dynamic>{
  'streams': instance.streams.map((e) => e.toJson()).toList(),
  'total': instance.total,
};
