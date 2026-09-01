import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/auth/data/datasources/auth_remote_data_source.dart';

/// Verrouille le contrat entre le client généré (`AuthApi`) et le mapping
/// d'erreurs de `AuthRemoteDataSource`.
///
/// Les tests du repository utilisent un faux datasource qui court-circuite ce
/// mapping ; ici on fait passer de vraies réponses HTTP à travers un vrai `Dio`
/// + le vrai `AuthApi`, via `DioAdapter`. C'est le seam que la migration OpenAPI
/// a rendu fragile : si la forme de `response.data` change sur un non-2xx, le
/// mapping casse — ces tests l'attrapent.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AuthRemoteDataSource dataSource;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    dataSource = AuthRemoteDataSource(AuthApi(dio), dio);
  });

  group('register', () {
    test('409 -> DuplicateAccountException avec le message serveur', () async {
      adapter.onPost(
        '/api/auth/register',
        (server) => server.reply(409, {
          'error': {'code': 'conflict', 'message': 'Cet email est déjà pris'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        dataSource.register(
          email: 'alice@example.com',
          username: 'alice',
          password: 'hunter2hunter',
        ),
        throwsA(
          isA<DuplicateAccountException>().having(
            (e) => e.message,
            'message',
            'Cet email est déjà pris',
          ),
        ),
      );
    });

    test('400 -> ValidationException avec le message serveur', () async {
      adapter.onPost(
        '/api/auth/register',
        (server) => server.reply(400, {
          'error': {'code': 'invalid_argument', 'message': 'invalid email'},
        }),
        data: Matchers.any,
      );

      await expectLater(
        dataSource.register(
          email: 'not-an-email',
          username: 'alice',
          password: 'hunter2hunter',
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            'invalid email',
          ),
        ),
      );
    });
  });

  group('login', () {
    test(
      '401 -> AuthException au message hardcodé (pas de leak du message serveur)',
      () async {
        adapter.onPost(
          '/api/auth/login',
          (server) => server.reply(401, {
            // Message technique volontairement « sensible » : il ne doit jamais
            // remonter dans l'UI (cf. ADR 009 §4).
            'error': {'code': 'unauthorized', 'message': 'bcrypt cost too low'},
          }),
          data: Matchers.any,
        );

        await expectLater(
          dataSource.login(email: 'alice@example.com', password: 'wrongpass'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Email ou mot de passe incorrect',
            ),
          ),
        );
      },
    );
  });
}
