/// Audience d'une diffusion, telle que rendue par `GET /api/streams/{id}/stats`
/// (US-06-02, STR-154).
///
/// [listeners] et [peak] sont des **estimations** : HLS n'ouvre pas de connexion
/// persistante, le serveur compte donc les clients ayant demandé le manifeste
/// récemment. Deux lecteurs derrière la même adresse publique comptent pour un,
/// et un lecteur qui vient de fermer reste compté quelques dizaines de secondes.
/// Les deux valeurs vivent en mémoire côté serveur : elles repartent de zéro au
/// redémarrage et ne survivent pas à la fin de la diffusion.
class BroadcastStats {
  const BroadcastStats({
    required this.streamId,
    required this.listeners,
    required this.peak,
    required this.duration,
  });

  final String streamId;
  final int listeners;
  final int peak;

  /// Durée de diffusion : depuis le démarrage jusqu'à maintenant tant que le
  /// flux est en direct, jusqu'à son arrêt ensuite.
  final Duration duration;

  /// Instantané vide, affiché tant qu'aucune mesure n'est arrivée.
  static const empty = BroadcastStats(
    streamId: '',
    listeners: 0,
    peak: 0,
    duration: Duration.zero,
  );
}
