import '../entities/live_stream.dart';

abstract class StreamRepository {
  Future<List<LiveStream>> listLiveStreams({int limit, int offset});

  /// Flux favoris de l'utilisateur connecté, triés par date d'ajout décroissante.
  Future<List<LiveStream>> listFavorites();

  /// Ajoute le flux aux favoris (idempotent côté serveur).
  Future<void> addFavorite(String streamId);

  /// Retire le flux des favoris (idempotent côté serveur).
  Future<void> removeFavorite(String streamId);
}
