import '../entities/recommended_track.dart';

/// Contrat de la recommandation de pistes (US-09-04). Une seule opération : lire
/// les pistes recommandées au demandeur, déjà classées par le serveur.
abstract class RecommendationRepository {
  Future<List<RecommendedTrack>> fetch();
}
