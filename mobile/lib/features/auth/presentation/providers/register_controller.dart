import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

class RegisterController extends AsyncNotifier<User?> {
  late final AuthRepository _repository = ref.read(authRepositoryProvider);

  @override
  Future<User?> build() async => null;

  Future<void> submit({
    required String email,
    required String username,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _repository.register(
        email: email,
        username: username,
        password: password,
      );
    });
  }
}

final registerControllerProvider =
    AsyncNotifierProvider<RegisterController, User?>(RegisterController.new);
