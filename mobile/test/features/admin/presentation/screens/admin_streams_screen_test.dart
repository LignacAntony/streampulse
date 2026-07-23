import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/domain/entities/admin_stream.dart';
import 'package:streampulse/features/admin/domain/repositories/admin_streams_repository.dart';
import 'package:streampulse/features/admin/presentation/screens/admin_streams_screen.dart';

class _FakeAdminStreamsRepository implements AdminStreamsRepository {
  _FakeAdminStreamsRepository({
    List<AdminStream>? all,
    this.mutationError,
    this.nextListError,
  }) : all = all ?? _defaultStreams();

  final List<AdminStream> all;
  final Object? mutationError;

  /// Si non nul, le PROCHAIN appel à `listLiveStreams` échoue avec cette
  /// exception puis se réinitialise à `null` (usage unique). Permet de faire
  /// échouer spécifiquement le chargement initial (liste vide, vue plein
  /// écran) OU un `loadMore`/pull-to-refresh ultérieur (liste déjà peuplée,
  /// toast attendu) selon le moment où le champ est renseigné.
  Object? nextListError;

  int stopCalls = 0;
  int listCalls = 0;

  @override
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async {
    listCalls++;
    if (nextListError != null) {
      final error = nextListError!;
      nextListError = null;
      throw error;
    }
    final page = all.skip(offset).take(limit).toList();
    return (streams: page, total: all.length);
  }

  @override
  Future<void> stopStream(String id) async {
    stopCalls++;
    if (mutationError != null) throw mutationError!;
  }
}

List<AdminStream> _defaultStreams() => [
      AdminStream(
        id: '1',
        title: 'Chill beats',
        isPublic: true,
        startedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        userId: 'u1',
        username: 'alice',
      ),
      AdminStream(
        id: '2',
        title: 'Deep focus',
        isPublic: false,
        startedAt: DateTime.now().subtract(const Duration(hours: 3)),
        userId: 'u2',
        username: 'bob',
      ),
      const AdminStream(
        id: '3',
        title: 'Late night jazz',
        isPublic: true,
        startedAt: null,
        userId: 'u3',
        username: 'carol',
      ),
    ];

Widget _buildHarness(AdminStreamsRepository repository) {
  return ToastificationWrapper(
    child: MaterialApp(home: AdminStreamsScreen(repository: repository)),
  );
}

