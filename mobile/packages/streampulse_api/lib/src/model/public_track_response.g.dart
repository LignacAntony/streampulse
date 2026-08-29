// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'public_track_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PublicTrackResponse _$PublicTrackResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PublicTrackResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'title',
            'artist',
            'duration_s',
            'owner_name',
          ],
        );
        final val = PublicTrackResponse(
          id: $checkedConvert('id', (v) => v as String),
          title: $checkedConvert('title', (v) => v as String),
          artist: $checkedConvert('artist', (v) => v as String?),
          durationS: $checkedConvert('duration_s', (v) => (v as num?)?.toInt()),
          ownerName: $checkedConvert('owner_name', (v) => v as String),
        );
        return val;
      },
      fieldKeyMap: const {'durationS': 'duration_s', 'ownerName': 'owner_name'},
    );

Map<String, dynamic> _$PublicTrackResponseToJson(
  PublicTrackResponse instance,
) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'artist': instance.artist,
  'duration_s': instance.durationS,
  'owner_name': instance.ownerName,
};
