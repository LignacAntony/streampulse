import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

class ForgotPasswordController extends AsyncNotifier<bool> {
  late final AuthRepository _repo = ref.read(authRepositoryProvider);

  @override
  Future<bool> build() async => false; // false = pas encore envoyé

  Future<void> submit({required String email}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await _repo.requestPasswordReset(email: email);
      return true;
    });
  }
}

final forgotPasswordControllerProvider =
    AsyncNotifierProvider<ForgotPasswordController, bool>(
  ForgotPasswordController.new,
);
