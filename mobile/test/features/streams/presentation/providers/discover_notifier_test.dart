import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/entities/manifest_status.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/discover_notifier.dart';
import 'package:streampulse/features/playlists/domain/entities/track.dart';
import 'package:streampulse/features/tracks/domain/entities/public_track.dart';
import 'package:streampulse/features/tracks/domain/repositories/track_repository.dart';

class _CountingStreamRepo implements StreamRepository {
  int liveCalls = 0;

  @override
  Future<List<LiveStream>> listLiveStreams({int limit = 20, int offset = 0}) async {
    liveCalls++;
    return const [];
  }

  @override
  Future<List<LiveStream>> listFavorites() async => const [];
  @override
  Future<void> addFavorite(String streamId) async {}
  @override
  Future<void> removeFavorite(String streamId) async {}
  @override
  Future<ManifestStatus> manifestStatus(String streamId) async =>
      ManifestStatus.available;
}

class _StubTrackRepo implements TrackRepository {
  @override
  Future<List<PublicTrack>> listPublicTracks({int? limit}) async => const [];
  @override
  Future<Track> upload({
    required String filePath,
    required String filename,
    required String title,
    String? artist,
    int? durationS,
    bool isPublic = false,
    void Function(double progress)? onProgress,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> deleteTrack(String id) => throw UnimplementedError();
  @override
  Future<void> updateVisibility(String id, {required bool isPublic}) =>
      throw UnimplementedError();
}

void main() {
  test(
      'pas de double fetch : load() puis startPolling() ne relance pas '
      'listLiveStreams (STR-250)', () async {
    final repo = _CountingStreamRepo();
    final notifier = DiscoverNotifier(repo, _StubTrackRepo());

    await notifier.load();
    expect(repo.liveCalls, 1);

    // Les flux viennent d'être chargés → le démarrage du polling ne doit pas
    // refaire un fetch immédiat (il attendra le prochain tick).
    notifier.startPolling();
    await Future<void>.delayed(Duration.zero);
    expect(repo.liveCalls, 1);

    notifier.stopPolling();
  });

  test('startPolling sans load récent fait bien un fetch immédiat', () async {
    final repo = _CountingStreamRepo();
    final notifier = DiscoverNotifier(repo, _StubTrackRepo());

    // Aucun load préalable → liste périmée → refresh immédiat attendu.
    notifier.startPolling();
    await Future<void>.delayed(Duration.zero);
    expect(repo.liveCalls, 1);

    notifier.stopPolling();
  });
}
