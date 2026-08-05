// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'add_playlist_track_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AddPlaylistTrackRequest _$AddPlaylistTrackRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('AddPlaylistTrackRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['track_id']);
  final val = AddPlaylistTrackRequest(
    trackId: $checkedConvert('track_id', (v) => v as String),
  );
  return val;
}, fieldKeyMap: const {'trackId': 'track_id'});

Map<String, dynamic> _$AddPlaylistTrackRequestToJson(
  AddPlaylistTrackRequest instance,
) => <String, dynamic>{'track_id': instance.trackId};
