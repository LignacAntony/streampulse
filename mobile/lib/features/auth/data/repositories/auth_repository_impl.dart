import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/token_pair.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._secureStorage);

  final AuthRemoteDataSource _remote;
  final SecureStorage _secureStorage;

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

  @override
  Future<TokenPair> login({
    required String email,
    required String password,
  }) async {
    final model = await _remote.login(email: email, password: password);
    await _secureStorage.saveAccessToken(model.accessToken);
    await _secureStorage.saveRefreshToken(model.refreshToken);
    return model.toEntity();
  }
}
