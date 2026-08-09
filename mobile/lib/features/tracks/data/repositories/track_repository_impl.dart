import '../../../playlists/domain/entities/track.dart';
import '../../../playlists/data/mappers/playlist_dto_mappers.dart';
import '../../domain/repositories/track_repository.dart';
import '../datasources/track_remote_data_source.dart';

/// Implémentation de [TrackRepository] : délègue au data source et mappe le DTO
/// généré vers l'entité domaine (réutilise `TrackResponseMapper`).
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
    void Function(double progress)? onProgress,
  }) async {
    final dto = await _remote.upload(
      filePath: filePath,
      filename: filename,
      title: title,
      artist: artist,
      durationS: durationS,
      onSendProgress: onProgress == null
          ? null
          : (sent, total) {
              // total <= 0 tant que la taille n'est pas connue : on n'émet la
              // progression que lorsqu'elle est calculable.
              if (total > 0) onProgress(sent / total);
            },
    );
    return dto.toEntity();
  }
}
