import 'register_validators.dart';

/// Validators pour le formulaire de réinitialisation de mot de passe.
///
/// Délègue à [RegisterValidators] pour éviter toute duplication des règles
/// métier (8–72 caractères). Les contraintes sont ainsi centralisées en un
/// seul endroit et toujours cohérentes avec l'inscription.
class ResetPasswordValidators {
  ResetPasswordValidators._();

  /// Valide le nouveau mot de passe — même règles que l'inscription.
  static String? password(String? raw) => RegisterValidators.password(raw);

  /// Valide la confirmation : doit être identique à [original].
  static String? confirmPassword(String? raw, String original) =>
      RegisterValidators.confirmPassword(raw, original);
}
