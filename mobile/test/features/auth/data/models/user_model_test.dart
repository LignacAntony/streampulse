import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/auth/data/models/user_model.dart';

void main() {
  group('UserModel.fromJson', () {
    test('parse une réponse 201 du backend', () {
      final model = UserModel.fromJson({
        'id': '11111111-2222-3333-4444-555555555555',
        'email': 'alice@example.com',
        'username': 'alice',
        'role': 'user',
        'created_at': '2026-01-02T03:04:05Z',
      });

      expect(model.id, '11111111-2222-3333-4444-555555555555');
      expect(model.email, 'alice@example.com');
      expect(model.username, 'alice');
      expect(model.role, 'user');
      expect(model.createdAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('toEntity propage tous les champs', () {
      final model = UserModel.fromJson({
        'id': 'abc',
        'email': 'a@b.co',
        'username': 'a',
        'role': 'broadcaster',
        'created_at': '2026-05-04T10:00:00Z',
      });

      final user = model.toEntity();

      expect(user.id, 'abc');
      expect(user.email, 'a@b.co');
      expect(user.username, 'a');
      expect(user.role, 'broadcaster');
      expect(user.createdAt, DateTime.utc(2026, 5, 4, 10));
    });
  });
}