void main() {
  group('AdminStreamsScreen', () {
    testWidgets('affiche les tuiles de flux après chargement', (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAdminStreamsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('Supervision des flux'), findsOneWidget);
      expect(find.text('Chill beats'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('Deep focus'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('Late night jazz'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
    });

    testWidgets('badge Public/Privé reflète la visibilité du flux', (
      tester,
    ) async {
      await tester.pumpWidget(_buildHarness(_FakeAdminStreamsRepository()));
      await tester.pumpAndSettle();

      // Flux 1 et 3 publics, flux 2 privé (cf. `_defaultStreams`).
      expect(find.text('PUBLIC'), findsNWidgets(2));
      expect(find.text('PRIVÉ'), findsOneWidget);
    });

    testWidgets(
      'durée depuis startedAt affichée ; omise si le flux n\'est pas démarré',
      (tester) async {
        await tester.pumpWidget(_buildHarness(_FakeAdminStreamsRepository()));
        await tester.pumpAndSettle();

        expect(find.textContaining('il y a 12 min'), findsOneWidget);
        expect(find.textContaining('il y a 3 h'), findsOneWidget);
        // Flux 3 (`startedAt: null`) : aucune durée affichée pour sa tuile —
        // seules les deux tuiles démarrées en montrent une.
        expect(find.textContaining('il y a'), findsNWidgets(2));
      },
    );

    testWidgets(
      'scroll jusqu\'en bas déclenche automatiquement loadMore (accumulation)',
      (tester) async {
        final many = List.generate(
          25,
          (i) => AdminStream(
            id: '$i',
            title: 'Stream $i',
            isPublic: true,
            startedAt: null,
            userId: 'u$i',
            username: 'user$i',
          ),
        );
        final repo = _FakeAdminStreamsRepository(all: many);
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        expect(find.text('Stream 0'), findsOneWidget);
        expect(find.text('Stream 20'), findsNothing);

        final scrollableFinder = find.descendant(
          of: find.byKey(const Key('admin_streams_list')),
          matching: find.byType(Scrollable),
        );
        final scrollableState =
            tester.state<ScrollableState>(scrollableFinder);
        scrollableState.position.jumpTo(
          scrollableState.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();

        expect(repo.listCalls, 2);
        expect(
          find.byKey(const Key('admin_streams_load_more_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'interrompre un flux demande confirmation ; annuler ne change rien',
      (tester) async {
        final repo = _FakeAdminStreamsRepository();
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('admin_stream_stop_1')));
        await tester.pumpAndSettle();

        expect(find.text('Interrompre le flux "Chill beats" de alice ?'),
            findsOneWidget);
        expect(find.text('Les auditeurs seront déconnectés.'), findsOneWidget);

        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();

        expect(repo.stopCalls, 0);
        expect(find.text('Chill beats'), findsOneWidget);
      },
    );

    testWidgets(
      'confirmer l\'interruption appelle le repository, retire la tuile et '
      'affiche un toast succès',
      (tester) async {
        final repo = _FakeAdminStreamsRepository();
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('admin_stream_stop_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('admin_confirm_stop_button')));
        await tester.pumpAndSettle();

        expect(repo.stopCalls, 1);
        expect(find.text('Chill beats'), findsNothing);
        expect(find.text('Flux interrompu'), findsOneWidget);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );

    testWidgets(
      '409 sur interruption affiche un toast avec le message serveur et '
      'garde la tuile',
      (tester) async {
        final repo = _FakeAdminStreamsRepository(
          mutationError: const ConflictException('stream already ended'),
        );
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('admin_stream_stop_1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('admin_confirm_stop_button')));
        await tester.pumpAndSettle();

        expect(find.text('stream already ended'), findsOneWidget);
        expect(find.text('Chill beats'), findsOneWidget);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );

    testWidgets(
      'échec réseau au premier chargement affiche l\'icône wifi_off',
      (tester) async {
        final repo = _FakeAdminStreamsRepository(
          nextListError: const NetworkException(),
        );
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        expect(find.text('Pas de connexion réseau'), findsOneWidget);
        expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
      },
    );

    testWidgets(
      'échec serveur au premier chargement affiche une icône neutre '
      '(pas wifi_off)',
      (tester) async {
        final repo = _FakeAdminStreamsRepository(
          nextListError: const ServerException(),
        );
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        expect(find.text('Impossible de charger les flux'), findsOneWidget);
        expect(find.byIcon(Icons.wifi_off_outlined), findsNothing);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);
      },
    );

    testWidgets(
      'échec de loadMore (page suivante) affiche un toast d\'erreur sans '
      'remplacer la liste déjà affichée',
      (tester) async {
        final many = List.generate(
          25,
          (i) => AdminStream(
            id: '$i',
            title: 'Stream $i',
            isPublic: true,
            startedAt: null,
            userId: 'u$i',
            username: 'user$i',
          ),
        );
        final repo = _FakeAdminStreamsRepository(all: many);
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        // Le chargement initial (page 1) a réussi ; on arme l'échec du
        // PROCHAIN appel — celui déclenché par le loadMore du scroll ci-dessous.
        repo.nextListError = const ServerException();

        final scrollableFinder = find.descendant(
          of: find.byKey(const Key('admin_streams_list')),
          matching: find.byType(Scrollable),
        );
        final scrollableState =
            tester.state<ScrollableState>(scrollableFinder);
        scrollableState.position.jumpTo(
          scrollableState.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();

        expect(find.text('Impossible de charger les flux'), findsOneWidget);
        // La liste reste affichée (pas de bascule vers la vue d'erreur plein
        // écran) : le toast est désormais le seul signal de l'échec.
        expect(find.byKey(const Key('admin_streams_list')), findsOneWidget);

        toastification.dismissAll(delayForAnimation: false);
        await tester.pump(const Duration(milliseconds: 700));
      },
    );

    testWidgets('état vide : « Aucun flux en direct »', (tester) async {
      final repo = _FakeAdminStreamsRepository(all: []);
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      expect(find.text('Aucun flux en direct'), findsOneWidget);
    });

    testWidgets('tirer pour rafraîchir recharge la première page', (
      tester,
    ) async {
      final repo = _FakeAdminStreamsRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();
      expect(repo.listCalls, 1);

      await tester.fling(
        find.byKey(const Key('admin_streams_list')),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(repo.listCalls, 2);
    });
  });
}
