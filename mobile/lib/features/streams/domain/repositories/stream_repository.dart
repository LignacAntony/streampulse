import '../entities/live_stream.dart';
import '../entities/manifest_status.dart';

abstract class StreamRepository {
  /// Flux publics en direct, paginés. [category] restreint à une catégorie
  /// (valeurs de la liste blanche backend) ; [search] filtre sur le titre ou le
  /// nom du diffuseur. Les deux sont optionnels (écran Découvrir).
  Future<List<LiveStream>> listLiveStreams({
    int limit,
    int offset,
    String? category,
    String? search,
  });

  /// Flux favoris de l'utilisateur connecté, triés par date d'ajout décroissante.
  Future<List<LiveStream>> listFavorites();

  /// Audience estimée d'un flux en direct (0 hors direct), pour rafraîchir le
  /// compteur d'auditeurs du lecteur. `null` si indisponible (l'UI conserve
  /// alors sa dernière valeur).
  Future<int?> streamListenerCount(String id);

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
