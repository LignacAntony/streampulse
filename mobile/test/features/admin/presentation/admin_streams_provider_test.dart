import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/domain/entities/admin_stream.dart';
import 'package:streampulse/features/admin/domain/repositories/admin_streams_repository.dart';
import 'package:streampulse/features/admin/presentation/providers/admin_streams_provider.dart';

AdminStream _stream(
  String id, {
  bool isPublic = true,
  DateTime? startedAt,
  String userId = 'u1',
  String username = 'alice',
}) =>
    AdminStream(
      id: id,
      title: 'Stream $id',
      isPublic: isPublic,
      startedAt: startedAt ?? DateTime.utc(2026, 1, 1),
      userId: userId,
      username: username,
    );

/// Trace d'un appel à `listLiveStreams`, pour vérifier la pagination transmise.
class _ListCall {
  _ListCall({required this.limit, required this.offset});

  final int limit;
  final int offset;
}

class _FakeAdminStreamsRepository implements AdminStreamsRepository {
  _FakeAdminStreamsRepository({
    List<AdminStream>? all,
    this.listError,
    this.mutationError,
  }) : all = all ?? List.generate(5, (i) => _stream('s$i'));

  final List<AdminStream> all;

  /// Mutable : un test peut faire échouer le 1er appel puis annuler l'erreur
  /// pour que le 2e réussisse (scénario « le réseau revient »).
  Object? listError;
  final Object? mutationError;

  final List<_ListCall> calls = [];
  int stopCalls = 0;

  @override
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async {
    calls.add(_ListCall(limit: limit, offset: offset));
    if (listError != null) throw listError!;
    final page = all.skip(offset).take(limit).toList();
    return (streams: page, total: all.length);
  }

  @override
  Future<void> stopStream(String id) async {
    stopCalls++;
    if (mutationError != null) throw mutationError!;
  }
}

/// Fake dont chaque `listLiveStreams` reste en vol tant que le test n'a pas
/// résolu son [Completer] : permet de contrôler l'ORDRE d'arrivée des
/// réponses pour vérifier le comportement out-of-order (jeton de génération).
///
/// `stopStream` résout immédiatement (contrairement à `listLiveStreams`) : il
/// simule une interruption concurrente (autre admin) qui se termine PENDANT
/// qu'un `loadMore` reste en vol, sans avoir besoin de contrôler son propre
/// timing.
class _CompleterAdminStreamsRepository implements AdminStreamsRepository {
  final List<Completer<({List<AdminStream> streams, int total})>> pending =
      [];

  @override
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) {
    final completer = Completer<({List<AdminStream> streams, int total})>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> stopStream(String id) async {}
}

/// Renvoie toujours la même paire (streams, total) fournie au constructeur —
/// utile pour reproduire une désync serveur (`total` incohérent avec la
/// longueur de `streams`) sans dépendre du calcul `all.length` de
/// `_FakeAdminStreamsRepository`.
class _FixedResponseRepository implements AdminStreamsRepository {
  _FixedResponseRepository({required this.streams, required this.total});

  final List<AdminStream> streams;
  final int total;

  @override
  Future<({List<AdminStream> streams, int total})> listLiveStreams({
    int limit = 20,
    int offset = 0,
  }) async =>
      (streams: streams, total: total);

  @override
  Future<void> stopStream(String id) async {}
}

