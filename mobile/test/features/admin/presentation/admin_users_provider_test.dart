import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/domain/entities/admin_user.dart';
import 'package:streampulse/features/admin/domain/repositories/admin_repository.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_users_provider.dart';

AdminUser _user(String id, {String role = 'user', bool isActive = true}) =>
    AdminUser(
      id: id,
      email: '$id@example.com',
      username: 'user_$id',
      role: role,
      isActive: isActive,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// Trace d'un appel à `listUsers`, pour vérifier les filtres/pagination transmis.
class _ListCall {
  _ListCall({
    required this.search,
    required this.role,
    required this.status,
    required this.limit,
    required this.offset,
  });

  final String? search;
  final String? role;
  final String? status;
  final int limit;
  final int offset;
}

class _FakeAdminRepository implements AdminRepository {
  _FakeAdminRepository({List<AdminUser>? all, this.listError, this.mutationError})
      : all = all ?? List.generate(5, (i) => _user('u$i'));

  final List<AdminUser> all;

  /// Mutable : un test peut faire échouer le 1er appel puis annuler l'erreur
  /// pour que le 2e réussisse (scénario « le réseau revient »).
  Object? listError;
  final Object? mutationError;

  final List<_ListCall> calls = [];
  int setActiveCalls = 0;
  int deleteCalls = 0;

  @override
  Future<({List<AdminUser> users, int total})> listUsers({
    String? search,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) async {
    calls.add(
      _ListCall(
        search: search,
        role: role,
        status: status,
        limit: limit,
        offset: offset,
      ),
    );
    if (listError != null) throw listError!;
    final page = all.skip(offset).take(limit).toList();
    return (users: page, total: all.length);
  }

  @override
  Future<AdminUser> setUserActive(String id, bool active) async {
    setActiveCalls++;
    if (mutationError != null) throw mutationError!;
    // `orElse` : le backend peut confirmer la mutation pour un id qui n'est
    // plus (ou jamais été) dans `all` — le test du no-op (#8) simule ce cas.
    final user = all.firstWhere((u) => u.id == id, orElse: () => _user(id));
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

/// Fake dont chaque `listUsers` reste en vol tant que le test n'a pas résolu
/// son [Completer] : permet de contrôler l'ORDRE d'arrivée des réponses pour
/// vérifier le comportement out-of-order (jeton de génération).
///
/// `setUserActive`/`deleteUser` résolvent immédiatement (contrairement à
/// `listUsers`) : ils simulent une mutation concurrente (autre onglet, autre
/// admin) qui se termine PENDANT qu'un `loadMore` reste en vol, sans avoir
/// besoin de contrôler leur propre timing.
class _CompleterAdminRepository implements AdminRepository {
  final List<Completer<({List<AdminUser> users, int total})>> pending = [];

  @override
  Future<({List<AdminUser> users, int total})> listUsers({
    String? search,
    String? role,
    String? status,
    int limit = 20,
    int offset = 0,
  }) {
    final completer = Completer<({List<AdminUser> users, int total})>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<AdminUser> setUserActive(String id, bool active) async =>
      _user(id, isActive: active);

  @override
  Future<void> deleteUser(String id) async {}
}

void main() {
  group('AdminUsersProvider.load', () {
    test('succès : expose la liste, le total ; loading revient à faux', () async {
      final provider = AdminUsersProvider(_FakeAdminRepository());

      await provider.load();

      expect(provider.users, hasLength(5));
      expect(provider.total, 5);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('recherche vide envoie search=null (pas de filtre)', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);

      await provider.load();

      expect(repo.calls.single.search, isNull);
      expect(repo.calls.single.offset, 0);
    });

    test('échec réseau : expose un message, ne relance pas, liste vide', () async {
      final provider = AdminUsersProvider(
        _FakeAdminRepository(listError: const NetworkException()),
      );

      await expectLater(provider.load(), completes);

      expect(provider.error, 'Pas de connexion réseau');
      expect(provider.users, isEmpty);
      expect(provider.loading, isFalse);
    });

    test('échec générique : expose un message générique', () async {
      final provider = AdminUsersProvider(
        _FakeAdminRepository(listError: const ServerException()),
      );

      await expectLater(provider.load(), completes);

      expect(provider.error, isNotNull);
      expect(provider.loading, isFalse);
    });

    test('un load réussi après un échec réinitialise error (même provider)',
        () async {
      final repo = _FakeAdminRepository(listError: const NetworkException());
      final provider = AdminUsersProvider(repo);

      await provider.load();
      expect(provider.error, isNotNull);
      expect(provider.users, isEmpty);

      repo.listError = null; // le réseau revient : le 2e appel réussit
      await provider.load();

      expect(provider.error, isNull);
      expect(provider.users, hasLength(5));
    });

    test('reset: false conserve la liste affichée pendant le rechargement', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      expect(provider.users, isNotEmpty);

      final future = provider.load(reset: false);
      // Pas vidée immédiatement : l'ancienne liste reste visible pendant le fetch.
      expect(provider.users, isNotEmpty);
      await future;
      expect(provider.users, hasLength(5));
    });

    test('reset: true (défaut) vide la liste avant le rechargement', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      expect(provider.users, isNotEmpty);

      final future = provider.load();
      expect(provider.users, isEmpty);
      await future;
      expect(provider.users, hasLength(5));
    });
  });

  group('filtres', () {
    test('setRoleFilter relance load avec le nouveau rôle', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();

      await provider.setRoleFilter('admin');

      expect(provider.roleFilter, 'admin');
      expect(repo.calls.last.role, 'admin');
      expect(repo.calls.last.offset, 0);
    });

    test('setStatusFilter relance load avec le nouveau statut', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();

      await provider.setStatusFilter('inactive');

      expect(provider.statusFilter, 'inactive');
      expect(repo.calls.last.status, 'inactive');
    });

    test('revenir à "Tous" (null) efface le filtre transmis au repository', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.setRoleFilter('broadcaster');

      await provider.setRoleFilter(null);

      expect(provider.roleFilter, isNull);
      expect(repo.calls.last.role, isNull);
    });

    test('changer de filtre vide la liste affichée pendant le rechargement', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      expect(provider.users, isNotEmpty);

      final future = provider.setRoleFilter('admin');
      expect(provider.users, isEmpty);
      await future;
    });
  });

  group('chargements concurrents (out-of-order)', () {
    test(
        'deux load entrelacés : le DERNIER gagne même si sa réponse arrive '
        'en premier', () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      // Deux load() partent avant toute réponse (ex. setRoleFilter puis
      // setStatusFilter tapés vite).
      final first = provider.load();
      final second = provider.load();
      expect(repo.pending, hasLength(2));

      // Le SECOND (le plus récent) répond en premier…
      repo.pending[1].complete((users: [_user('fresh')], total: 1));
      await second;
      expect(provider.users.single.id, 'fresh');

      // …puis la réponse OBSOLÈTE du premier arrive en dernier : elle ne
      // doit pas écraser l'état du chargement le plus récent.
      repo.pending[0].complete(
        (users: List.generate(5, (i) => _user('stale$i')), total: 5),
      );
      await first;

      expect(provider.users.single.id, 'fresh');
      expect(provider.total, 1);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('un échec obsolète n\'écrase pas le succès du load le plus récent',
        () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      final first = provider.load();
      final second = provider.load();

      repo.pending[1].complete((users: [_user('fresh')], total: 1));
      await second;

      // L'échec du load obsolète arrive après le succès du plus récent :
      // error doit rester null.
      repo.pending[0].completeError(const NetworkException());
      await first;

      expect(provider.error, isNull);
      expect(provider.users.single.id, 'fresh');
      expect(provider.loading, isFalse);
    });

    test('une page loadMore obsolète (load parti entre-temps) est abandonnée',
        () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      // Première page complète : hasMore vrai.
      final initial = provider.load();
      repo.pending[0].complete(
        (users: List.generate(20, (i) => _user('u$i')), total: 45),
      );
      await initial;
      expect(provider.hasMore, isTrue);

      final more = provider.loadMore(); // page 2 en vol…
      final reload = provider.load(); // …puis changement de filtre

      // Le load (plus récent) répond d'abord.
      repo.pending[2].complete((users: [_user('fresh')], total: 1));
      await reload;

      // La page 2 obsolète arrive ensuite : PAS accumulée.
      repo.pending[1].complete(
        (users: List.generate(20, (i) => _user('stale$i')), total: 45),
      );
      await more;

      expect(provider.users.single.id, 'fresh');
      expect(provider.total, 1);
      expect(provider.loadingMore, isFalse);
      // La pagination n'est pas bloquée par la page abandonnée.
      expect(provider.hasMore, isFalse);
    });
  });

  group('mutations concurrentes (isolation load / loadMore)', () {
    test(
        'delete() pendant un loadMore en vol invalide la page obsolète '
        '(pas de doublon, total cohérent)', () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      final initial = provider.load();
      repo.pending[0].complete(
        (users: List.generate(20, (i) => _user('u$i')), total: 100),
      );
      await initial;
      expect(provider.users, hasLength(20));
      expect(provider.total, 100);
      expect(provider.hasMore, isTrue);

      final more = provider.loadMore(); // offset 20, reste en vol (pending[1])
      expect(repo.pending, hasLength(2));

      // Suppression concurrente de u0 (autre admin/onglet) pendant que la
      // page 2 est en vol : décrémente total et retire u0 immédiatement.
      await provider.delete(_user('u0'));
      expect(provider.users, hasLength(19));
      expect(provider.users.any((u) => u.id == 'u0'), isFalse);
      expect(provider.total, 99);

      // La page 2 (obsolète) se résout enfin : sans le compteur de version de
      // liste, elle ré-accumulerait par-dessus (`[..._users, ...result.users]`),
      // ressuscitant u0 et écrasant total à 100. Avec le fix, elle doit être
      // intégralement ignorée.
      repo.pending[1].complete(
        (users: List.generate(20, (i) => _user('u${i + 20}')), total: 100),
      );
      await more;

      expect(provider.users, hasLength(19));
      expect(provider.users.any((u) => u.id == 'u0'), isFalse);
      expect(provider.total, 99);
      expect(provider.loadingMore, isFalse);
    });

    test(
        'toggleActive() pendant un loadMore en vol invalide la page obsolète',
        () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      final initial = provider.load();
      repo.pending[0].complete(
        (users: List.generate(20, (i) => _user('u$i')), total: 100),
      );
      await initial;

      final more = provider.loadMore(); // offset 20, reste en vol (pending[1])
      expect(repo.pending, hasLength(2));

      await provider.toggleActive(_user('u0'));

      // Page 2 obsolète : ignorée, comme pour delete() ci-dessus.
      repo.pending[1].complete(
        (users: List.generate(20, (i) => _user('u${i + 20}')), total: 100),
      );
      await more;

      expect(provider.users, hasLength(20)); // pas 40 : page ignorée
      expect(provider.loadingMore, isFalse);
    });

    test(
        'delete() résolu pendant qu\'un load() est en vol : loading revient '
        'à false (pas de spinner figé — régression du fix ci-dessus)',
        () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      // Premier load, complet : peuple la liste avec u0 (utilisateur réel,
      // visible, que l'on va supprimer ci-dessous).
      final firstLoad = provider.load();
      repo.pending[0].complete((users: [_user('u0')], total: 1));
      await firstLoad;
      expect(provider.users, hasLength(1));

      // Un second load part (ex. une recherche tapée juste après avoir lancé
      // une suppression) — `reset: false` pour que u0 reste visible pendant
      // que ce load est en vol, comme un rechargement en tâche de fond.
      final loadFuture = provider.load(reset: false);
      expect(provider.loading, isTrue);
      expect(repo.pending, hasLength(2));

      // La suppression de u0 (déjà lancée avant la recherche, cf. scénario du
      // ticket) se résout AVANT la réponse de ce second load. `delete` ne
      // doit PAS invalider ce `load()` : seul `loadMore` a besoin d'être
      // protégé contre une mutation de `_users` pendant son vol (son offset
      // capturé serait faussé) — un `load()` recharge tout depuis zéro, il
      // n'a rien à protéger.
      await provider.delete(_user('u0'));

      repo.pending[1].complete(
        (users: List.generate(5, (i) => _user('x$i')), total: 5),
      );
      await loadFuture;

      expect(provider.loading, isFalse);
      expect(provider.users, hasLength(5)); // la réponse du load reste valide
    });

    test(
        'toggleActive() résolu pendant qu\'un load() est en vol : loading '
        'revient à false (pas de spinner figé)', () async {
      final repo = _CompleterAdminRepository();
      final provider = AdminUsersProvider(repo);

      // Premier load, complet : peuple la liste avec u0 (utilisateur réel
      // que l'on va basculer ci-dessous — un toggle sur un id absent est un
      // no-op qui ne bump aucun compteur, cf. fix #8 : il faut un VRAI match
      // pour reproduire la régression).
      final firstLoad = provider.load();
      repo.pending[0].complete((users: [_user('u0')], total: 1));
      await firstLoad;

      final loadFuture = provider.load(reset: false);
      expect(provider.loading, isTrue);

      await provider.toggleActive(_user('u0'));

      repo.pending[1].complete(
        (users: List.generate(5, (i) => _user('x$i')), total: 5),
      );
      await loadFuture;

      expect(provider.loading, isFalse);
      expect(provider.users, hasLength(5));
    });
  });

  group('AdminUsersProvider.loadMore', () {
    test('accumule les pages tant que users.length < total', () async {
      final repo = _FakeAdminRepository(
        all: List.generate(45, (i) => _user('u$i')),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();
      expect(provider.users, hasLength(20));
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.users, hasLength(40));
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.users, hasLength(45));
      expect(provider.hasMore, isFalse);
    });

    test('offset += limit à chaque page', () async {
      final repo = _FakeAdminRepository(
        all: List.generate(45, (i) => _user('u$i')),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();

      await provider.loadMore();

      expect(repo.calls.last.offset, 20);
      expect(repo.calls.last.limit, 20);
    });

    test('ne fait rien si hasMore est faux (déjà tout chargé)', () async {
      final repo = _FakeAdminRepository(
        all: List.generate(3, (i) => _user('u$i')),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();
      expect(provider.hasMore, isFalse);
      final callsBefore = repo.calls.length;

      await provider.loadMore();

      expect(repo.calls.length, callsBefore);
    });

    test('garde anti-double-appel : deux loadMore concurrents ne font qu\'une page', () async {
      final repo = _FakeAdminRepository(
        all: List.generate(45, (i) => _user('u$i')),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();

      final f1 = provider.loadMore();
      final f2 = provider.loadMore();
      await Future.wait([f1, f2]);

      expect(provider.users, hasLength(40));
    });
  });

  group('AdminUsersProvider.setSearch', () {
    test('débounce : un seul appel repository après plusieurs frappes rapides', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);

      provider.setSearch('a');
      provider.setSearch('al');
      provider.setSearch('ali');

      await Future.delayed(const Duration(milliseconds: 100));
      expect(repo.calls, isEmpty);

      await Future.delayed(const Duration(milliseconds: 300));
      expect(repo.calls, hasLength(1));
      expect(repo.calls.single.search, 'ali');
      expect(provider.search, 'ali');
    });

    test('recherche vidée après une frappe envoie search=null', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);

      provider.setSearch('');
      await Future.delayed(const Duration(milliseconds: 350));

      expect(repo.calls.single.search, isNull);
    });

    test('dispose annule le debounce en attente', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);

      provider.setSearch('ali');
      provider.dispose();

      await Future.delayed(const Duration(milliseconds: 400));
      expect(repo.calls, isEmpty);
    });
  });

  group('AdminUsersProvider.toggleActive', () {
    test('succès : remplace l\'utilisateur dans la liste locale, retourne true',
        () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      final target = provider.users.first;
      expect(target.isActive, isTrue);

      final changed = await provider.toggleActive(target);

      expect(changed, isTrue);
      expect(repo.setActiveCalls, 1);
      final updated = provider.users.firstWhere((u) => u.id == target.id);
      expect(updated.isActive, isFalse);
      expect(provider.users, hasLength(5));
    });

    test(
        'utilisateur déjà absent de la liste locale : no-op silencieux, '
        'retourne false, ne notifie pas', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      final usersBefore = provider.users;

      var notified = false;
      provider.addListener(() => notified = true);

      // Le backend confirme la mutation (`setUserActive` réussit), mais
      // l'utilisateur n'est plus dans `_users` (retiré entre-temps, ex. par
      // un autre admin) : l'appelant ne doit pas afficher de toast succès.
      final changed = await provider.toggleActive(_user('does-not-exist'));

      expect(changed, isFalse);
      expect(repo.setActiveCalls, 1);
      expect(notified, isFalse);
      expect(provider.users, same(usersBefore));
    });

    test('409 : relance l\'exception sans modifier la liste locale', () async {
      final repo = _FakeAdminRepository(
        mutationError: const ConflictException(
          'cannot deactivate the last active admin',
        ),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();
      final target = provider.users.first;

      await expectLater(
        provider.toggleActive(target),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'cannot deactivate the last active admin',
          ),
        ),
      );
      expect(provider.users.first.isActive, target.isActive);
    });
  });

  group('AdminUsersProvider.delete', () {
    test('succès : retire l\'utilisateur de la liste locale et décrémente total', () async {
      final repo = _FakeAdminRepository();
      final provider = AdminUsersProvider(repo);
      await provider.load();
      final target = provider.users.first;
      final totalBefore = provider.total;

      await provider.delete(target);

      expect(repo.deleteCalls, 1);
      expect(provider.users.any((u) => u.id == target.id), isFalse);
      expect(provider.users, hasLength(4));
      expect(provider.total, totalBefore - 1);
    });

    test('409 : relance l\'exception sans modifier la liste locale', () async {
      final repo = _FakeAdminRepository(
        mutationError: const ConflictException(
          'cannot delete your own account',
        ),
      );
      final provider = AdminUsersProvider(repo);
      await provider.load();
      final countBefore = provider.users.length;

      await expectLater(
        provider.delete(provider.users.first),
        throwsA(isA<ConflictException>()),
      );
      expect(provider.users, hasLength(countBefore));
    });
  });
}
