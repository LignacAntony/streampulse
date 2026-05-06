class RegisterValidators {
  RegisterValidators._();

  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 72;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 30;

  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');

  static String? email(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Email requis';
    if (!_emailRegex.hasMatch(value)) return 'Email invalide';
    return null;
  }

  static String? username(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return 'Pseudo requis';
    if (value.length < minUsernameLength) {
      return 'Au moins $minUsernameLength caractères';
    }
    if (value.length > maxUsernameLength) {
      return 'Au plus $maxUsernameLength caractères';
    }
    if (!_usernameRegex.hasMatch(value)) {
      return 'Lettres, chiffres et _ uniquement';
    }
    return null;
  }

  static String? password(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return 'Mot de passe requis';
    if (value.length < minPasswordLength) {
      return 'Au moins $minPasswordLength caractères';
    }
    if (value.length > maxPasswordLength) {
      return 'Au plus $maxPasswordLength caractères';
    }
    return null;
  }

  static String? confirmPassword(String? raw, String original) {
    final value = raw ?? '';
    if (value.isEmpty) return 'Confirmation requise';
    if (value != original) return 'Les mots de passe ne correspondent pas';
    return null;
  }

  static int passwordStrength(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return 0;

    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(value)) score++;
    if (RegExp(r'\d').hasMatch(value)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;

    return score > 4 ? 4 : score;
  }
}
