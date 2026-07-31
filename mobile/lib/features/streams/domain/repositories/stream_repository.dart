import '../entities/live_stream.dart';

abstract class StreamRepository {
  Future<List<LiveStream>> listLiveStreams({int limit, int offset});

  /// Flux favoris de l'utilisateur connecté, triés par date d'ajout décroissante.
  Future<List<LiveStream>> listFavorites();

  /// Ajoute le flux aux favoris (idempotent côté serveur).
  Future<void> addFavorite(String streamId);

  /// Retire le flux des favoris (idempotent côté serveur).
  Future<void> removeFavorite(String streamId);

  /// `true` si le direct est terminé (manifeste HLS public 404/409), `false`
  /// sinon. Sert à distinguer une fin de direct d'une coupure réseau côté
  /// lecteur (STR-118).
  Future<bool> isStreamEnded(String streamId);
}
