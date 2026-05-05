import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import 'auth_providers.dart';

// AsyncNotifier qui pilote le flux d'inscription.
//
// Cycle de vie :
//   build()   → AsyncData(null)            : état initial, formulaire prêt
//   submit()  → AsyncLoading                : requête HTTP en vol
//             → AsyncData(User)             : compte créé
//             → AsyncError(exception, …)    : erreur métier ou réseau
//
// Le screen écoute l'état pour afficher spinner / SnackBar / navigation.
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
