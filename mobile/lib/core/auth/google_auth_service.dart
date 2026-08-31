import 'package:google_sign_in/google_sign_in.dart';

/// L'utilisateur a fermé la feuille de connexion Google sans la valider.
/// Distincte d'un échec : l'UI reste silencieuse dans ce cas.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();
}

/// La connexion Google a échoué (réseau, configuration, jeton absent).
class GoogleSignInFailure implements Exception {
  const GoogleSignInFailure([this.message = 'Connexion Google impossible']);

  final String message;

  @override
  String toString() => 'GoogleSignInFailure: $message';
}

/// Abstraction (DIP) de la connexion Google côté appareil.
///
/// Le repository dépend de cette interface, jamais du plugin `google_sign_in`
/// directement : un fake la remplace dans les tests, sans compte Google réel.
/// [signIn] renvoie l'**ID token** Google (JWT) à transmettre au backend, qui
/// le vérifie contre les clés publiques de Google.
abstract class GoogleAuthService {
  Future<String> signIn();
  Future<void> signOut();
}

class GoogleAuthServiceImpl implements GoogleAuthService {
  GoogleAuthServiceImpl({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: const ['email'],
            // Audience du jeton = Client Web OAuth (== GOOGLE_CLIENT_ID côté
            // backend). Sur iOS, laissé nul, le plugin lit GIDServerClientID
            // depuis Info.plist ; sur Android, fourni par --dart-define.
            serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
          );

  /// ID du Client Web OAuth, injecté au build :
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Nécessaire sur Android ;
  /// optionnel sur iOS (Info.plist → GIDServerClientID).
  static const String _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final GoogleSignIn _googleSignIn;

  @override
  Future<String> signIn() async {
    final GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signIn();
    } on Exception catch (e) {
      throw GoogleSignInFailure(e.toString());
    }

    // signIn() renvoie null quand l'utilisateur annule.
    if (account == null) {
      throw const GoogleSignInCancelled();
    }

    final auth = await account.authentication;
    final idToken = auth.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleSignInFailure('Jeton Google absent');
    }
    return idToken;
  }

  @override
  Future<void> signOut() => _googleSignIn.signOut();
}
