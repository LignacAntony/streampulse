import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/network/sse_client.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stats.dart';
import 'package:streampulse/features/broadcast/domain/entities/broadcast_stream.dart';
import 'package:streampulse/features/broadcast/domain/repositories/broadcast_repository.dart';
import 'package:streampulse/features/broadcast/domain/services/broadcast_audio_publisher.dart';
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
  DateTime? createdAt,
}) => BroadcastStream(
  id: id,
  title: title ?? 'Flux $id',
  status: status,
  isPublic: true,
  createdAt: createdAt ?? DateTime.utc(2026, 1, 1),
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
  }) async => BroadcastStream(
    id: 'new',
    title: title,
    status: 'idle',
    isPublic: isPublic,
    createdAt: DateTime.utc(2026, 6, 1),
  );

  @override
  Future<BroadcastStream> startStream(String id) async {
    if (startError != null) throw startError!;
    return _stream(id, status: 'live', startedAt: DateTime.now());
  }

  @override
  Future<BroadcastStream> stopStream(String id) async {
    stoppedIds.add(id);
    return _stream(id, status: 'ended');
  }

  @override
  Future<void> deleteStream(String id) async {
    deletedIds.add(id);
  }

  @override
  Future<BroadcastStats> streamStats(String id) async =>
      BroadcastStats(streamId: id, listeners: listeners, peak: peak);

  final List<String> deletedIds = [];
  final List<String> stoppedIds = [];
  int listeners = 4;
  int peak = 9;
}

/// Repository dont `streamStats` ne répond jamais : reproduit la fenêtre entre
/// le passage en direct et le premier relevé, ainsi que le retour
/// d'arrière-plan où l'audience est repartie à null.
class _DeferredStatsRepository extends _FakeBroadcastRepository {
  _DeferredStatsRepository({super.streams});

  @override
  Future<BroadcastStats> streamStats(String id) =>
      Completer<BroadcastStats>().future;
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

class _FakeAudioPublisher implements BroadcastAudioPublisher {
  _FakeAudioPublisher({this.isSupported = true});

  final StreamController<BroadcastAudioState> _states =
      StreamController<BroadcastAudioState>.broadcast();

  @override
  final bool isSupported;

  @override
  BroadcastAudioState state = BroadcastAudioState.idle;

  @override
  Stream<BroadcastAudioState> get states => _states.stream;

  @override
  Future<void> prepare() async {}

  @override
  Future<void> start(Uri sourceUrl) async {
    _emit(BroadcastAudioState.live);
  }

  @override
  Future<void> stop() async {
    _emit(BroadcastAudioState.idle);
  }

  /// Reconnexion en cours, puis abandon : les deux états que le diffuseur
  /// audio émet sans que l'utilisateur n'ait rien demandé.
  void reconnect() => _emit(BroadcastAudioState.reconnecting);
  void giveUp() => _emit(BroadcastAudioState.failed);

  void _emit(BroadcastAudioState next) {
    state = next;
    _states.add(next);
  }

  @override
  Future<void> dispose() async {
    if (!_states.isClosed) await _states.close();
  }
}

Widget _harness(
  BroadcastRepository repository, {
  String role = 'broadcaster',
  bool profileFails = false,
  BroadcastAudioPublisher? audioPublisher,
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
          audioPublisher: audioPublisher ?? _FakeAudioPublisher(),
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
    testWidgets('un non-diffuseur est orienté vers la demande de rôle', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_FakeBroadcastRepository(), role: 'user'),
      );
      await _settle(tester);

      expect(find.text('Diffusez vos propres flux'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard_become_broadcaster_button')),
        findsOneWidget,
      );
      // Rien à créer tant que le rôle n'est pas accordé.
      expect(find.byKey(const Key('dashboard_create_button')), findsNothing);
    });

