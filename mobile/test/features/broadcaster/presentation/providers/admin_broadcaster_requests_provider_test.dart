import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/broadcaster/domain/entities/admin_broadcaster_request.dart';
import 'package:streampulse/features/broadcaster/domain/entities/broadcaster_request.dart';
import 'package:streampulse/features/broadcaster/domain/repositories/admin_broadcaster_repository.dart';
import 'package:streampulse/features/broadcaster/presentation/providers/admin_broadcaster_requests_provider.dart';

AdminBroadcasterRequest _request(
  String id, {
  BroadcasterRequestStatus status = BroadcasterRequestStatus.pending,
}) =>
    AdminBroadcasterRequest(
      id: id,
      status: status,
      message: 'Je veux diffuser',
      reviewNote: '',
      userId: 'u-$id',
      email: '$id@mail.dev',
      username: 'user-$id',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

class _FakeRepo implements AdminBroadcasterRepository {
  List<AdminBroadcasterRequest> requests = const [];
  BroadcasterRequestStatus? lastStatusFilter;
  Object? approveError;

  /// Si posé, `approve` attend ce completer : permet de tester la garde
  /// anti-double-envoi pendant qu'un appel est en vol.
  Completer<void>? approveGate;

  int listCalls = 0;
  int approveCalls = 0;
  int rejectCalls = 0;

  @override
  Future<List<AdminBroadcasterRequest>> list({
    BroadcasterRequestStatus? status,
  }) async {
    listCalls++;
    lastStatusFilter = status;
    return requests
        .where((r) => status == null || r.status == status)
        .toList();
  }

  @override
  Future<void> approve(String id, {String? note}) async {
    approveCalls++;
    if (approveGate != null) await approveGate!.future;
    if (approveError != null) throw approveError!;
  }

  @override
  Future<void> reject(String id, {String? note}) async {
    rejectCalls++;
  }
}

void main() {
  group('AdminBroadcasterRequestsProvider', () {
    test('load : filtre "pending" par défaut', () async {
      final repo = _FakeRepo()
        ..requests = [
          _request('a'),
          _request('b', status: BroadcasterRequestStatus.approved),
        ];
      final provider = AdminBroadcasterRequestsProvider(repo);

      await provider.load();

      expect(repo.lastStatusFilter, BroadcasterRequestStatus.pending);
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.id, 'a');
      expect(provider.error, isNull);
    });

    test('erreur réseau : error + isNetworkError', () async {
      final provider = AdminBroadcasterRequestsProvider(_ThrowingRepo());

      await provider.load();

      expect(provider.error, isNotNull);
      expect(provider.isNetworkError, isTrue);
    });

    test('approve : MAJ locale, pas de rechargement réseau (filtre pending)',
        () async {
      final repo = _FakeRepo()..requests = [_request('a')];
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();

      await provider.approve(provider.requests.single);

      expect(repo.approveCalls, 1);
      expect(repo.listCalls, 1); // aucun reload : MAJ locale uniquement
      expect(provider.requests, isEmpty); // approuvée → hors filtre pending
    });

    test('approve : sous filtre « Toutes », la carte reste avec le nouveau statut',
        () async {
      final repo = _FakeRepo()..requests = [_request('a')];
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.setStatusFilter(null); // Toutes

      await provider.approve(provider.requests.single);

      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.status,
          BroadcasterRequestStatus.approved);
    });

    test('approve en échec : relaie l\'exception, liste inchangée, pas de reload',
        () async {
      final repo = _FakeRepo()
        ..requests = [_request('a')]
        ..approveError = const ConflictException('Demande déjà traitée');
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();

      await expectLater(
        provider.approve(provider.requests.single),
        throwsA(isA<ConflictException>()),
      );
      expect(repo.listCalls, 1); // pas de reload trompeur
      expect(provider.requests, hasLength(1)); // carte conservée
      expect(provider.isMutating('a'), isFalse); // libéré même sur échec
    });

    test('garde anti-double-envoi : 2e approve pendant le 1er en vol = no-op',
        () async {
      final gate = Completer<void>();
      final repo = _FakeRepo()
        ..requests = [_request('a')]
        ..approveGate = gate;
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();
      final request = provider.requests.single;

      final first = provider.approve(request); // en vol (bloqué sur le gate)
      expect(provider.isMutating('a'), isTrue);
      await provider.approve(request); // doit être ignoré immédiatement
      expect(repo.approveCalls, 1); // un seul POST

      gate.complete();
      await first;
      expect(repo.approveCalls, 1);
      expect(provider.isMutating('a'), isFalse);
    });

    test('setStatusFilter change le filtre (enum) et recharge', () async {
      final repo = _FakeRepo()
        ..requests = [_request('b', status: BroadcasterRequestStatus.approved)];
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();

      await provider.setStatusFilter(BroadcasterRequestStatus.approved);

      expect(provider.statusFilter, BroadcasterRequestStatus.approved);
      expect(repo.lastStatusFilter, BroadcasterRequestStatus.approved);
      expect(provider.requests.single.id, 'b');
    });
  });
}

/// Fait échouer `list` en réseau (mutations non sollicitées ici).
class _ThrowingRepo implements AdminBroadcasterRepository {
  @override
  Future<List<AdminBroadcasterRequest>> list({
    BroadcasterRequestStatus? status,
  }) async =>
      throw const NetworkException();

  @override
  Future<void> approve(String id, {String? note}) async {}

  @override
  Future<void> reject(String id, {String? note}) async {}
}
