import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/features/chat/data/datasources/chat_websocket_source.dart';
import 'package:streampulse/features/chat/presentation/providers/chat_controller.dart';
import 'package:streampulse/features/profile/domain/entities/user_profile.dart';
import 'package:streampulse/features/profile/domain/repositories/profile_repository.dart';
import 'package:streampulse/features/profile/presentation/providers/profile_controller.dart';
import 'package:streampulse/features/streams/domain/entities/live_stream.dart';
import 'package:streampulse/features/streams/domain/repositories/stream_repository.dart';
import 'package:streampulse/features/streams/presentation/providers/audio_player_controller.dart';
import 'package:streampulse/features/streams/presentation/providers/favorites_controller.dart';
import 'package:streampulse/features/streams/presentation/screens/stream_player_screen.dart';

class _FakePlaybackController extends PlaybackController {
  _FakePlaybackController([this._status = PlaybackStatus.idle]);

  final PlaybackStatus _status;

  @override
  PlaybackStatus get status => _status;
  @override
  bool get isPlaying => _status == PlaybackStatus.playing;
  @override
  bool get isBusy =>
      _status == PlaybackStatus.loading || _status == PlaybackStatus.buffering;
  @override
  bool get isReconnecting => _status == PlaybackStatus.reconnecting;
  @override
  bool get hasError => _status == PlaybackStatus.error;
  @override
  bool get isEnded => _status == PlaybackStatus.ended;
  @override
  NowPlaying? get nowPlaying => null;
  @override
  Future<void> load(NowPlaying now) async {}
  @override
  Future<void> togglePlayPause() async {}
  @override
  Future<void> stop() async {}
}

LiveStream _realStream(String id) => LiveStream(
      id: id,
      title: 'Vrai Titre',
      startedAt: DateTime.utc(2026, 1, 1),
      status: 'live',
    );

class _FakeStreamRepository implements StreamRepository {
  _FakeStreamRepository({List<LiveStream> favorites = const []})
      : _favorites = favorites;

  List<LiveStream> _favorites;
  int listFavoritesCalls = 0;
  final List<String> added = [];
  final List<String> removed = [];

  @override
  Future<List<LiveStream>> listFavorites() async {
    listFavoritesCalls++;
    return _favorites;
  }

  @override
  Future<void> addFavorite(String streamId) async {
    added.add(streamId);
    _favorites = [_realStream(streamId)];
  }

  @override
  Future<void> removeFavorite(String streamId) async {
    removed.add(streamId);
    _favorites = const [];
  }

  @override
  Future<List<LiveStream>> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async =>
      const [];

  @override
  Future<bool> isManifestUnavailable(String streamId) async => false;
}

class _FakeChatWebSocketSource implements ChatWebSocketSource {
  @override
  Stream<Map<String, dynamic>> connect(String streamId) =>
      const Stream.empty();
  @override
  void send(Map<String, dynamic> message) {}
  @override
  void disconnect() {}
}

final _testProfile = UserProfile(
  id: 'test-user-id',
  email: 'test@test.com',
  role: 'user',
  pseudo: 'testuser',
  bio: '',
  avatarUrl: null,
  theme: 'dark',
  notificationsEnabled: true,
  audioQuality: 'high',
  createdAt: DateTime.utc(2026, 1, 1),
);

class _FakeProfileRepository implements ProfileRepository {
  @override
  Future<UserProfile> getMe() async => _testProfile;

  @override
  Future<UserProfile> update(UserProfile profile) async => profile;
}

Widget _harness({
  required String streamId,
  LiveStream? stream,
  required _FakeStreamRepository repo,
  required FavoritesController controller,
  PlaybackStatus playbackStatus = PlaybackStatus.idle,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<FavoritesController>.value(value: controller),
      Provider<ChatWebSocketSource>(
        create: (_) => _FakeChatWebSocketSource(),
      ),
      ChangeNotifierProvider<ChatController>(
        create: (ctx) => ChatController(ctx.read<ChatWebSocketSource>()),
      ),
      ChangeNotifierProvider<ProfileController>(
        create: (_) => ProfileController(_FakeProfileRepository())..load(),
      ),
    ],
    child: ToastificationWrapper(
      child: MaterialApp(
        home: StreamPlayerScreen(
          streamId: streamId,
          stream: stream,
          controller: _FakePlaybackController(playbackStatus),
        ),
      ),
    ),
  );
}

void main() {
  group('StreamPlayerScreen — réconciliation deep-link', () {
    testWidgets(
        'ajout en arrivée deep-link (sans métadonnées) : recharge la liste '
        'et remplace le placeholder par les vraies métadonnées', (tester) async {
      final repo = _FakeStreamRepository();
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(streamId: 's1', repo: repo, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(repo.added, ['s1']);
      expect(repo.listFavoritesCalls, 2);
      expect(controller.favorites.single.title, 'Vrai Titre');
      expect(controller.favorites.single.status, 'live');
    });

    testWidgets(
        'métadonnées déjà connues (navigation normale) : pas de rechargement '
        'superflu', (tester) async {
      final repo = _FakeStreamRepository();
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(
          streamId: 's1',
          stream: _realStream('s1'),
          repo: repo,
          controller: controller,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pumpAndSettle();

      expect(repo.added, ['s1']);
      expect(repo.listFavoritesCalls, 1);
    });

    testWidgets('retrait : pas de rechargement de réconciliation',
        (tester) async {
      final repo = _FakeStreamRepository(favorites: [_realStream('s1')]);
      final controller = FavoritesController(repo);
      await tester.pumpWidget(
        _harness(streamId: 's1', repo: repo, controller: controller),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();

      expect(repo.removed, ['s1']);
      expect(repo.listFavoritesCalls, 1);
    });
  });

  group('StreamPlayerScreen — états de lecture (STR-118)', () {
    testWidgets('erreur : bouton replay affiché', (tester) async {
      final repo = _FakeStreamRepository();
      await tester.pumpWidget(_harness(
        streamId: 's1',
        repo: repo,
        controller: FavoritesController(repo),
        playbackStatus: PlaybackStatus.error,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.replay), findsOneWidget);
    });

    testWidgets('flux terminé : bouton replay affiché', (tester) async {
      final repo = _FakeStreamRepository();
      await tester.pumpWidget(_harness(
        streamId: 's1',
        repo: repo,
        controller: FavoritesController(repo),
        playbackStatus: PlaybackStatus.ended,
      ));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.replay), findsOneWidget);
    });
  });
}
