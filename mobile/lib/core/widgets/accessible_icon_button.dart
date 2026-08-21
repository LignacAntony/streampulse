import 'package:flutter/material.dart';

import '../constants/app_constants.dart';

/// Bouton-icône nommé pour les lecteurs d'écran (STR-244).
///
/// ## Pourquoi un `tooltip` ne suffit pas
///
/// Vérifié sur l'arbre sémantique : un `IconButton(tooltip: 'Mettre en pause')`
/// produit un nœud `label="" tooltip="Mettre en pause"`. Le texte est donc bien
/// exposé — la garde `labeledTapTargetGuideline` de Flutter l'accepte — mais
/// dans le champ **tooltip**, pas dans le champ **label**.
///
/// La différence n'est pas cosmétique :
///
/// - Android : le tooltip devient `AccessibilityNodeInfo.tooltipText`. TalkBack
///   s'en sert **à défaut** de description, donc le bouton est utilisable.
/// - iOS : il devient un *hint*, pas un *label*. VoiceOver annonce alors
///   « bouton » sans nom, puis éventuellement le hint après une pause — et
///   seulement si les hints sont activés.
///
/// Un bouton-icône qui n'a qu'un tooltip est donc **anonyme sur iOS**. Ce widget
/// pose les deux : le libellé sémantique pour les lecteurs d'écran, le tooltip
/// pour l'appui long et le survol.
///
/// ## Taille de cible
///
/// `IconButton` fait 48 px par défaut, au-dessus des 44 px exigés par WCAG 2.1
/// AA ([AppConstants.minTouchTarget]). La contrainte est néanmoins posée
/// explicitement : une densité visuelle réduite (`visualDensity`) ou un
/// `IconButtonTheme` sur un écran donné peut faire passer sous la barre sans
/// que rien ne le signale.
class AccessibleIconButton extends StatelessWidget {
  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.iconSize,
    this.tooltip,
  });

  final IconData icon;

  /// Ce que le lecteur d'écran annonce. Décrit **l'action**, pas l'icône :
  /// « Mettre en pause », jamais « icône pause ».
  final String label;

  /// `null` désactive le bouton — l'état est alors annoncé par le lecteur
  /// d'écran, sans que le libellé change.
  final VoidCallback? onPressed;

  final Color? color;
  final double? iconSize;

  /// Texte de l'infobulle si elle doit différer du libellé. Par défaut, le
  /// libellé sert aux deux : les faire diverger sans raison donnerait deux
  /// vocabulaires pour le même bouton.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      enabled: onPressed != null,
      // Le libellé du Semantics fait autorité : sans cette exclusion, le tooltip
      // posé en dessous ajouterait une seconde annonce du même texte.
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: AppConstants.minTouchTarget,
          minHeight: AppConstants.minTouchTarget,
        ),
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip ?? label,
          color: color,
          iconSize: iconSize,
          icon: Icon(icon),
        ),
      ),
    );
  }
}
