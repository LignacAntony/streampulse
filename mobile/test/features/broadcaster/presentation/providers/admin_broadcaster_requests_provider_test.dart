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
  String? lastStatusFilter;
  Object? approveError;

  int listCalls = 0;
  int approveCalls = 0;
  int rejectCalls = 0;

  @override
  Future<List<AdminBroadcasterRequest>> list({String? status}) async {
    listCalls++;
    lastStatusFilter = status;
    return requests
        .where((r) => status == null || r.status.name == status)
        .toList();
  }

  @override
  Future<void> approve(String id, {String? note}) async {
    approveCalls++;
    if (approveError != null) throw approveError!;
    requests = requests
        .map((r) => r.id == id
            ? _request(id, status: BroadcasterRequestStatus.approved)
            : r)
        .toList();
  }

  @override
  Future<void> reject(String id, {String? note}) async {
    rejectCalls++;
    requests = requests
        .map((r) => r.id == id
            ? _request(id, status: BroadcasterRequestStatus.rejected)
            : r)
        .toList();
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

      expect(repo.lastStatusFilter, 'pending');
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.id, 'a');
      expect(provider.error, isNull);
    });

    test('erreur réseau : error + isNetworkError', () async {
      final repo = _FakeRepo();
      final provider = AdminBroadcasterRequestsProvider(_ThrowingRepo(repo));

      await provider.load();

      expect(provider.error, isNotNull);
      expect(provider.isNetworkError, isTrue);
    });

    test('approve puis recharge : la demande traitée quitte le filtre pending',
        () async {
      final repo = _FakeRepo()..requests = [_request('a')];
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();

      await provider.approve(provider.requests.single);

      expect(repo.approveCalls, 1);
      expect(repo.listCalls, 2); // load initial + reload après mutation
      expect(provider.requests, isEmpty); // approuvée, hors filtre pending
    });

    test('approve en conflit : relaie l\'exception mais recharge quand même',
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
      expect(repo.listCalls, 2); // le finally recharge malgré l'échec
    });

    test('setStatusFilter change le filtre et recharge', () async {
      final repo = _FakeRepo()
        ..requests = [_request('b', status: BroadcasterRequestStatus.approved)];
      final provider = AdminBroadcasterRequestsProvider(repo);
      await provider.load();

      await provider.setStatusFilter('approved');

      expect(provider.statusFilter, 'approved');
      expect(repo.lastStatusFilter, 'approved');
      expect(provider.requests.single.id, 'b');
    });
  });
}

/// Enrobe le fake pour faire échouer `list` en réseau.
class _ThrowingRepo implements AdminBroadcasterRepository {
  _ThrowingRepo(this._inner);
  final AdminBroadcasterRepository _inner;

  @override
  Future<List<AdminBroadcasterRequest>> list({String? status}) async =>
      throw const NetworkException();

  @override
  Future<void> approve(String id, {String? note}) =>
      _inner.approve(id, note: note);

  @override
  Future<void> reject(String id, {String? note}) =>
      _inner.reject(id, note: note);
}