void main() {
  group('AdminStreamsProvider.load', () {
    test('succès : expose la liste, le total ; loading revient à faux', () async {
      final provider = AdminStreamsProvider(_FakeAdminStreamsRepository());

      await provider.load();

      expect(provider.streams, hasLength(5));
      expect(provider.total, 5);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('transmet limit/offset (première page)', () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      await provider.load();

      expect(repo.calls.single.limit, AdminStreamsProvider.pageSize);
      expect(repo.calls.single.offset, 0);
    });

    test('échec réseau : expose un message, ne relance pas, liste vide', () async {
      final provider = AdminStreamsProvider(
        _FakeAdminStreamsRepository(listError: const NetworkException()),
      );

      await expectLater(provider.load(), completes);

      expect(provider.error, 'Pas de connexion réseau');
      expect(provider.streams, isEmpty);
      expect(provider.loading, isFalse);
    });

    test('échec générique : expose un message générique', () async {
      final provider = AdminStreamsProvider(
        _FakeAdminStreamsRepository(listError: const ServerException()),
      );

      await expectLater(provider.load(), completes);

      expect(provider.error, isNotNull);
      expect(provider.loading, isFalse);
    });

    test('un load réussi après un échec réinitialise error (même provider)',
        () async {
      final repo = _FakeAdminStreamsRepository(
        listError: const NetworkException(),
      );
      final provider = AdminStreamsProvider(repo);

      await provider.load();
      expect(provider.error, isNotNull);
      expect(provider.streams, isEmpty);

      repo.listError = null; // le réseau revient : le 2e appel réussit
      await provider.load();

      expect(provider.error, isNull);
      expect(provider.streams, hasLength(5));
    });

    test('reset: false conserve la liste affichée pendant le rechargement',
        () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.streams, isNotEmpty);

      final future = provider.load(reset: false);
      // Pas vidée immédiatement : l'ancienne liste reste visible pendant le fetch.
      expect(provider.streams, isNotEmpty);
      await future;
      expect(provider.streams, hasLength(5));
    });

    test('reset: true (défaut) vide la liste avant le rechargement', () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.streams, isNotEmpty);

      final future = provider.load();
      expect(provider.streams, isEmpty);
      await future;
      expect(provider.streams, hasLength(5));
    });
  });

  group('chargements concurrents (out-of-order)', () {
    test(
        'deux load entrelacés : le DERNIER gagne même si sa réponse arrive '
        'en premier', () async {
      final repo = _CompleterAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      // Deux load() partent avant toute réponse (ex. pull-to-refresh
      // déclenché deux fois vite).
      final first = provider.load();
      final second = provider.load();
      expect(repo.pending, hasLength(2));

      // Le SECOND (le plus récent) répond en premier…
      repo.pending[1].complete((streams: [_stream('fresh')], total: 1));
      await second;
      expect(provider.streams.single.id, 'fresh');

      // …puis la réponse OBSOLÈTE du premier arrive en dernier : elle ne
      // doit pas écraser l'état du chargement le plus récent.
      repo.pending[0].complete(
        (streams: List.generate(5, (i) => _stream('stale$i')), total: 5),
      );
      await first;

      expect(provider.streams.single.id, 'fresh');
      expect(provider.total, 1);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
    });

    test('un échec obsolète n\'écrase pas le succès du load le plus récent',
        () async {
      final repo = _CompleterAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      final first = provider.load();
      final second = provider.load();

      repo.pending[1].complete((streams: [_stream('fresh')], total: 1));
      await second;

      // L'échec du load obsolète arrive après le succès du plus récent :
      // error doit rester null.
      repo.pending[0].completeError(const NetworkException());
      await first;

      expect(provider.error, isNull);
      expect(provider.streams.single.id, 'fresh');
      expect(provider.loading, isFalse);
    });

    test('une page loadMore obsolète (load parti entre-temps) est abandonnée',
        () async {
      final repo = _CompleterAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      // Première page complète : hasMore vrai.
      final initial = provider.load();
      repo.pending[0].complete(
        (streams: List.generate(20, (i) => _stream('s$i')), total: 45),
      );
      await initial;
      expect(provider.hasMore, isTrue);

      final more = provider.loadMore(); // page 2 en vol…
      final reload = provider.load(); // …puis rechargement (pull-to-refresh)

      // Le load (plus récent) répond d'abord.
      repo.pending[2].complete((streams: [_stream('fresh')], total: 1));
      await reload;

      // La page 2 obsolète arrive ensuite : PAS accumulée.
      repo.pending[1].complete(
        (streams: List.generate(20, (i) => _stream('stale$i')), total: 45),
      );
      await more;

      expect(provider.streams.single.id, 'fresh');
      expect(provider.total, 1);
      expect(provider.loadingMore, isFalse);
      // La pagination n'est pas bloquée par la page abandonnée.
      expect(provider.hasMore, isFalse);
    });
  });

  group('mutations concurrentes (isolation load / loadMore)', () {
    test(
        'stop() pendant un loadMore en vol invalide la page obsolète '
        '(pas de doublon, total cohérent)', () async {
      final repo = _CompleterAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      final initial = provider.load();
      repo.pending[0].complete(
        (streams: List.generate(20, (i) => _stream('s$i')), total: 100),
      );
      await initial;
      expect(provider.streams, hasLength(20));
      expect(provider.total, 100);
      expect(provider.hasMore, isTrue);

      final more = provider.loadMore(); // offset 20, reste en vol (pending[1])
      expect(repo.pending, hasLength(2));

      // Interruption concurrente de s0 (autre admin/onglet) pendant que la
      // page 2 est en vol : décrémente total et retire s0 immédiatement.
      await provider.stop(_stream('s0'));
      expect(provider.streams, hasLength(19));
      expect(provider.streams.any((s) => s.id == 's0'), isFalse);
      expect(provider.total, 99);

      // La page 2 (obsolète) se résout enfin : sans le compteur de version de
      // liste, elle ré-accumulerait par-dessus (`[..._streams, ...result.streams]`),
      // ressuscitant s0 et écrasant total à 100. Avec le fix, elle doit être
      // intégralement ignorée.
      repo.pending[1].complete(
        (streams: List.generate(20, (i) => _stream('s${i + 20}')), total: 100),
      );
      await more;

      expect(provider.streams, hasLength(19));
      expect(provider.streams.any((s) => s.id == 's0'), isFalse);
      expect(provider.total, 99);
      expect(provider.loadingMore, isFalse);
    });

    test(
        'stop() résolu pendant qu\'un load() est en vol : loading revient à '
        'false (pas de spinner figé — régression du fix users)', () async {
      final repo = _CompleterAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);

      // Premier load, complet : peuple la liste avec s0 (flux réel, visible,
      // que l'on va interrompre ci-dessous).
      final firstLoad = provider.load();
      repo.pending[0].complete((streams: [_stream('s0')], total: 1));
      await firstLoad;
      expect(provider.streams, hasLength(1));

      // Un second load part (ex. pull-to-refresh juste après avoir lancé une
      // interruption) — `reset: false` pour que s0 reste visible pendant que
      // ce load est en vol, comme un rechargement en tâche de fond.
      final loadFuture = provider.load(reset: false);
      expect(provider.loading, isTrue);
      expect(repo.pending, hasLength(2));

      // L'interruption de s0 se résout AVANT la réponse de ce second load.
      // `stop` ne doit PAS invalider ce `load()` : seul `loadMore` a besoin
      // d'être protégé contre une mutation de `_streams` pendant son vol (son
      // offset capturé serait faussé) — un `load()` recharge tout depuis
      // zéro, il n'a rien à protéger.
      await provider.stop(_stream('s0'));

      repo.pending[1].complete(
        (streams: List.generate(5, (i) => _stream('x$i')), total: 5),
      );
      await loadFuture;

      expect(provider.loading, isFalse);
      expect(provider.streams, hasLength(5)); // la réponse du load reste valide
    });
  });

  group('AdminStreamsProvider.loadMore', () {
    test('accumule les pages tant que streams.length < total', () async {
      final repo = _FakeAdminStreamsRepository(
        all: List.generate(45, (i) => _stream('s$i')),
      );
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.streams, hasLength(20));
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.streams, hasLength(40));
      expect(provider.hasMore, isTrue);

      await provider.loadMore();
      expect(provider.streams, hasLength(45));
      expect(provider.hasMore, isFalse);
    });

    test('offset += limit à chaque page', () async {
      final repo = _FakeAdminStreamsRepository(
        all: List.generate(45, (i) => _stream('s$i')),
      );
      final provider = AdminStreamsProvider(repo);
      await provider.load();

      await provider.loadMore();

      expect(repo.calls.last.offset, 20);
      expect(repo.calls.last.limit, 20);
    });

    test('ne fait rien si hasMore est faux (déjà tout chargé)', () async {
      final repo = _FakeAdminStreamsRepository(
        all: List.generate(3, (i) => _stream('s$i')),
      );
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.hasMore, isFalse);
      final callsBefore = repo.calls.length;

      await provider.loadMore();

      expect(repo.calls.length, callsBefore);
    });

    test('garde anti-double-appel : deux loadMore concurrents ne font qu\'une page',
        () async {
      final repo = _FakeAdminStreamsRepository(
        all: List.generate(45, (i) => _stream('s$i')),
      );
      final provider = AdminStreamsProvider(repo);
      await provider.load();

      final f1 = provider.loadMore();
      final f2 = provider.loadMore();
      await Future.wait([f1, f2]);

      expect(provider.streams, hasLength(40));
    });
  });

  group('AdminStreamsProvider.refresh', () {
    test('refresh() vide la liste puis recharge la première page (reset)',
        () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.streams, isNotEmpty);

      final future = provider.refresh();
      expect(provider.streams, isEmpty); // reset: true, comme load() par défaut
      await future;

      expect(provider.streams, hasLength(5));
      expect(repo.calls, hasLength(2));
      expect(repo.calls.last.offset, 0);
    });
  });

  group('AdminStreamsProvider.stop', () {
    test(
        'succès : retire le flux de la liste locale, décrémente total, '
        'retourne true', () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      final target = provider.streams.first;
      final totalBefore = provider.total;

      final stopped = await provider.stop(target);

      expect(stopped, isTrue);
      expect(repo.stopCalls, 1);
      expect(provider.streams.any((s) => s.id == target.id), isFalse);
      expect(provider.streams, hasLength(4));
      expect(provider.total, totalBefore - 1);
    });

    test(
        'flux déjà absent de la liste locale : no-op silencieux, retourne '
        'false, ne notifie pas', () async {
      final repo = _FakeAdminStreamsRepository();
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      final streamsBefore = provider.streams;

      var notified = false;
      provider.addListener(() => notified = true);

      // Le backend confirme la mutation (`stopStream` réussit), mais le flux
      // n'est plus dans `_streams` (déjà arrêté entre-temps par un autre
      // admin) : l'appelant ne doit pas afficher de toast succès.
      final stopped = await provider.stop(_stream('does-not-exist'));

      expect(stopped, isFalse);
      expect(repo.stopCalls, 1);
      expect(notified, isFalse);
      expect(provider.streams, same(streamsBefore));
    });

    test('total ne descend jamais sous 0 (garde)', () async {
      // Scénario contrived : le serveur renvoie total=0 alors que la page
      // contient un flux (désync) — le garde `if (_total > 0)` doit empêcher
      // `total` de passer négatif lors du `stop` qui suit.
      final repo = _FixedResponseRepository(streams: [_stream('s0')], total: 0);
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      expect(provider.total, 0);
      expect(provider.streams, hasLength(1));

      final stopped = await provider.stop(provider.streams.first);

      expect(stopped, isTrue);
      expect(provider.streams, isEmpty);
      expect(provider.total, 0); // pas -1
    });

    test('409 : relance l\'exception sans modifier la liste locale', () async {
      final repo = _FakeAdminStreamsRepository(
        mutationError: const ConflictException('stream already ended'),
      );
      final provider = AdminStreamsProvider(repo);
      await provider.load();
      final target = provider.streams.first;
      final countBefore = provider.streams.length;

      await expectLater(
        provider.stop(target),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'stream already ended',
          ),
        ),
      );
      expect(provider.streams, hasLength(countBefore));
    });
  });
}
