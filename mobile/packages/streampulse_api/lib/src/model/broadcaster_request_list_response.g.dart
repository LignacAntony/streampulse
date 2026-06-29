// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcaster_request_list_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BroadcasterRequestListResponse _$BroadcasterRequestListResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('BroadcasterRequestListResponse', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['requests']);
  final val = BroadcasterRequestListResponse(
    requests: $checkedConvert(
      'requests',
      (v) => (v as List<dynamic>)
          .map(
            (e) => BroadcasterRequestAdmin.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    ),
  );
  return val;
});

Map<String, dynamic> _$BroadcasterRequestListResponseToJson(
  BroadcasterRequestListResponse instance,
) => <String, dynamic>{
  'requests': instance.requests.map((e) => e.toJson()).toList(),
};
