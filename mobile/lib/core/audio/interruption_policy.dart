/// Action à appliquer au lecteur suite à un événement d'interruption (STR-110).
enum InterruptionAction { none, pause, resume, duck, unduck }

/// Politique de gestion des interruptions audio (appels, notifications, casque),
/// **pure et sans dépendance plateforme** → unit-testable. Le [StreamAudioHandler]
/// traduit chaque [InterruptionAction] en appel lecteur (`pause`/`play`/volume).
///
/// Règle clé (US-04-04) : on ne **reprend** automatiquement que si c'est bien une
/// interruption qui nous avait mis en pause — jamais si l'utilisateur avait déjà
/// mis en pause de lui-même avant l'appel.
class InterruptionPolicy {
  bool _pausedByInterruption = false;

  /// Interruption « focus » (appel, notification…). [begin] distingue le début
  /// de la fin ; [isDuck] = transitoire pouvant être simplement atténuée (sinon
  /// pause franche) ; [isPlaying] = état de lecture au moment de l'événement.
  InterruptionAction onInterruption({
    required bool begin,
    required bool isDuck,
    required bool isPlaying,
  }) {
    if (begin) {
      if (isDuck) return InterruptionAction.duck;
      if (isPlaying) {
        _pausedByInterruption = true;
        return InterruptionAction.pause;
      }
      return InterruptionAction.none;
    }
    // Fin d'interruption.
    if (isDuck) return InterruptionAction.unduck;
    if (_pausedByInterruption) {
      _pausedByInterruption = false;
      return InterruptionAction.resume;
    }
    return InterruptionAction.none;
  }

  /// Casque / sortie audio débranché : on met en pause **sans** reprise
  /// automatique (comportement attendu — le son ne doit pas repartir tout seul
  /// sur le haut-parleur), et on oublie tout état de reprise.
  InterruptionAction onBecomingNoisy({required bool isPlaying}) {
    _pausedByInterruption = false;
    return isPlaying ? InterruptionAction.pause : InterruptionAction.none;
  }
}
