import '../network/dio_client.dart';
import '../storage/secure_storage.dart';

/// Fournit au lecteur audio l'access token à joindre aux requêtes de pistes.
///
/// [forceRefresh] déclenche d'abord une rotation : c'est le recours quand une
/// lecture a échoué faute d'un token encore valide (une file d'attente peut
/// durer plus que les 15 min d'un access token). Renvoie `null` si aucun token
/// n'est disponible — l'appelant laisse alors le serveur répondre 401 plutôt que
/// d'inventer un état d'erreur local.
typedef PlaybackTokenProvider = Future<String?> Function({bool forceRefresh});

/// Implémentation branchée sur le stockage sécurisé et le client HTTP.
///
/// Existe parce que le lecteur natif (just_audio) ouvre ses propres connexions
/// et ne traverse pas les intercepteurs de [DioClient] : l'injection du `Bearer`
/// et le rafraîchissement doivent être faits explicitement pour lui.
class PlaybackAuth {
  const PlaybackAuth(this._storage, this._client);

  final SecureStorage _storage;
  final DioClient _client;

  Future<String?> token({bool forceRefresh = false}) async {
    if (forceRefresh) {
      // Échec de la rotation (refresh token expiré/révoqué) : on lit quand même
      // le token courant. S'il est périmé, le 401 du serveur est la réponse
      // honnête, et le router renverra vers /login au prochain appel API.
      await _client.refreshTokens();
    }
    return _storage.getAccessToken();
  }
}
