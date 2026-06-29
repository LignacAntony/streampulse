// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'broadcaster_request_admin.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

BroadcasterRequestAdmin _$BroadcasterRequestAdminFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  'BroadcasterRequestAdmin',
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
        'user_id',
        'email',
        'username',
      ],
    );
    final val = BroadcasterRequestAdmin(
      id: $checkedConvert('id', (v) => v as String),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$BroadcasterRequestAdminStatusEnumEnumMap, v),
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
      userId: $checkedConvert('user_id', (v) => v as String),
      email: $checkedConvert('email', (v) => v as String),
      username: $checkedConvert('username', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'reviewNote': 'review_note',
    'reviewedBy': 'reviewed_by',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
    'userId': 'user_id',
  },
);

Map<String, dynamic> _$BroadcasterRequestAdminToJson(
  BroadcasterRequestAdmin instance,
) => <String, dynamic>{
  'id': instance.id,
  'status': _$BroadcasterRequestAdminStatusEnumEnumMap[instance.status]!,
  'message': instance.message,
  'review_note': instance.reviewNote,
  'reviewed_by': instance.reviewedBy,
  'created_at': instance.createdAt.toIso8601String(),
  'updated_at': instance.updatedAt.toIso8601String(),
  'user_id': instance.userId,
  'email': instance.email,
  'username': instance.username,
};

const _$BroadcasterRequestAdminStatusEnumEnumMap = {
  BroadcasterRequestAdminStatusEnum.pending: 'pending',
  BroadcasterRequestAdminStatusEnum.approved: 'approved',
  BroadcasterRequestAdminStatusEnum.rejected: 'rejected',
};
