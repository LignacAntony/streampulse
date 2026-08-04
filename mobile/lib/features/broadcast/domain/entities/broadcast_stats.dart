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
  });

  final String streamId;
  final int listeners;

  /// Maximum d'auditeurs observé depuis le début de la diffusion. **Tout aussi
  /// estimé** que [listeners] : il dérive exactement des mêmes mesures.
  final int peak;

  /// `duration_seconds` de l'API n'est volontairement pas repris ici : le
  /// tableau de bord affiche déjà la durée du direct via un compteur local
  /// rafraîchi chaque seconde, alors que la valeur serveur n'arriverait que
  /// toutes les 5 s et ferait sauter le chronomètre. Le champ reste dans le
  /// contrat HTTP, où l'historique (STR-162) en aura besoin.

  @override
  bool operator ==(Object other) =>
      other is BroadcastStats &&
      other.streamId == streamId &&
      other.listeners == listeners &&
      other.peak == peak;

  @override
  int get hashCode => Object.hash(streamId, listeners, peak);
}
