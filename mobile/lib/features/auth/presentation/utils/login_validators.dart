import 'register_validators.dart';

class LoginValidators {
  LoginValidators._();

  static String? email(String? raw) => RegisterValidators.email(raw);

  static String? password(String? raw) {
    final value = raw ?? '';
    if (value.isEmpty) return 'Mot de passe requis';
    return null;
  }
}
