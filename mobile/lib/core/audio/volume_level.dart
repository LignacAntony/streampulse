/// Niveau sonore de l'application, en deux valeurs distinctes (STR-244) :
/// celle que l'auditeur a choisie, et celle réellement envoyée au lecteur.
///
/// Les deux divergent pendant l'atténuation d'une interruption transitoire
/// (ducking, ADR 033) : une notification arrive, le flux baisse, mais le
/// **réglage** de l'auditeur n'a pas changé — et c'est celui-là que le curseur
/// doit montrer. Confondre les deux ferait sauter le curseur à chaque
/// notification reçue, ce qui se lit comme un bug.
///
/// ## Ce que cet objet corrige
///
/// La version précédente capturait `player.volume` au moment du duck pour le
/// restaurer après. Cela marchait tant que personne ne pouvait régler le
/// volume. Depuis qu'un curseur existe, un réglage fait **pendant**
/// l'interruption était écrasé à la restauration : l'auditeur baissait le son
/// pendant sa notification, et le son remontait tout seul à la fin.
///
/// Ici le réglage est la source de vérité et l'atténuation en dérive, si bien
/// que le cas ne peut plus se produire.
///
/// Objet **pur** et immuable, comme [InterruptionPolicy] et [PlaybackOrder] :
/// la règle se vérifie sans lecteur ni plateforme.
class VolumeLevel {
  const VolumeLevel({this.user = 1, this.ducked = false});

  /// Facteur appliqué pendant une atténuation.
  ///
  /// Un **facteur** et non un niveau absolu : atténuer à 0,4 en dur remonterait
  /// le son de quelqu'un qui écoute à 0,2.
  static const double duckFactor = 0.4;

  /// Niveau choisi par l'auditeur, dans `[0, 1]`.
  final double user;

  /// Vrai pendant une atténuation.
  final bool ducked;

  /// Niveau à envoyer au lecteur.
  double get effective => ducked ? user * duckFactor : user;

  /// Applique un nouveau réglage. La valeur est ramenée dans `[0, 1]` :
  /// `just_audio` accepte des valeurs supérieures à 1 (amplification) mais le
  /// curseur ne les propose pas, et une valeur venue d'un magasin de
  /// préférences trafiqué ne doit pas saturer le son.
  VolumeLevel withUser(double value) =>
      VolumeLevel(user: value.clamp(0.0, 1.0), ducked: ducked);

  /// Entre ou sort de l'atténuation, sans toucher au réglage.
  VolumeLevel withDucked(bool value) =>
      VolumeLevel(user: user, ducked: value);

  @override
  bool operator ==(Object other) =>
      other is VolumeLevel && other.user == user && other.ducked == ducked;

  @override
  int get hashCode => Object.hash(user, ducked);

  @override
  String toString() => 'VolumeLevel(user: $user, ducked: $ducked)';
}
