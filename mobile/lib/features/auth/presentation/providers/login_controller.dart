import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/token_pair.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

class LoginController extends AsyncNotifier<TokenPair?> {
  late final AuthRepository _repository = ref.read(authRepositoryProvider);

  @override
  Future<TokenPair?> build() async => null;

  Future<void> submit({
    required String email,
    required String password,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return _repository.login(email: email, password: password);
    });
  }
}

final loginControllerProvider =
    AsyncNotifierProvider<LoginController, TokenPair?>(LoginController.new);
