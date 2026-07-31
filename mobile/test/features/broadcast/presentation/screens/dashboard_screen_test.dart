import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/network/sse_client.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stream.dart';
import 'package:streampulse/features/broadcast/domain/repositories/broadcast_repository.dart';
import 'package:streampulse/features/broadcast/presentation/screens/dashboard_screen.dart';
import 'package:streampulse/features/profile/domain/entities/user_profile.dart';
import 'package:streampulse/features/profile/domain/repositories/profile_repository.dart';
import 'package:streampulse/features/profile/presentation/providers/profile_controller.dart';

BroadcastStream _stream(
  String id, {
  String status = 'idle',
  String? title,
  DateTime? startedAt,
  String? sourceUrl,
}) =>
    BroadcastStream(
      id: id,
      title: title ?? 'Flux $id',
      status: status,
      isPublic: true,
      startedAt: startedAt,
      streamKey: 'cle-secrete-$id',
      streamSourceUrl:
          sourceUrl ?? 'http://localhost:8080/api/streams/ingest/cle-secrete-$id',
    );

class _FakeBroadcastRepository implements BroadcastRepository {
  _FakeBroadcastRepository({List<BroadcastStream>? streams, this.startError})
      : streams = streams ?? const [];

  List<BroadcastStream> streams;

  /// Si non nul, `startStream` échoue avec cette exception.
  final Object? startError;
  int listCalls = 0;

  @override
  Future<List<BroadcastStream>> listMyStreams() async {
    listCalls++;
    return streams;
  }

  @override
  Future<BroadcastStream> createStream({
    required String title,
    required bool isPublic,
    String? description,
    String? category,
  }) async =>
      BroadcastStream(
        id: 'new',
        title: title,
        status: 'idle',
        isPublic: isPublic,
      );

  @override
  Future<BroadcastStream> startStream(String id) async {
    if (startError != null) throw startError!;
    return _stream(id, status: 'live', startedAt: DateTime.now());
  }

  @override
  Future<BroadcastStream> stopStream(String id) async =>
      _stream(id, status: 'ended');
}

