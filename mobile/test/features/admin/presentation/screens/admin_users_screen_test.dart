import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/domain/entities/admin_user.dart';
import 'package:streampulse/features/admin/domain/repositories/admin_repository.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_users_provider.dart';
import 'package:streampulse/features/admin/presentation/screens/admin_users_screen.dart';

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({List<AdminUser>? all, this.mutationError})
      : all = all ?? _defaultUsers();

  final List<AdminUser> all;
  final Object? mutationError;

  int setActiveCalls = 0;
  int deleteCalls = 0;
  String? lastSearch;
  String? lastRole;
  String? lastStatus;

  @override
  Future<({List<AdminUser> users, int total})> listUsers({
    String? search,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    lastSearch = search;
    lastRole = role;
    lastStatus = status;
    final filtered = all.where((u) {
      if (search != null && search.isNotEmpty) {
        final q = search.toLowerCase();
        if (!u.username.toLowerCase().contains(q) &&
            !u.email.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (role != null && u.role != role) return false;
      if (status == 'active' && !u.isActive) return false;
      if (status == 'inactive' && u.isActive) return false;
      return true;
    }).toList();
    final page = filtered.skip(offset).take(limit).toList();
    return (users: page, total: filtered.length);
  }

  @override
  Future<AdminUser> setUserActive(String id, bool active) async {
    setActiveCalls++;
    if (mutationError != null) throw mutationError!;
    final user = all.firstWhere((u) => u.id == id);
    return AdminUser(
      id: user.id,
      email: user.email,
      username: user.username,
      role: user.role,
      isActive: active,
      createdAt: user.createdAt,
    );
  }

  @override
  Future<void> deleteUser(String id) async {
    deleteCalls++;
    if (mutationError != null) throw mutationError!;
  }
}

List<AdminUser> _defaultUsers() => [
      AdminUser(
        id: '1',
        email: 'alice@example.com',
        username: 'alice',
        role: 'user',
        isActive: true,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      AdminUser(
        id: '2',
        email: 'bob@example.com',
        username: 'bob',
        role: 'broadcaster',
        isActive: true,
        createdAt: DateTime.utc(2026, 1, 2),
      ),
      AdminUser(
        id: '3',
        email: 'carol@example.com',
        username: 'carol',
        role: 'admin',
        isActive: false,
        createdAt: DateTime.utc(2026, 1, 3),
      ),
    ];

Widget _buildHarness(AdminRepository repository) {
  return ToastificationWrapper(
    child: MaterialApp(home: AdminUsersScreen(repository: repository)),
  );
}

void main() {
  group('AdminUsersScreen', () {
    testWidgets('affiche les tuiles utilisateur après chargement', (tester) async {
      await tester.pumpWidget(_buildHarness(_FakeAdminRepository()));
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('alice@example.com'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      expect(find.text('Administration'), findsOneWidget);
    });

    testWidgets('recherche (debounce) filtre la liste', (tester) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('admin_users_search_field')),
        'ali',
      );
      // Avant l'expiration du debounce (300 ms) : pas encore relancé.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('bob'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsNothing);
      expect(find.text('carol'), findsNothing);
    });

    testWidgets('filtre par rôle', (tester) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_users_role_chip_admin')));
      await tester.pumpAndSettle();

      expect(find.text('carol'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
      expect(find.text('bob'), findsNothing);
    });

    testWidgets('filtre par statut', (tester) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('admin_users_status_chip_inactive')),
      );
      await tester.pumpAndSettle();

      expect(find.text('carol'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
    });

    testWidgets(
      'scroll jusqu\'en bas déclenche automatiquement loadMore (accumulation)',
      (tester) async {
        final many = List.generate(
          25,
          (i) => AdminUser(
            id: '$i',
            email: 'user$i@example.com',
            username: 'user$i',
            role: 'user',
            isActive: true,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final repo = _FakeAdminRepository(all: many);
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        // Page 1 seulement (limit=20) : les 5 derniers ne sont pas encore chargés.
        expect(find.text('user0'), findsOneWidget);
        expect(find.text('user20'), findsNothing);

        // Le pied de liste n'est construit que lorsqu'il approche du viewport
        // (ListView paresseuse) : on saute directement en bas (jumpTo) plutôt
        // que de simuler un drag — l'écran a 3 Scrollable (2 rangées de
        // filtres + la liste), ce qui rend `scrollUntilVisible` ambigu.
        // Ce jumpTo déclenche lui-même le listener de scroll (à moins de
        // 200px du bas) : `loadMore` s'exécute automatiquement.
        final scrollableFinder = find.descendant(
          of: find.byKey(const Key('admin_users_list')),
          matching: find.byType(Scrollable),
        );
        final scrollableState = tester.state<ScrollableState>(scrollableFinder);
        scrollableState.position.jumpTo(
          scrollableState.position.maxScrollExtent,
        );
        await tester.pumpAndSettle();

        // La liste (paresseuse) ne garde en mémoire que les tuiles proches du
        // viewport : `user0` a pu être démonté après le scroll. On vérifie
        // donc l'accumulation directement sur l'état du provider plutôt que
        // sur la présence de tuiles précises à l'écran.
        final provider = Provider.of<AdminUsersProvider>(
          tester.element(find.byKey(const Key('admin_users_search_field'))),
          listen: false,
        );
        expect(provider.users, hasLength(25));
        expect(provider.total, 25);
        expect(provider.hasMore, isFalse);
        expect(
          find.byKey(const Key('admin_users_load_more_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'désactiver un compte actif demande confirmation ; annuler ne change rien',
      (tester) async {
        final repo = _FakeAdminRepository();
        await tester.pumpWidget(_buildHarness(repo));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('admin_user_switch_1')));
        await tester.pumpAndSettle();

        expect(find.text('Désactiver alice ?'), findsOneWidget);

        await tester.tap(find.text('Annuler'));
        await tester.pumpAndSettle();

        expect(repo.setActiveCalls, 0);
      },
    );

    testWidgets('désactiver un compte actif : confirmer appelle le repository', (
      tester,
    ) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_switch_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin_confirm_deactivate_button')));
      await tester.pumpAndSettle();

      expect(repo.setActiveCalls, 1);
      expect(find.text('Compte désactivé'), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('réactiver un compte inactif ne demande pas de confirmation', (
      tester,
    ) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_switch_3')));
      await tester.pumpAndSettle();

      expect(find.text('Désactiver carol ?'), findsNothing);
      expect(repo.setActiveCalls, 1);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('409 sur désactivation affiche un toast avec le message serveur', (
      tester,
    ) async {
      final repo = _FakeAdminRepository(
        mutationError: const ConflictException(
          'cannot deactivate the last active admin',
        ),
      );
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_switch_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin_confirm_deactivate_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('cannot deactivate the last active admin'),
        findsOneWidget,
      );
      // La liste n'a pas été modifiée localement : alice est toujours présente.
      expect(find.text('alice'), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('supprimer un compte demande confirmation (mention cascade)', (
      tester,
    ) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();

      expect(find.text('Supprimer définitivement alice ?'), findsOneWidget);
      expect(find.textContaining('cascade'), findsOneWidget);

      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 0);
      expect(find.text('alice'), findsOneWidget);
    });

    testWidgets('supprimer un compte : confirmer retire la tuile de la liste', (
      tester,
    ) async {
      final repo = _FakeAdminRepository();
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin_confirm_delete_button')));
      await tester.pumpAndSettle();

      expect(repo.deleteCalls, 1);
      expect(find.text('alice'), findsNothing);
      expect(find.text('Compte supprimé'), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });

    testWidgets('409 sur suppression affiche un toast et garde la tuile', (
      tester,
    ) async {
      final repo = _FakeAdminRepository(
        mutationError: const ConflictException(
          'cannot delete your own account',
        ),
      );
      await tester.pumpWidget(_buildHarness(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('admin_user_menu_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supprimer').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('admin_confirm_delete_button')));
      await tester.pumpAndSettle();

      expect(find.text('cannot delete your own account'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);

      toastification.dismissAll(delayForAnimation: false);
      await tester.pump(const Duration(milliseconds: 700));
    });
  });
}
