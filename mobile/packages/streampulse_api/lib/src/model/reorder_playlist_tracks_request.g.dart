// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reorder_playlist_tracks_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ReorderPlaylistTracksRequest _$ReorderPlaylistTracksRequestFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('ReorderPlaylistTracksRequest', json, ($checkedConvert) {
  $checkKeys(json, requiredKeys: const ['track_ids']);
  final val = ReorderPlaylistTracksRequest(
    trackIds: $checkedConvert(
      'track_ids',
      (v) => (v as List<dynamic>).map((e) => e as String).toList(),
    ),
  );
  return val;
}, fieldKeyMap: const {'trackIds': 'track_ids'});

Map<String, dynamic> _$ReorderPlaylistTracksRequestToJson(
  ReorderPlaylistTracksRequest instance,
) => <String, dynamic>{'track_ids': instance.trackIds};
