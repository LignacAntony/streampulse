import 'package:flutter/widgets.dart';

/// Ruptures de largeur et adaptation de la mise en page (STR-244).
///
/// ## La décision, plutôt que de la subir
///
/// Le paysage **est autorisé** — `Info.plist` liste `LandscapeLeft`/`Right` et
/// l'`AndroidManifest` ne pose aucun `screenOrientation` — mais l'interface
/// était figée en une colonne portrait. Faire pivoter le téléphone donnait donc
/// un portrait étiré, où une ligne de liste traverse 800 px pour trois mots.
///
/// Deux issues possibles : verrouiller le portrait, ou adapter. Le verrouillage
/// était honnête et immédiat, mais il aurait retiré une capacité que les deux
/// plateformes offrent — et le sujet demande une interface « responsive ».
///
/// C'est donc l'adaptation qui est retenue, par un mécanisme unique :
/// **borner la largeur du contenu** ([contentMaxWidth]). Une ligne de texte
/// au-delà de ~70 caractères se lit mal — ce n'est pas une question de
/// plateforme mais de typographie, et c'est exactement ce qui rendait le
/// paysage illisible.
///
/// Le cas tablette — passer en plusieurs colonnes plutôt que de laisser deux
/// tiers de l'écran vides — n'est **pas** traité ici. Une API `columnsFor` avait
/// été écrite pour lui, sans aucun appelant : de l'échafaudage à maintenir sans
/// comportement derrière (revue PR #332). Elle reviendra avec l'écran qui en a
/// besoin.
///
/// ## Pourquoi ces valeurs
///
/// Ce sont les classes de taille de Material 3 : compact (< 600), medium
/// (600–839), expanded (≥ 840). Les reprendre plutôt que d'inventer les nôtres
/// évite d'avoir à les défendre, et elles s'alignent sur ce que font les
/// composants Material que l'application utilise déjà.
///
/// Objet **pur** : la règle se vérifie sans monter d'arbre de widgets.
class Breakpoints {
  const Breakpoints._();

  /// En deçà : téléphone en portrait. Une seule colonne.
  static const double medium = 600;

  /// Largeur maximale d'une colonne de contenu.
  ///
  /// Bornée à [medium] : au-delà, la ligne devient trop longue pour l'œil, quel
  /// que soit l'espace disponible. Sur un écran plus large, la colonne est
  /// centrée et l'espace restant sert de marge — c'est ce qui remplace le
  /// portrait étiré.
  static double contentMaxWidth(double width) =>
      width <= medium ? width : medium;

}

/// Centre et borne son enfant au-delà de la rupture (cf. [Breakpoints.contentMaxWidth]).
///
/// À poser autour du contenu d'un écran de liste ou de formulaire. Sans effet
/// sur un téléphone en portrait : la contrainte n'y mord pas, donc rien ne
/// change là où l'application passe l'essentiel de son temps.
class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // `maxWidth` infini : le parent est un ListView horizontal, une Row non
        // bornée, ou un contexte de mesure. Borner y lèverait une exception.
        if (!constraints.hasBoundedWidth) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: Breakpoints.contentMaxWidth(constraints.maxWidth),
            ),
            child: child,
          ),
        );
      },
    );
  }
}
