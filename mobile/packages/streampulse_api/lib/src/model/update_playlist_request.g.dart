// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update_playlist_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

UpdatePlaylistRequest _$UpdatePlaylistRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('UpdatePlaylistRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['name']);
  final val = UpdatePlaylistRequest(
    name: $checkedConvert('name', (v) => v as String),
    description: $checkedConvert('description', (v) => v as String?),
  );
  return val;
});

Map<String, dynamic> _$UpdatePlaylistRequestToJson(
  UpdatePlaylistRequest instance,
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
