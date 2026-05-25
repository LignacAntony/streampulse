import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

class ForgotPasswordController extends AsyncNotifier<void> {
  late final AuthRepository _repo = ref.read(authRepositoryProvider);

  @override
  Future<void> build() async {}

  Future<void> submit({required String email}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _repo.requestPasswordReset(email: email),
    );
  }
}

final forgotPasswordControllerProvider =
    AsyncNotifierProvider<ForgotPasswordController, void>(
  ForgotPasswordController.new,
);
