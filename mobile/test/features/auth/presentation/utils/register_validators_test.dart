import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/auth/presentation/utils/register_validators.dart';

void main() {
  group('RegisterValidators.email', () {
    test('accepte une adresse simple', () {
      expect(RegisterValidators.email('alice@example.com'), isNull);
    });

    test('rejette null, vide et espace seul', () {
      expect(RegisterValidators.email(null), 'Email requis');
      expect(RegisterValidators.email(''), 'Email requis');
      expect(RegisterValidators.email('   '), 'Email requis');
    });

    test('rejette les formats invalides', () {
      for (final raw in [
        'plain',
        'no-at-sign',
        'alice@',
        '@example.com',
        'alice example.com',
        'alice@example',
      ]) {
        expect(
          RegisterValidators.email(raw),
          'Email invalide',
          reason: 'cas: $raw',
        );
      }
    });
  });

  group('RegisterValidators.username', () {
    test('accepte un pseudo alphanumérique avec underscore', () {
      expect(RegisterValidators.username('alice_42'), isNull);
      expect(RegisterValidators.username('Bob'), isNull);
    });

    test('rejette null et vide', () {
      expect(RegisterValidators.username(null), 'Pseudo requis');
      expect(RegisterValidators.username(''), 'Pseudo requis');
    });

    test('rejette si trop court', () {
      expect(
        RegisterValidators.username('ab'),
        contains('${RegisterValidators.minUsernameLength}'),
      );
    });

    test('rejette si trop long', () {
      final tooLong = 'a' * (RegisterValidators.maxUsernameLength + 1);
      expect(
        RegisterValidators.username(tooLong),
        contains('${RegisterValidators.maxUsernameLength}'),
      );
    });

    test('rejette les caractères non autorisés', () {
      for (final raw in ['with space', 'with-dash', 'wîth-accent', 'a.b']) {
        expect(
          RegisterValidators.username(raw),
          'Lettres, chiffres et _ uniquement',
          reason: 'cas: $raw',
        );
      }
    });
  });

  group('RegisterValidators.password', () {
    test('accepte un mot de passe ≥ 8 caractères', () {
      expect(RegisterValidators.password('hunter2hunter'), isNull);
    });

    test('rejette null et vide', () {
      expect(RegisterValidators.password(null), 'Mot de passe requis');
      expect(RegisterValidators.password(''), 'Mot de passe requis');
    });

    test('rejette si < 8 caractères', () {
      expect(
        RegisterValidators.password('short'),
        contains('${RegisterValidators.minPasswordLength}'),
      );
    });

    test('rejette si > 72 caractères (limite bcrypt)', () {
      final tooLong = 'x' * (RegisterValidators.maxPasswordLength + 1);
      expect(
        RegisterValidators.password(tooLong),
        contains('${RegisterValidators.maxPasswordLength}'),
      );
    });
  });

  group('RegisterValidators.confirmPassword', () {
    test('accepte une valeur identique', () {
      expect(
        RegisterValidators.confirmPassword('hunter2hunter', 'hunter2hunter'),
        isNull,
      );
    });

    test('rejette null et vide', () {
      expect(
        RegisterValidators.confirmPassword(null, 'hunter2hunter'),
        'Confirmation requise',
      );
      expect(
        RegisterValidators.confirmPassword('', 'hunter2hunter'),
        'Confirmation requise',
      );
    });

    test('rejette si différent du mot de passe', () {
      expect(
        RegisterValidators.confirmPassword('foo', 'bar'),
        'Les mots de passe ne correspondent pas',
      );
    });
  });

  group('RegisterValidators.passwordStrength', () {
    test('null ou vide → 0', () {
      expect(RegisterValidators.passwordStrength(null), 0);
      expect(RegisterValidators.passwordStrength(''), 0);
    });

    test('court (< 8) → 0', () {
      expect(RegisterValidators.passwordStrength('abc'), 0);
    });

    test('lettres minuscules longueur 8 → 1 (longueur seule)', () {
      expect(RegisterValidators.passwordStrength('abcdefgh'), 1);
    });

    test('avec chiffre → +1', () {
      expect(RegisterValidators.passwordStrength('abcdefg1'), 2);
    });

    test('avec majuscule + chiffre → +2', () {
      expect(RegisterValidators.passwordStrength('Abcdefg1'), 3);
    });

    test('long (≥12) + majuscule + chiffre + spécial → 4 (plafonné)', () {
      expect(RegisterValidators.passwordStrength('Hunter2Hunter!'), 4);
    });

    test('plafond 4', () {
      expect(
        RegisterValidators.passwordStrength('SuperLongPasswordWith1!'),
        4,
      );
    });
  });
}
