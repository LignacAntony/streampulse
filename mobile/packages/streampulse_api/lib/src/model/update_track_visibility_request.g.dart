// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_track_visibility_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdateTrackVisibilityRequest _$UpdateTrackVisibilityRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('UpdateTrackVisibilityRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['is_public']);
  final val = UpdateTrackVisibilityRequest(
    isPublic: $checkedConvert('is_public', (v) => v as bool),
  );
  return val;
}, fieldKeyMap: const {'isPublic': 'is_public'});

Map<String, dynamic> _$UpdateTrackVisibilityRequestToJson(
  UpdateTrackVisibilityRequest instance,
) => <String, dynamic>{'is_public': instance.isPublic};
