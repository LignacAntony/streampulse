import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/broadcaster/domain/entities/broadcaster_request.dart';
import 'package:streampulse/features/broadcaster/domain/repositories/broadcaster_repository.dart';
import 'package:streampulse/features/broadcaster/presentation/providers/broadcaster_controller.dart';

BroadcasterRequest _request(BroadcasterRequestStatus status) => BroadcasterRequest(
      id: '1',
      status: status,
      message: 'hello',
      reviewNote: '',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

class _FakeRepository implements BroadcasterRepository {
  _FakeRepository({this.existing, this.error, this.loadError});

  final BroadcasterRequest? existing;
  final Object? error;
  final Object? loadError;
  int createCalls = 0;
  String? lastMessage;

  @override
  Future<BroadcasterRequest?> getMyRequest() async {
    if (loadError != null) throw loadError!;
    return existing;
  }

  @override
  Future<BroadcasterRequest> requestBroadcaster({String message = ''}) async {
    createCalls++;
    lastMessage = message;
    if (error != null) throw error!;
    return _request(BroadcasterRequestStatus.pending);
  }
}

void main() {
  group('BroadcasterController.load', () {
    test('aucune demande existante : request null, loadFailed faux', () async {
      final controller = BroadcasterController(_FakeRepository());

      await controller.load();

      expect(controller.request, isNull);
      expect(controller.hasPendingRequest, isFalse);
      expect(controller.loadFailed, isFalse);
    });

    test('demande en attente : hasPendingRequest vrai', () async {
      final controller = BroadcasterController(
        _FakeRepository(existing: _request(BroadcasterRequestStatus.pending)),
      );

      await controller.load();

      expect(controller.hasPendingRequest, isTrue);
    });

    test('échec réseau : expose loadFailed sans relancer', () async {
      final controller = BroadcasterController(
        _FakeRepository(loadError: const NetworkException()),
      );

      await expectLater(controller.load(), completes);

      expect(controller.loadFailed, isTrue);
      expect(controller.request, isNull);
    });
  });

  group('BroadcasterController.submit', () {
    test('succès : stocke la demande créée et passe en pending', () async {
      final repo = _FakeRepository();
      final controller = BroadcasterController(repo);

      await controller.submit('je veux diffuser');

      expect(repo.createCalls, 1);
      expect(repo.lastMessage, 'je veux diffuser');
      expect(controller.request?.isPending, isTrue);
      expect(controller.isSubmitting, isFalse);
    });

    test('conflit : relaie l\'exception et réinitialise isSubmitting', () async {
      final controller = BroadcasterController(
        _FakeRepository(error: const ConflictException('Demande déjà en cours')),
      );

      await expectLater(
        controller.submit('x'),
        throwsA(isA<ConflictException>()),
      );
      expect(controller.isSubmitting, isFalse);
    });
  });
}