class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository({this.role = 'broadcaster', this.fails = false});

  final String role;
  final bool fails;

  @override
  Future<UserProfile> getMe() async {
    if (fails) throw Exception('non connecté');
    return UserProfile(
      id: 'u1',
      email: 'diffuseur@streampulse.dev',
      role: role,
      pseudo: 'diffuseur',
      bio: '',
      avatarUrl: null,
      theme: 'dark',
      notificationsEnabled: true,
      audioQuality: 'high',
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<UserProfile> update(UserProfile profile) async => profile;
}

/// Connecteur SSE inerte : les tests d'écran n'exercent pas le temps réel,
/// mais il évite que `DashboardScreen` construise un vrai `SseClient` (et
/// donc `SecureStorage`, qui passerait par un canal de plateforme).
class _InertSseConnector implements SseConnector {
  @override
  Stream<SseEvent> connect(String path) => const Stream.empty();
}

Widget _harness(
  BroadcastRepository repository, {
  String role = 'broadcaster',
  bool profileFails = false,
}) {
  return ToastificationWrapper(
    child: MultiProvider(
      providers: [
        ChangeNotifierProvider<ProfileController>(
          create: (_) => ProfileController(
            _FakeProfileRepository(role: role, fails: profileFails),
          ),
        ),
      ],
      child: MaterialApp(
        home: DashboardScreen(
          repository: repository,
          sse: _InertSseConnector(),
        ),
      ),
    ),
  );
}

/// Laisse passer le `postFrameCallback` du montage puis les futures des
/// chargements, sans `pumpAndSettle` : un flux en direct fait battre un
/// `Timer.periodic` chaque seconde, qui empêcherait l'arbre de se stabiliser.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  group('DashboardScreen — accès', () {
    testWidgets('un non-diffuseur est orienté vers la demande de rôle',
        (tester) async {
      await tester.pumpWidget(_harness(_FakeBroadcastRepository(), role: 'user'));
      await _settle(tester);

      expect(find.text('Diffusez vos propres flux'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard_become_broadcaster_button')),
        findsOneWidget,
      );
      // Rien à créer tant que le rôle n'est pas accordé.
      expect(find.byKey(const Key('dashboard_create_button')), findsNothing);
    });

    testWidgets('un visiteur non connecté est invité à se connecter',
        (tester) async {
      await tester.pumpWidget(
        _harness(_FakeBroadcastRepository(), profileFails: true),
      );
      await _settle(tester);

      expect(find.text('Connectez-vous'), findsOneWidget);
      expect(find.byKey(const Key('dashboard_login_button')), findsOneWidget);
    });

    testWidgets('un diffuseur sans flux est invité à en créer un',
        (tester) async {
      await tester.pumpWidget(_harness(_FakeBroadcastRepository()));
      await _settle(tester);

      expect(find.text('Aucun flux'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard_empty_create_button')),
        findsOneWidget,
      );
    });
  });

  group('DashboardScreen — liste', () {
    testWidgets('affiche le statut de chaque flux', (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a', title: 'Talk du soir', status: 'live',
              startedAt: DateTime.now().subtract(const Duration(minutes: 2))),
          _stream('b', title: 'Session jazz'),
          _stream('c', title: 'Archive', status: 'ended'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.text('Talk du soir'), findsOneWidget);
      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.text('PRÊT'), findsOneWidget);
      expect(find.text('TERMINÉ'), findsOneWidget);
    });

    testWidgets('le direct affiche un chronomètre, pas les autres flux',
        (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a', status: 'live',
              startedAt: DateTime.now().subtract(const Duration(minutes: 2))),
          _stream('b'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.byKey(const Key('dashboard_stream_timer_a')), findsOneWidget);
      expect(find.byKey(const Key('dashboard_stream_timer_b')), findsNothing);
    });

    testWidgets(
        'un seul live : le démarrage des autres flux est désactivé et expliqué',
        (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a', status: 'live', startedAt: DateTime.now()),
          _stream('b'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      final startB = tester.widget<FilledButton>(
        find.byKey(const Key('dashboard_start_button_b')),
      );
      expect(startB.onPressed, isNull);
      expect(find.text('Un autre flux est en direct'), findsOneWidget);
      // Le flux en direct garde son bouton d'arrêt actif.
      final stopA = tester.widget<FilledButton>(
        find.byKey(const Key('dashboard_stop_button_a')),
      );
      expect(stopA.onPressed, isNotNull);
    });
  });

  group('DashboardScreen — flux terminé', () {
    testWidgets('aucun bouton de démarrage, le backend le refuserait',
        (tester) async {
      // `start` n'accepte que idle -> live : proposer le bouton sur un flux
      // terminé ne peut produire qu'un 409.
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'ended')],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.byKey(const Key('dashboard_start_button_a')), findsNothing);
      expect(find.byKey(const Key('dashboard_stop_button_a')), findsNothing);
      expect(
        find.text('Diffusion terminée. Créez un nouveau flux pour rediffuser.'),
        findsOneWidget,
      );
      // Le motif « un autre flux est en direct » ne concerne que les flux
      // encore démarrables.
      expect(find.text('Un autre flux est en direct'), findsNothing);
    });

    testWidgets(
      'un 409 sans autre direct est expliqué par la bonne raison',
      (tester) async {
        final repository = _FakeBroadcastRepository(
          streams: [_stream('a')],
          startError: const ConflictException('stream is not idle'),
        );
        await tester.pumpWidget(_harness(repository));
        await _settle(tester);

        await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
        await _settle(tester);
        // Le toast vit dans un overlay animé : laisser l'animation d'entrée
        // se dérouler avant d'assert.
        await tester.pump(const Duration(milliseconds: 600));

        expect(find.text("Ce flux n'est plus démarrable"), findsOneWidget);
        expect(find.text('Un autre flux est déjà en direct'), findsNothing);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
  });

  group('DashboardScreen — clé de diffusion', () {
    testWidgets('l\'URL d\'ingest est masquée par défaut', (tester) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      final displayed = tester
          .widget<Text>(find.byKey(const Key('dashboard_ingest_url_a')))
          .data!;

      expect(displayed, contains('•'));
      expect(
        displayed,
        isNot(contains('cle-secrete-a')),
        reason: 'le secret ne doit pas être rendu sans action explicite',
      );
    });

    testWidgets('la révélation affiche l\'URL complète', (tester) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('dashboard_reveal_key_a')));
      await tester.pump();

      final revealed =
          tester.widget<Text>(find.byKey(const Key('dashboard_ingest_url_a')));
      expect(revealed.data!, contains('cle-secrete-a'));
      // Tronquer l'URL révélée rendrait le bouton « révéler » inutile : on ne
      // pourrait pas lire la clé qu'on vient de demander à voir.
      expect(revealed.maxLines, isNull);
      expect(revealed.overflow, isNot(TextOverflow.ellipsis));
      final displayed = revealed.data!;
      expect(displayed, contains('cle-secrete-a'));

      // La révélation se referme d'elle-même : pas de secret laissé à l'écran.
      await tester.pump(const Duration(seconds: 16));
      final masked = tester
          .widget<Text>(find.byKey(const Key('dashboard_ingest_url_a')))
          .data!;
      expect(masked, isNot(contains('cle-secrete-a')));
    });

    test('maskIngestUrl ne laisse que les 4 derniers caractères de la clé', () {
      const url = 'http://localhost:8080/api/streams/ingest/abcdefghijkl';
      final masked = maskIngestUrl(url);

      expect(masked, endsWith('ijkl'));
      expect(masked, isNot(contains('abcdefgh')));
      expect(masked, startsWith('http://localhost:8080/api/streams/ingest/'));
    });

    test('maskIngestUrl reste sûr sur une URL inattendue', () {
      // Clé plus courte que la fenêtre visible : tout est masqué.
      expect(maskIngestUrl('http://x/ingest/ab'), 'http://x/ingest/••••');
      // Aucune séparation exploitable : on ne rend rien du tout.
      expect(maskIngestUrl('sans-separateur'), '••••');
      expect(maskIngestUrl('http://x/ingest/'), '••••');
    });
  });

  group('DashboardScreen — latence de démarrage (STR-159)', () {
    testWidgets(
      'le passage EN DIRECT est rendu depuis la réponse de start, '
      'sans rechargement bloquant',
      (tester) async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        await tester.pumpWidget(_harness(repository));
        await _settle(tester);
        final listCallsAfterLoad = repository.listCalls;

        await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
        await _settle(tester);

        expect(find.text('EN DIRECT'), findsOneWidget);
        expect(
          repository.listCalls,
          listCallsAfterLoad,
          reason: 'le rendu du direct ne doit pas attendre un refetch de la '
              'liste : la réponse de start suffit',
        );

        // Le toast de succès arme un minuteur d'auto-fermeture : le purger
        // avant la fin du test (même pattern que `AdminStreamsScreen`).
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
  });
}
