import 'package:streampulse_api/streampulse_api.dart';

import '../../../playlists/domain/entities/track.dart';
import '../../../playlists/data/mappers/playlist_dto_mappers.dart';
import '../../domain/entities/public_track.dart';
import '../../domain/repositories/track_repository.dart';
import '../datasources/track_remote_data_source.dart';

extension _PublicTrackMapper on PublicTrackResponse {
  PublicTrack toEntity() => PublicTrack(
        id: id,
        title: title,
        artist: artist,
        durationS: durationS,
        ownerName: ownerName,
      );
}

class TrackRepositoryImpl implements TrackRepository {
  TrackRepositoryImpl(this._remote);

  final TrackRemoteDataSource _remote;

  @override
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
    void Function(double progress)? onProgress,
  }) async {
    final dto = await _remote.upload(
      filePath: filePath,
      filename: filename,
      title: title,
      artist: artist,
      durationS: durationS,
      isPublic: isPublic,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              if (total > 0) onProgress(sent / total);
            },
    );
    return dto.toEntity();
  }

  @override
  Future<List<PublicTrack>> listPublicTracks({int? limit}) async {
    final dtos = await _remote.listPublicTracks(limit: limit);
    return dtos.map((d) => d.toEntity()).toList();
  }

  @override
  Future<void> deleteTrack(String id) => _remote.deleteTrack(id);

  @override
  Future<void> updateVisibility(String id, {required bool isPublic}) =>
      _remote.updateVisibility(id, isPublic: isPublic);
}
