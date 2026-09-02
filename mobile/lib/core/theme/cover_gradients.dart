import 'package:flutter/material.dart';

/// Dégradés de cover des playlists, choisis de façon déterministe selon la
/// position (variété visuelle sans donnée de couverture réelle).
///
/// Palette **partagée** (STR-250) : la Bibliothèque et la vitrine de l'accueil
/// doivent afficher une même playlist avec la même couleur — sans ça, une
/// duplication divergente donnait deux teintes selon l'écran.
const List<List<Color>> playlistCoverGradients = <List<Color>>[
  [Color(0xFF9D7BF5), Color(0xFF7C4DFF)],
  [Color(0xFF2BD9C4), Color(0xFF14B8A6)],
  [Color(0xFF5B4B8A), Color(0xFF37305C)],
  [Color(0xFF2E6E7E), Color(0xFF1E4A57)],
  [Color(0xFFF5A97B), Color(0xFFEF7C4D)],
  [Color(0xFF7B95F5), Color(0xFF4D6BFF)],
];

/// Index **stable entre exécutions** dérivé d'un id, pour choisir une couleur
/// dans une palette de longueur [paletteLength].
///
/// Somme des unités de code (déterministe) et **non** `String.hashCode`, qui peut
/// varier d'un lancement de l'app à l'autre — la couleur d'un même élément
/// changerait alors à chaque relance. Factorisé ici pour être partagé par les
/// covers de playlists **et** les vignettes de flux (`stream_tile`).
int stableColorIndex(String id, int paletteLength) {
  assert(paletteLength > 0);
  var acc = 0;
  for (final unit in id.codeUnits) {
    acc = (acc + unit) % paletteLength;
  }
  return acc;
}

/// Dégradé **stable pour une playlist donnée** : dérivé de son id, et non de sa
/// position dans une liste. Ainsi la même playlist garde la même couleur, que ce
/// soit dans la grille de la Bibliothèque ou dans la rangée de l'accueil (où les
/// positions diffèrent).
List<Color> playlistCoverGradient(String id) =>
    playlistCoverGradients[stableColorIndex(id, playlistCoverGradients.length)];
