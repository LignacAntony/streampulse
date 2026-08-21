/// Temps d'écoute cumulé d'un direct (STR-244).
///
/// Un direct n'a pas de durée — il n'a pas de fin connue — mais il a un temps
/// d'écoute, et c'est cela que l'auditeur veut voir : « ça fait 12 minutes que
/// j'écoute ».
///
/// ## Pourquoi pas la position du lecteur
///
/// `just_audio` expose bien une `position` sur un flux HLS, et l'utiliser aurait
/// coûté une ligne. Mais cette position est relative à la **source chargée**, et
/// le contrôleur recharge l'URL à chaque reprise après erreur (reconnexion
/// bornée, STR-118). Une coupure réseau de deux secondes remettrait donc le
/// compteur à zéro, sous un libellé qui promet « depuis le début de l'écoute ».
///
/// Cette horloge est pilotée par l'**état de lecture**, pas par la source : elle
/// traverse les rechargements. C'est la seule façon de tenir la promesse du
/// libellé.
///
/// ## Objet pur
///
/// Aucune minuterie, aucun `DateTime.now()` interne, aucune dépendance Flutter —
/// même parti que [InterruptionPolicy] et [PlaybackOrder] : l'appelant fournit
/// l'instant, ce qui rend le comportement vérifiable sans attendre.
class ListeningClock {
  Duration _accumulated = Duration.zero;
  DateTime? _startedAt;

  /// Vrai si l'horloge tourne (l'auditeur entend quelque chose).
  bool get running => _startedAt != null;

  /// Démarre ou reprend le décompte. Idempotent : appelée alors que l'horloge
  /// tourne déjà, elle ne redémarre pas — sinon chaque événement de lecture
  /// répété (le lecteur en émet plusieurs pour un même état) décalerait
  /// l'origine et le temps affiché reculerait.
  void start(DateTime at) {
    _startedAt ??= at;
  }

  /// Suspend le décompte en cumulant la tranche écoulée.
  ///
  /// Appelée à la pause **et pendant une reconnexion** : le compteur mesure du
  /// temps d'écoute, et une reconnexion est précisément le moment où l'auditeur
  /// n'écoute rien. Le figer est plus honnête que de le laisser courir sur du
  /// silence.
  void pause(DateTime at) {
    final started = _startedAt;
    if (started == null) return;
    _accumulated += _nonNegative(at.difference(started));
    _startedAt = null;
  }

  /// Repart de zéro. À appeler quand l'écoute change d'objet — autre flux, ou
  /// arrêt — jamais sur une simple pause.
  void reset() {
    _accumulated = Duration.zero;
    _startedAt = null;
  }

  /// Temps d'écoute à l'instant [now], tranche en cours comprise.
  Duration elapsedAt(DateTime now) {
    final started = _startedAt;
    if (started == null) return _accumulated;
    return _accumulated + _nonNegative(now.difference(started));
  }

  /// Une horloge murale peut reculer (fuseau, synchronisation NTP, changement
  /// manuel). Un temps d'écoute négatif n'a aucun sens et ferait afficher un
  /// compteur qui décroît : la tranche est alors comptée pour zéro.
  static Duration _nonNegative(Duration d) =>
      d.isNegative ? Duration.zero : d;
}
