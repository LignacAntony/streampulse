/// Libellés partagés par la liste de détail d'une playlist et le sélecteur
/// d'ajout : les deux affichent la même piste, ils doivent la décrire pareil.
///
/// Volontairement local à la feature. Les autres écrans formatent des durées
/// différentes (« 23min » pour l'ancienneté d'un direct, « 1:05:03 » pour un
/// chrono en cours) : les fusionner imposerait un format commun là où chacun
/// répond à un besoin distinct.
library;

/// « Artiste · m:ss », en repliant les champs nuls (la table `tracks` autorise
/// `artist` et `duration_s` à null).
String trackSubtitle({required String? artist, required int? durationS}) {
  final name = artist ?? 'Artiste inconnu';
  if (durationS == null) return name;
  return '$name · ${formatTrackDuration(durationS)}';
}

/// Durée d'une piste en `m:ss` (les minutes ne sont pas complétées à gauche :
/// une piste dure rarement plus de dix minutes).
String formatTrackDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final rest = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$rest';
}
