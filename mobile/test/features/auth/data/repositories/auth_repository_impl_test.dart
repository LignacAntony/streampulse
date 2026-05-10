import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:streampulse/features/auth/data/models/token_pair_model.dart';
import 'package:streampulse/features/auth/data/models/user_model.dart';
import 'package:streampulse/features/auth/data/repositories/auth_repository_impl.dart';

class _FakeRemote implements AuthRemoteDataSource {
  _FakeRemote({this.model, this.tokenPair, this.error});

  final UserModel? model;
  final TokenPairModel? tokenPair;
  final Object? error;
  int calls = 0;
  String? lastEmail;
  String? lastUsername;
  String? lastPassword;

  @override
  Future<UserModel> register({
    required String email,
    required String username,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastUsername = username;
    lastPassword = password;
    if (error != null) throw error!;
    return model!;
  }

  @override
  Future<TokenPairModel> login({
    required String email,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    if (error != null) throw error!;
    return tokenPair!;
  }
}

class _FakeSecureStorage implements SecureStorage {
  String? accessToken;
  String? refreshToken;

  @override
  Future<void> saveAccessToken(String token) async => accessToken = token;

  @override
  Future<void> saveRefreshToken(String token) async => refreshToken = token;

  @override
  Future<String?> getAccessToken() async => accessToken;

  @override
  Future<String?> getRefreshToken() async => refreshToken;

  @override
  Future<void> clearTokens() async {
    accessToken = null;
    refreshToken = null;
  }
}

void main() {
  group('AuthRepositoryImpl.register', () {
    test('convertit le UserModel en User et propage les champs', () async {
      final remote = _FakeRemote(
        model: UserModel.fromJson({
          'id': 'abc',
          'email': 'alice@example.com',
          'username': 'alice',
          'role': 'user',
          'created_at': '2026-01-02T03:04:05Z',
        }),
      );
      final repo = AuthRepositoryImpl(remote, _FakeSecureStorage());

      final user = await repo.register(
        email: 'alice@example.com',
        username: 'alice',
        password: 'hunter2hunter',
      );

      expect(remote.calls, 1);
      expect(remote.lastEmail, 'alice@example.com');
      expect(remote.lastUsername, 'alice');
      expect(remote.lastPassword, 'hunter2hunter');
      expect(user.id, 'abc');
      expect(user.email, 'alice@example.com');
      expect(user.username, 'alice');
      expect(user.role, 'user');
    });

    test('propage DuplicateAccountException en cas de 409', () async {
      final remote = _FakeRemote(
        error: const DuplicateAccountException(),
      );
      final repo = AuthRepositoryImpl(remote, _FakeSecureStorage());

      expect(
        () => repo.register(
          email: 'alice@example.com',
          username: 'alice',
          password: 'hunter2hunter',
        ),
        throwsA(isA<DuplicateAccountException>()),
      );
    });

    test('propage ValidationException en cas de 400', () async {
      final remote = _FakeRemote(
        error: const ValidationException('invalid email'),
      );
      final repo = AuthRepositoryImpl(remote, _FakeSecureStorage());

      expect(
        () => repo.register(
          email: 'invalid',
          username: 'alice',
          password: 'hunter2hunter',
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('AuthRepositoryImpl.login', () {
    test('persiste les tokens via SecureStorage et retourne TokenPair',
        () async {
      final remote = _FakeRemote(
        tokenPair: TokenPairModel.fromJson({
          'access_token': 'access-xyz',
          'refresh_token': 'refresh-xyz',
        }),
      );
      final storage = _FakeSecureStorage();
      final repo = AuthRepositoryImpl(remote, storage);

      final pair = await repo.login(
        email: 'alice@example.com',
        password: 'hunter2hunter',
      );

      expect(remote.calls, 1);
      expect(remote.lastEmail, 'alice@example.com');
      expect(remote.lastPassword, 'hunter2hunter');
      expect(pair.accessToken, 'access-xyz');
      expect(pair.refreshToken, 'refresh-xyz');
      expect(storage.accessToken, 'access-xyz');
      expect(storage.refreshToken, 'refresh-xyz');
    });

    test('propage AuthException en cas de 401 et ne persiste rien', () async {
      final remote = _FakeRemote(
        error: const AuthException('Email ou mot de passe incorrect'),
      );
      final storage = _FakeSecureStorage();
      final repo = AuthRepositoryImpl(remote, storage);

      await expectLater(
        () => repo.login(
          email: 'alice@example.com',
          password: 'wrong',
        ),
        throwsA(isA<AuthException>()),
      );
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    });
  });
}
