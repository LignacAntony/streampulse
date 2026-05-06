import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

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
