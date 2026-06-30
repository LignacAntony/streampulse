// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcaster_request_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BroadcasterRequestResponse _$BroadcasterRequestResponseFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'BroadcasterRequestResponse',
  json,
  ($checkedConvert) {
    $checkKeys(
      json,
      requiredKeys: const [
        'id',
        'status',
        'message',
        'review_note',
        'reviewed_by',
        'created_at',
        'updated_at',
      ],
    );
    final val = BroadcasterRequestResponse(
      id: $checkedConvert('id', (v) => v as String),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$BroadcasterRequestResponseStatusEnumEnumMap, v),
      ),
      message: $checkedConvert('message', (v) => v as String),
      reviewNote: $checkedConvert('review_note', (v) => v as String),
      reviewedBy: $checkedConvert('reviewed_by', (v) => v as String?),
      createdAt: $checkedConvert(
        'created_at',
        (v) => DateTime.parse(v as String),
      ),
      updatedAt: $checkedConvert(
        'updated_at',
        (v) => DateTime.parse(v as String),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'reviewNote': 'review_note',
    'reviewedBy': 'reviewed_by',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$BroadcasterRequestResponseToJson(
  BroadcasterRequestResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'status': _$BroadcasterRequestResponseStatusEnumEnumMap[instance.status]!,
  'message': instance.message,
  'review_note': instance.reviewNote,
  'reviewed_by': instance.reviewedBy,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
};

const _$BroadcasterRequestResponseStatusEnumEnumMap = {
  BroadcasterRequestResponseStatusEnum.pending: 'pending',
  BroadcasterRequestResponseStatusEnum.approved: 'approved',
  BroadcasterRequestResponseStatusEnum.rejected: 'rejected',
};
