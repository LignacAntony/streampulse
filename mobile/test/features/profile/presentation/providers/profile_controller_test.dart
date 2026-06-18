import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/profile/domain/entities/user_profile.dart';
import 'package:streampulse/features/profile/domain/repositories/profile_repository.dart';
import 'package:streampulse/features/profile/presentation/providers/profile_controller.dart';

UserProfile _profile() => UserProfile(
      id: '1',
      email: 'user1@streampulse.dev',
      role: 'user',
      pseudo: 'user1',
      bio: '',
      avatarUrl: null,
      theme: 'dark',
      notificationsEnabled: true,
      audioQuality: 'normal',
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _FakeRepository implements ProfileRepository {
  _FakeRepository({this.profile, this.error});

  final UserProfile? profile;
  final Object? error;

  @override
  Future<UserProfile> getMe() async {
    if (error != null) throw error!;
    return profile!;
  }

  @override
  Future<UserProfile> update(UserProfile profile) async => profile;
}

void main() {
  group('ProfileController.load', () {
    test('succès : expose le profil et loadFailed reste faux', () async {
      final controller = ProfileController(_FakeRepository(profile: _profile()));

      await controller.load();

      expect(controller.profile, isNotNull);
      expect(controller.loadFailed, isFalse);
      expect(controller.isLoading, isFalse);
    });

    test('échec : ne relance pas et expose loadFailed', () async {
      final controller =
          ProfileController(_FakeRepository(error: const NetworkException()));

      await expectLater(controller.load(), completes);

      expect(controller.profile, isNull);
      expect(controller.loadFailed, isTrue);
      expect(controller.isLoading, isFalse);
    });

    test('un load réussi après un échec réinitialise loadFailed', () async {
      final failing = ProfileController(
        _FakeRepository(error: const NetworkException()),
      );
      await failing.load();
      expect(failing.loadFailed, isTrue);

      final ok = ProfileController(_FakeRepository(profile: _profile()));
      await ok.load();
      expect(ok.loadFailed, isFalse);
      expect(ok.profile, isNotNull);
    });
  });
}
