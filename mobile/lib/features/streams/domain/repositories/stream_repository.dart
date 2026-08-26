import '../entities/live_stream.dart';
import '../entities/manifest_status.dart';

abstract class StreamRepository {
  Future<List<LiveStream>> listLiveStreams({int limit, int offset});

  /// Flux favoris de l'utilisateur connecté, triés par date d'ajout décroissante.
  Future<List<LiveStream>> listFavorites();

  /// Ajoute le flux aux favoris (idempotent côté serveur).
  Future<void> addFavorite(String streamId);

  /// Retire le flux des favoris (idempotent côté serveur).
  Future<void> removeFavorite(String streamId);

  /// Interroge le manifeste HLS **public** du flux et rend le verdict du
  /// serveur : direct en cours, terminé, en cours de démarrage, ou indéterminé.
  ///
  /// C'est le serveur qui tranche entre « terminé » et « pas encore prêt »
  /// (STR-229) — lui seul sait si une session existe. Le lecteur se contentait
  /// autrefois d'un booléen et devait deviner.
  Future<ManifestStatus> manifestStatus(String streamId);
}
