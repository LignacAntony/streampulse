// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'playlist_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlaylistResponse _$PlaylistResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      'PlaylistResponse',
      json,
      ($checkedConvert) {
        $checkKeys(
          json,
          requiredKeys: const [
            'id',
            'name',
            'description',
            'is_public',
            'track_count',
            'is_favorite',
            'created_at',
            'updated_at',
          ],
        );
        final val = PlaylistResponse(
          id: $checkedConvert('id', (v) => v as String),
          name: $checkedConvert('name', (v) => v as String),
          description: $checkedConvert('description', (v) => v as String?),
          isPublic: $checkedConvert('is_public', (v) => v as bool),
          trackCount: $checkedConvert('track_count', (v) => (v as num).toInt()),
          isFavorite: $checkedConvert('is_favorite', (v) => v as bool),
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
        'isPublic': 'is_public',
        'trackCount': 'track_count',
        'isFavorite': 'is_favorite',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
      },
    );

Map<String, dynamic> _$PlaylistResponseToJson(PlaylistResponse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'is_public': instance.isPublic,
      'track_count': instance.trackCount,
      'is_favorite': instance.isFavorite,
      'created_at': instance.createdAt.toIso8601String(),
      'updated_at': instance.updatedAt.toIso8601String(),
    };