    testWidgets('un visiteur non connecté est invité à se connecter', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_FakeBroadcastRepository(), profileFails: true),
      );
      await _settle(tester);

      expect(find.text('Connectez-vous'), findsOneWidget);
      expect(find.byKey(const Key('dashboard_login_button')), findsOneWidget);
    });

    testWidgets('un diffuseur sans flux est invité à en créer un', (
      tester,
    ) async {
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
          _stream(
            'a',
            title: 'Talk du soir',
            status: 'live',
            startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
          _stream('b', title: 'Session jazz'),
          _stream('c', title: 'Archive', status: 'ended'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.text('Talk du soir'), findsOneWidget);
      expect(find.text('EN DIRECT'), findsOneWidget);
      expect(find.text('PRÊT'), findsOneWidget);

      // La 3e carte est sous la ligne de flottaison : la ListView ne la
      // construit qu'une fois amenée à l'écran.
      await tester.scrollUntilVisible(
        find.byKey(const Key('dashboard_stream_card_c')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('TERMINÉ'), findsOneWidget);
    });

    testWidgets('le direct affiche un chronomètre, pas les autres flux', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream(
            'a',
            status: 'live',
            startedAt: DateTime.now().subtract(const Duration(minutes: 2)),
          ),
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
      },
    );
  });

  group('DashboardScreen — audience (STR-154)', () {
    testWidgets('le direct affiche les auditeurs estimés et le pic', (
      tester,
    ) async {
      final repository =
          _FakeBroadcastRepository(
              streams: [
                _stream('a', status: 'live', startedAt: DateTime.now()),
              ],
            )
            ..listeners = 4
            ..peak = 9;
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.byKey(const Key('dashboard_listeners_a')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard_listeners_a')))
            .data,
        '4',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('dashboard_peak_a'))).data,
        'Pic : 9',
      );
      // Le libellé reste prudent : le compte est une estimation, pas une
      // mesure de connexions (HLS n'en a pas).
      expect(find.text('auditeurs estimés'), findsOneWidget);
    });

    testWidgets('un seul auditeur : libellé au singulier', (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live', startedAt: DateTime.now())],
      )..listeners = 1;
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.text('auditeur estimé'), findsOneWidget);
    });

    testWidgets('la ligne est présente dès le direct, avant toute mesure', (
      tester,
    ) async {
      // Sans ça, la ligne « apparaît » au premier relevé et pousse le contenu
      // vers le bas ; et elle disparaît au passage en arrière-plan, quand
      // `_cancelStats()` remet l'audience à null.
      final repository = _DeferredStatsRepository(
        streams: [_stream('a', status: 'live', startedAt: DateTime.now())],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(find.byKey(const Key('dashboard_listeners_a')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('dashboard_listeners_a')))
            .data,
        '—',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('dashboard_peak_a'))).data,
        'Pic : —',
      );
    });

    testWidgets('le pic est libellé explicitement', (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live', startedAt: DateTime.now())],
      )..peak = 9;
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      expect(
        tester.widget<Text>(find.byKey(const Key('dashboard_peak_a'))).data,
        'Pic : 9',
      );
    });

    testWidgets('une info-bulle explique que le chiffre est une estimation', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(
        streams: [_stream('a', status: 'live', startedAt: DateTime.now())],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      // Cibler l'info-bulle QUI ENTOURE la ligne d'audience : le menu ⋮ de la
      // carte en porte une autre.
      final tooltip = tester.widget<Tooltip>(
        find
            .ancestor(
              of: find.byKey(const Key('dashboard_listeners_a')),
              matching: find.byType(Tooltip),
            )
            .first,
      );
      expect(tooltip.message, contains('même connexion comptent pour un'));
    });

    testWidgets(
      'aucune audience affichée sur un flux qui n\'est pas en direct',
      (tester) async {
        final repository = _FakeBroadcastRepository(
          streams: [
            _stream('a'),
            _stream('b', status: 'ended'),
          ],
        );
        await tester.pumpWidget(_harness(repository));
        await _settle(tester);

        expect(find.byKey(const Key('dashboard_listeners_a')), findsNothing);
        expect(find.byKey(const Key('dashboard_listeners_b')), findsNothing);
      },
    );
  });

  group('DashboardScreen — flux terminé', () {
    testWidgets('aucun bouton de démarrage, le backend le refuserait', (
      tester,
    ) async {
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

    testWidgets('un 409 sans autre direct est expliqué par la bonne raison', (
      tester,
    ) async {
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
    });
  });

  group('DashboardScreen — retours de revue', () {
    testWidgets('les badges PRÊT et TERMINÉ ne partagent pas leur couleur', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a'),
          _stream('b', status: 'ended'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      Color badgeColor(String label) {
        final container = tester.widget<Container>(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        );
        return (container.decoration! as BoxDecoration).color!;
      }

      expect(
        badgeColor('PRÊT'),
        isNot(badgeColor('TERMINÉ')),
        reason: 'un flux actionnable doit se distinguer au coup d\'œil',
      );
    });

    testWidgets('aucune URL d\'ingest sur un flux terminé', (tester) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a', status: 'ended'),
          _stream('b'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      // La clé y est inutilisable : l'afficher n'est que du bruit, et une
      // exposition inutile d'un secret.
      expect(find.byKey(const Key('dashboard_ingest_url_a')), findsNothing);
      expect(find.byKey(const Key('dashboard_ingest_url_b')), findsOneWidget);
    });

    testWidgets('supprimer un flux le retire après confirmation', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream('a', title: 'À jeter'),
          _stream('b'),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('dashboard_stream_menu_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard_delete_item_a')));
      await tester.pumpAndSettle();

      expect(find.text('Supprimer « À jeter » ?'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('dashboard_confirm_delete_button')),
      );
      await _settle(tester);

      expect(repository.deletedIds, ['a']);
      expect(find.byKey(const Key('dashboard_stream_card_a')), findsNothing);
      expect(find.byKey(const Key('dashboard_stream_card_b')), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('supprimer un direct annonce l\'arrêt de la diffusion', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(
        streams: [
          _stream(
            'a',
            title: 'En cours',
            status: 'live',
            startedAt: DateTime.now(),
          ),
        ],
      );
      await tester.pumpWidget(_harness(repository));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('dashboard_stream_menu_a')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dashboard_delete_item_a')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('la diffusion sera arrêtée'),
        findsOneWidget,
        reason: 'le backend termine le direct au passage : il faut le dire',
      );

      await tester.tap(find.text('Annuler'));
      await _settle(tester);
      expect(repository.deletedIds, isEmpty);
    });
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

      final revealed = tester.widget<Text>(
        find.byKey(const Key('dashboard_ingest_url_a')),
      );
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
    testWidgets('le passage EN DIRECT est rendu depuis la réponse de start, '
        'sans rechargement bloquant', (tester) async {
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
        reason:
            'le rendu du direct ne doit pas attendre un refetch de la '
            'liste : la réponse de start suffit',
      );

      // Le toast de succès arme un minuteur d'auto-fermeture : le purger
      // avant la fin du test (même pattern que `AdminStreamsScreen`).
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });
  });

  group('DashboardScreen — microphone (STR-156)', () {
    testWidgets('affiche que le microphone de cet appareil est diffusé', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      await tester.pumpWidget(_harness(repository, audioPublisher: audio));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
      await _settle(tester);

      expect(find.text('Microphone diffusé'), findsOneWidget);
      expect(
        find.byKey(const Key('dashboard_microphone_status_a')),
        findsOneWidget,
      );

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets(
      'le passage en arrière-plan arrête le live et libère le micro',
      (tester) async {
        final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
        final audio = _FakeAudioPublisher();
        await tester.pumpWidget(_harness(repository, audioPublisher: audio));
        await _settle(tester);
        await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
        await _settle(tester);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await _settle(tester);

        expect(repository.stoppedIds, ['a']);
        expect(audio.state, BroadcastAudioState.idle);
        expect(find.text('TERMINÉ'), findsOneWidget);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );

    testWidgets('annonce que la reprise est bornée pendant une reconnexion', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      await tester.pumpWidget(_harness(repository, audioPublisher: audio));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
      await _settle(tester);

      audio.reconnect();
      await _settle(tester);

      expect(find.text('Reconnexion audio…'), findsOneWidget);
      expect(
        find.text('Le direct s\'arrêtera si la reconnexion échoue.'),
        findsOneWidget,
      );

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    // La panne définitive du micro arrête le direct sans action de
    // l'utilisateur : la carte doit le dire, sinon le flux passerait de « en
    // direct » à « terminé » sans explication.
    testWidgets('un abandon du micro termine le direct et le signale', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      final audio = _FakeAudioPublisher();
      await tester.pumpWidget(_harness(repository, audioPublisher: audio));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('dashboard_start_button_a')));
      await _settle(tester);
      expect(find.text('EN DIRECT'), findsOneWidget);

      audio.giveUp();
      await _settle(tester);
      // Laisse l'animation d'entrée du toast se jouer : `pump()` sans durée
      // ne fait pas avancer l'overlay de toastification.
      await tester.pump(const Duration(milliseconds: 400));

      expect(repository.stoppedIds, ['a']);
      expect(find.text('TERMINÉ'), findsOneWidget);
      expect(
        find.text('Diffusion arrêtée : le microphone n\'est plus disponible'),
        findsOneWidget,
      );

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    // Sur le web, `prepare()` échouerait après coup : un bouton pleinement
    // actif qui ne fait qu'afficher un toast fugace est une fausse promesse.
    testWidgets('neutralise le démarrage sur une plateforme sans capture', (
      tester,
    ) async {
      final repository = _FakeBroadcastRepository(streams: [_stream('a')]);
      await tester.pumpWidget(
        _harness(
          repository,
          audioPublisher: _FakeAudioPublisher(isSupported: false),
        ),
      );
      await _settle(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('dashboard_start_button_a')),
      );
      expect(button.onPressed, isNull);
      expect(
        find.byKey(const Key('dashboard_audio_unsupported_a')),
        findsOneWidget,
      );
      expect(find.text('EN DIRECT'), findsNothing);
    });
  });
}
