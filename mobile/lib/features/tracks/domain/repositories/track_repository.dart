import '../../../playlists/domain/entities/track.dart';
import '../entities/public_track.dart';

abstract class TrackRepository {
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
    void Function(double progress)? onProgress,
  });

  Future<List<PublicTrack>> listPublicTracks({int? limit});

  Future<void> deleteTrack(String id);

  Future<void> updateVisibility(String id, {required bool isPublic});
}
