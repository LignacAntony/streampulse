import '../../../../core/auth/google_auth_service.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../domain/entities/token_pair.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../mappers/auth_dto_mappers.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._remote, this._secureStorage, this._googleAuth);

  final AuthRemoteDataSource _remote;
  final SecureStorage _secureStorage;
  final GoogleAuthService _googleAuth;

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

  @override
  Future<TokenPair> loginWithGoogle() async {
    final idToken = await _googleAuth.signIn();
    final model = await _remote.loginWithGoogle(idToken: idToken);
    await _secureStorage.saveAccessToken(model.accessToken);
    await _secureStorage.saveRefreshToken(model.refreshToken);
    return model.toEntity();
  }

  @override
  Future<void> requestPasswordReset({required String email}) =>
      _remote.requestPasswordReset(email: email);

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) => _remote.resetPassword(token: token, newPassword: newPassword);

  @override
  Future<void> logout() async {
    final refresh = await _secureStorage.getRefreshToken();
    if (refresh != null) {
      try {
        await _remote.logout(refreshToken: refresh);
      } catch (_) {}
    }
    await _secureStorage.clearTokens();
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    await _remote.deleteAccount(password: password);
    await _secureStorage.clearTokens();
  }
}
