import 'register_validators.dart';

class ResetPasswordValidators {
  ResetPasswordValidators._();

  static String? password(String? raw) => RegisterValidators.password(raw);

  static String? confirmPassword(String? raw, String original) =>
      RegisterValidators.confirmPassword(raw, original);
}
