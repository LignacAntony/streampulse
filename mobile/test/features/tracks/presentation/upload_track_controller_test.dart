import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/tracks/domain/repositories/track_repository.dart';
import 'package:streampulse/features/tracks/presentation/providers/upload_track_controller.dart';

/// Faux repository : capture les paramètres, émet une progression simulée puis
/// renvoie une piste ou lève l'erreur fournie.
class _FakeTrackRepository implements TrackRepository {
  _FakeTrackRepository({this.error});

  final Object? error;
  int calls = 0;
  String? gotTitle;

  @override
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    void Function(double progress)? onProgress,
  }) async {
    calls++;
    gotTitle = title;
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    if (error != null) throw error!;
    return Track(id: 't1', title: title, artist: artist, durationS: durationS);
  }
}

void main() {
  group('UploadTrackController', () {
    test('succès : status success, progression à 1.0, piste exposée', () async {
      final repo = _FakeTrackRepository();
      final controller = UploadTrackController(repo);

      final ok = await controller.upload(
        filePath: '/tmp/song.mp3',
        filename: 'song.mp3',
        title: 'Song',
        artist: 'Artist',
      );

      expect(ok, isTrue);
      expect(controller.status, UploadStatus.success);
      expect(controller.progress, 1.0);
      expect(controller.uploaded?.id, 't1');
      expect(repo.calls, 1);
      expect(repo.gotTitle, 'Song');
    });

    test('conflit : status error et message métier remonté', () async {
      final repo = _FakeTrackRepository(
        error: const ConflictException('Une piste porte déjà ce titre'),
      );
      final controller = UploadTrackController(repo);

      final ok = await controller.upload(
        filePath: '/tmp/song.mp3',
        filename: 'song.mp3',
        title: 'Song',
      );

      expect(ok, isFalse);
      expect(controller.status, UploadStatus.error);
      expect(controller.error, 'Une piste porte déjà ce titre');
    });
  });
}
