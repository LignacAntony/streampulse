import '../entities/live_stream.dart';

abstract class StreamRepository {
  Future<List<LiveStream>> listLiveStreams({int limit, int offset});

  /// Flux favoris de l'utilisateur connecté, triés par date d'ajout décroissante.
  Future<List<LiveStream>> listFavorites();

  /// Ajoute le flux aux favoris (idempotent côté serveur).
  Future<void> addFavorite(String streamId);

  /// Retire le flux des favoris (idempotent côté serveur).
  Future<void> removeFavorite(String streamId);

  /// `true` si le manifeste HLS public n'est plus servi (404/409), `false` sinon
  /// (200 en direct, ou réseau indéterminé). Le 409 étant ambigu (fin de direct
  /// **ou** démarrage pas encore prêt), c'est le lecteur qui lève l'ambiguïté
  /// (STR-118/109).
  Future<bool> isManifestUnavailable(String streamId);
}
