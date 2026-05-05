import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

// Implémentation concrète du repository : délègue le transport au
// remote data source et convertit les modèles en entités pures.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote);

  final AuthRemoteDataSource _remote;

  @override
  Future<User> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final model = await _remote.register(
      email: email,
      username: username,
      password: password,
    );
    return model.toEntity();
  }
}
