// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'create_playlist_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CreatePlaylistRequest _$CreatePlaylistRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('CreatePlaylistRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['name']);
  final val = CreatePlaylistRequest(
    name: $checkedConvert('name', (v) => v as String),
    description: $checkedConvert('description', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$CreatePlaylistRequestToJson(
  CreatePlaylistRequest instance,
) {
  final val = <String, dynamic>{'name': instance.name};

  void writeNotNull(String key, dynamic value) {
    if (value != null) {
      val[key] = value;
    }
  }

  writeNotNull('description', instance.description);
  return val;
}
