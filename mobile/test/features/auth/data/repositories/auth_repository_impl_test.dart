import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse_api/streampulse_api.dart';
import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/core/storage/secure_storage.dart';
import 'package:streampulse/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:streampulse/features/auth/data/repositories/auth_repository_impl.dart';

class _FakeRemote implements AuthRemoteDataSource {
  _FakeRemote({this.model, this.tokenPair, this.error});

  final UserResponse? model;
  final TokenPairResponse? tokenPair;
  final Object? error;
  int calls = 0;
  String? lastEmail;
  String? lastUsername;
  String? lastPassword;

  @override
  Future<UserResponse> register({
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
  Future<TokenPairResponse> login({
    required String email,
    required String password,
  }) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    if (error != null) throw error!;
    return tokenPair!;
  }

  int logoutCalls = 0;
  String? lastLogoutRefreshToken;

  @override
  Future<void> logout({required String refreshToken}) async {
    logoutCalls++;
    lastLogoutRefreshToken = refreshToken;
    if (error != null) throw error!;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    if (error != null) throw error!;
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    if (error != null) throw error!;
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
    test('convertit le UserResponse en User et propage les champs', () async {
      final remote = _FakeRemote(
        model: UserResponse(
          id: 'abc',
          email: 'alice@example.com',
          username: 'alice',
          role: 'user',
          createdAt: DateTime.parse('2026-01-02T03:04:05Z'),
        ),
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
      final remote = _FakeRemote(error: const DuplicateAccountException());
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
    test(
      'persiste les tokens via SecureStorage et retourne TokenPair',
      () async {
        final remote = _FakeRemote(
          tokenPair: TokenPairResponse(
            accessToken: 'access-xyz',
            refreshToken: 'refresh-xyz',
          ),
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
      },
    );

    test('propage AuthException en cas de 401 et ne persiste rien', () async {
      final remote = _FakeRemote(
        error: const AuthException('Email ou mot de passe incorrect'),
      );
      final storage = _FakeSecureStorage();
      final repo = AuthRepositoryImpl(remote, storage);

      await expectLater(
        () => repo.login(email: 'alice@example.com', password: 'wrong'),
        throwsA(isA<AuthException>()),
      );
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    });
  });

  group('AuthRepositoryImpl.logout', () {
    test(
      'appelle le serveur avec le refresh token et purge le stockage',
      () async {
        final remote = _FakeRemote();
        final storage = _FakeSecureStorage()
          ..accessToken = 'access-xyz'
          ..refreshToken = 'refresh-xyz';
        final repo = AuthRepositoryImpl(remote, storage);

        await repo.logout();

        expect(remote.logoutCalls, 1);
        expect(remote.lastLogoutRefreshToken, 'refresh-xyz');
        expect(storage.accessToken, isNull);
        expect(storage.refreshToken, isNull);
      },
    );

    test('purge quand même le stockage si le serveur échoue', () async {
      final remote = _FakeRemote(error: const NetworkException());
      final storage = _FakeSecureStorage()
        ..accessToken = 'access-xyz'
        ..refreshToken = 'refresh-xyz';
      final repo = AuthRepositoryImpl(remote, storage);

      await repo.logout();

      expect(remote.logoutCalls, 1);
      expect(storage.accessToken, isNull);
      expect(storage.refreshToken, isNull);
    });

    test(
      'ne tente pas le serveur si aucun refresh token, mais purge',
      () async {
        final remote = _FakeRemote();
        final storage = _FakeSecureStorage()..accessToken = 'orphan-access';
        final repo = AuthRepositoryImpl(remote, storage);

        await repo.logout();

        expect(remote.logoutCalls, 0);
        expect(storage.accessToken, isNull);
        expect(storage.refreshToken, isNull);
      },
    );
  });
}
