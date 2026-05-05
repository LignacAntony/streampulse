// Validateurs purs pour le formulaire d'inscription.
//
// Reproduisent les règles du backend afin que :
//   - l'utilisateur reçoive un retour immédiat sans aller-retour HTTP,
//   - les erreurs serveur (400 / 409) restent rares, gérées séparément.
//
// Chaque validateur retourne `null` si la valeur est valide, ou une chaîne
// d'erreur localisée à afficher dans le `TextFormField`.
class RegisterValidators {
  RegisterValidators._();

  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 72;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 30;

  // Regex permissive — la validation stricte est faite côté serveur via
  // `net/mail.ParseAddress`. On bloque seulement les évidences (espace, @
  // manquant, point manquant).
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
}
