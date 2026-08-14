import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:streampulse_api/streampulse_api.dart';

import 'package:streampulse/core/errors/exceptions.dart';
import 'package:streampulse/features/admin/data/mappers/admin_dto_mappers.dart';
import 'package:streampulse/features/admin/data/repositories/admin_repository_impl.dart';

/// `AdminRepositoryImpl` n'a pas de couche `datasource` séparée (cf. brief
/// STR-195) : le mapping DioException -> exception typée vit directement
/// dedans. On fait donc passer de vraies réponses HTTP à travers un vrai
/// `Dio` + le vrai `AdminApi` généré, via `DioAdapter` — même style que
/// `auth_remote_data_source_test.dart`.
void main() {
  late Dio dio;
  late DioAdapter adapter;
  late AdminRepositoryImpl repository;

  setUp(() {
    dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
    adapter = DioAdapter(dio: dio);
    repository = AdminRepositoryImpl(AdminApi(dio));
  });

  group('AdminUserResponseMapper', () {
    test('convertit tous les champs vers AdminUser', () {
      final dto = AdminUserResponse(
        id: 'u-1',
        email: 'alice@example.com',
        username: 'alice',
        role: AdminUserResponseRoleEnum.broadcaster,
        isActive: true,
        createdAt: DateTime.parse('2026-01-02T03:04:05.000Z'),
      );

      final entity = dto.toEntity();

      expect(entity.id, 'u-1');
      expect(entity.email, 'alice@example.com');
      expect(entity.username, 'alice');
      expect(entity.role, 'broadcaster');
      expect(entity.isActive, isTrue);
      expect(entity.createdAt, DateTime.parse('2026-01-02T03:04:05.000Z'));
    });
  });

  group('AdminRepositoryImpl.listUsers', () {
    test(
      'succès : mappe la liste + le total et transmet les filtres',
      () async {
        adapter.onGet(
          '/api/admin/users',
          (server) => server.reply(200, {
            'users': [
              {
                'id': 'u-1',
                'email': 'alice@example.com',
                'username': 'alice',
                'role': 'user',
                'is_active': true,
                'created_at': '2026-01-02T03:04:05.000Z',
              },
            ],
            'total': 42,
          }),
          queryParameters: {
            'search': 'ali',
            'role': 'user',
            'status': 'active',
            'limit': 10,
            'offset': 5,
          },
        );

        final result = await repository.listUsers(
          search: 'ali',
          role: 'user',
          status: 'active',
          limit: 10,
          offset: 5,
        );

        expect(result.total, 42);
        expect(result.users, hasLength(1));
        expect(result.users.single.id, 'u-1');
        expect(result.users.single.username, 'alice');
        expect(result.users.single.isActive, isTrue);
      },
    );
  });

  group('AdminRepositoryImpl.setUserActive', () {
    test('succès : retourne l\'utilisateur mis à jour', () async {
      adapter.onPatch(
        '/api/admin/users/u-1',
        (server) => server.reply(200, {
          'id': 'u-1',
          'email': 'alice@example.com',
          'username': 'alice',
          'role': 'user',
          'is_active': false,
          'created_at': '2026-01-02T03:04:05.000Z',
        }),
        data: Matchers.any,
      );

      final user = await repository.setUserActive('u-1', false);

      expect(user.id, 'u-1');
      expect(user.isActive, isFalse);
    });

    test('409 -> ConflictException avec le message serveur', () async {
      adapter.onPatch(
        '/api/admin/users/u-1',
        (server) => server.reply(409, {
          'error': {
            'code': 'conflict',
            'message': 'cannot deactivate the last active admin',
          },
        }),
        data: Matchers.any,
      );

      await expectLater(
        repository.setUserActive('u-1', false),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'cannot deactivate the last active admin',
          ),
        ),
      );
    });
  });

  group('AdminRepositoryImpl.deleteUser', () {
    test('succès : supprime le compte', () async {
      adapter.onDelete(
        '/api/admin/users/u-1',
        (server) => server.reply(204, null),
      );

      await expectLater(repository.deleteUser('u-1'), completes);
    });

    test('409 -> ConflictException avec le message serveur', () async {
      adapter.onDelete(
        '/api/admin/users/u-1',
        (server) => server.reply(409, {
          'error': {'code': 'conflict', 'message': 'cannot delete your own account'},
        }),
      );

      await expectLater(
        repository.deleteUser('u-1'),
        throwsA(
          isA<ConflictException>().having(
            (e) => e.message,
            'message',
            'cannot delete your own account',
          ),
        ),
      );
    });
  });
}
