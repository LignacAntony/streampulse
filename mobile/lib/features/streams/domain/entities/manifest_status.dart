/// Verdict du serveur sur le manifeste HLS d'un flux (STR-229).
///
/// Le statut HTTP ne suffit pas à décider : le backend rend `409` aussi bien
/// pour un direct terminé que pour un direct qui démarre. Les deux appellent des
/// conduites **opposées** — abandonner ou patienter — d'où une énumération
/// plutôt qu'un booléen « indisponible », qui forçait l'appelant à deviner.
enum ManifestStatus {
  /// Manifeste servi : le direct est en cours.
  available,

  /// Aucune session live : direct terminé, ou jamais démarré. Verdict définitif,
  /// rien à attendre.
  ended,

  /// Session vivante, manifeste pas encore écrit — la fenêtre entre le start et
  /// le premier segment (~10 s). État transitoire : réessayer a du sens.
  notReady,

  /// Le serveur n'a pas répondu, ou a répondu autre chose : on ne conclut pas.
  unknown,
}
