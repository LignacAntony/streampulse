import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

class ResetPasswordController extends AsyncNotifier<void> {
  late final AuthRepository _repo = ref.read(authRepositoryProvider);

  @override
  Future<void> build() async {}

  Future<void> submit({
    required String token,
    required String newPassword,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.resetPassword(token: token, newPassword: newPassword),
    );
  }
}

final resetPasswordControllerProvider =
    AsyncNotifierProvider<ResetPasswordController, void>(
  ResetPasswordController.new,
);
