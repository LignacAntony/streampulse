# ADR 043 — Accessibilité de l'application mobile et adaptation aux largeurs d'écran

**Date** : 2026-08-21
**Statut** : Accepté
**Ticket** : [STR-244](https://linear.app/streampulse/issue/STR-244/completer-le-lecteur-linterface-et-les-metriques-manquantes-du-bareme)

---

## Contexte

Le sujet demande une interface « responsive (iOS/Android) et respectant les
standards d'accessibilité ». L'audit a mesuré l'écart, et il était net :

| Recherche dans `lib/` (147 fichiers) | Occurrences |
| -- | -- |
| `Semantics(` | 1 — sur l'écran de démarrage |
| `semanticLabel` / `semanticsLabel` | 0 |
| `LayoutBuilder` / `OrientationBuilder` | 0 |
| `AppConstants.minTouchTarget` | 8 fichiers |

[`docs/accessibilite.md`](../accessibilite.md) déclarait déjà l'accessibilité de
la **documentation**, en excluant explicitement l'application : « un chantier
distinct […] confondre les deux reviendrait à déclarer conforme quelque chose
qui ne l'est pas ». Cette ADR ouvre ce chantier.

---

## 1. Un `tooltip` n'est pas un `label` — vérifié, pas supposé

Le ticket affirmait que les treize fichiers portant un `tooltip:` « ne comptent
pas », un tooltip n'étant pas un libellé sémantique. C'est **inexact tel quel**,
et la nuance change ce qu'il faut corriger.

Mesuré sur l'arbre sémantique d'un `IconButton(tooltip: 'Mettre en pause')` :

```
label="" tooltip="Mettre en pause" button=true
```

Le texte **est** exposé, dans le champ `tooltip`. Conséquences par plateforme :

| | Ce que devient le tooltip | Effet |
| -- | -- | -- |
| Android | `AccessibilityNodeInfo.tooltipText` | TalkBack s'en sert à défaut de description : le bouton est utilisable |
| iOS | un *hint*, pas un *label* | VoiceOver annonce « bouton » **sans nom**, puis éventuellement le hint après une pause, et seulement si les hints sont activés |

Un bouton-icône qui n'a qu'un tooltip est donc **anonyme sur iOS**. C'est un
vrai défaut — mais pas celui qui était annoncé, et le corriger demande de poser
un `label`, pas de remplacer les tooltips.

`AccessibleIconButton` pose **les deux** : le libellé pour les lecteurs
d'écran, le tooltip pour l'appui long et le survol.

Le libellé décrit l'**action**, jamais l'icône ni l'état. Le tooltip d'origine
du bouton de lecture disait « Pause » quand la lecture était à l'arrêt : un
lecteur d'écran annonçait donc exactement l'inverse de ce que l'appui allait
faire.

---

## 2. Les vérificateurs de Flutter tournent en CI

`flutter_test` embarque `androidTapTargetGuideline`, `iOSTapTargetGuideline`,
`labeledTapTargetGuideline` et `textContrastGuideline`. Les faire tourner vaut
mieux qu'une affirmation de conformité dans un document : ils échouent quand la
règle est violée, y compris sur du code écrit plus tard.

Une vérification **plus stricte** leur est ajoutée :
`expectNoTooltipOnlyTapTargets`. `labeledTapTargetGuideline` accepte un tooltip
seul — elle regarde label *ou* tooltip — alors que c'est précisément le cas qui
laisse un bouton anonyme sur iOS.

Elle est accompagnée d'un **test de contrôle** : un `IconButton` nu doit être
signalé. Sans lui, on ne saurait pas si la garde vérifie quelque chose ou passe
toujours — et c'est exactement ce qui s'est produit à l'écriture : la première
version cherchait l'arbre sémantique sur le mauvais `PipelineOwner`, n'en
trouvait aucun, et rendait sereinement une liste vide. Un vérificateur qui ne
trouve pas son sujet échoue désormais bruyamment.

### Ce que ces gardes ne couvrent pas

L'ordre de parcours, la pertinence des libellés, et le comportement réel de
TalkBack et VoiceOver. Cette vérification-là **n'a pas été faite** : elle exige
un appareil, et le matériel n'était pas disponible. C'est un écart déclaré, pas
un point tenu.

---

## 3. Une ligne de liste se lit d'un coup, ou pas du tout

Une ligne de playlist affiche un numéro, un titre, un artiste, et un point
coloré pour la piste en cours. Un lecteur d'écran parcourt ces fragments un par
un — et ne voit pas le point.

Sans regroupement, TalkBack annonce « 3 », s'arrête, « Sunrise », s'arrête,
« Neon Lights, 3:34 » — trois arrêts, et jamais l'information qui compte : c'est
celle-ci qui joue.

Le conteneur porte donc la phrase entière et masque ses enfants :

> « Piste 3, Sunrise, Neon Lights, en cours de lecture »

Les boutons d'une liste nomment leur cible pour la même raison : dix boutons
« Interrompre » qui se suivent ne disent pas lequel on a sous le doigt.

---

## 4. Adapter plutôt que verrouiller le portrait

Le paysage **est autorisé** — `Info.plist` liste `LandscapeLeft`/`Right`,
l'`AndroidManifest` ne pose aucun `screenOrientation` — mais l'interface était
figée en une colonne. Faire pivoter le téléphone donnait un portrait étiré, où
une ligne de trois mots traverse 800 px.

Deux issues : verrouiller le portrait, ou adapter. Le ticket demandait de
trancher et d'écrire la décision.

**L'adaptation est retenue.** Le verrouillage était honnête et immédiat, mais il
aurait retiré une capacité que les deux plateformes offrent, pour un gain nul
en accessibilité — quelqu'un qui fixe son téléphone sur un support de vélo n'a
pas le choix de l'orientation.

Deux mécanismes, parce que les deux problèmes sont distincts :

1. **Borner la largeur du contenu** — répond au portrait étiré. Une ligne de
   texte au-delà de ~70 caractères se lit mal ; ce n'est pas une question de
   plateforme mais de typographie.
2. **Multiplier les colonnes** — répond à la tablette, où borner la largeur
   laisserait deux tiers de l'écran vides.

Les valeurs sont les classes de taille de Material 3 (compact < 600, medium
600–839, expanded ≥ 840). Les reprendre plutôt que d'inventer les nôtres évite
d'avoir à les défendre, et les aligne sur les composants Material déjà utilisés.

`ResponsiveContent` **n'a aucun effet sur un téléphone en portrait** : la
contrainte n'y mord pas. Rien ne change là où l'application passe l'essentiel de
son temps, et c'est voulu — une adaptation qui modifie le cas nominal pour
soigner un cas rare est une régression déguisée.

---

## Conséquences

**Positives**

- Les contrôles du lecteur, les lignes de playlist et les actions d'admin ont un
  nom pour un lecteur d'écran, sur **les deux** plateformes.
- Quatre vérificateurs WCAG tournent en CI, plus une garde maison plus stricte.
- La rotation ne produit plus une colonne étirée.
- Le grossissement de texte est couvert par un test.

**Négatives, assumées**

- **Aucune vérification au lecteur d'écran réel.** TalkBack et VoiceOver exigent
  un appareil ; le point n'est pas tenu et ne doit pas être présenté comme tel.
- La couverture est partielle : les surfaces nommées par le ticket sont
  traitées, les écrans d'authentification et de profil ne le sont pas encore.
- `AccessibleIconButton` n'expose pas toute la surface d'`IconButton`
  (`padding`, `splashRadius`, `constraints`) — à élargir au besoin.
- Les colonnes multiples sont disponibles (`Breakpoints.columnsFor`) mais
  encore appliquées nulle part : les écrans de liste bornent leur largeur sans
  passer en grille.

---

## Alternatives écartées

**Verrouiller le portrait dans `Info.plist` et l'`AndroidManifest`.** Une ligne
de configuration par plateforme, et le problème du portrait étiré disparaît.
Écarté : cela retire une capacité offerte par les deux systèmes à des
utilisateurs qui n'ont pas toujours le choix de l'orientation.

**Se fier aux `tooltip:` existants.** Ils satisfont la garde de Flutter et
fonctionnent sur Android. Écarté après vérification : sur iOS ils deviennent des
hints, et le bouton reste sans nom.

**Ajouter `Semantics` à la main partout plutôt qu'un widget dédié.** Écarté :
rien n'empêcherait alors le prochain `IconButton` d'oublier son libellé. Le
widget rend la règle difficile à contourner, la garde de test la rend visible.

**Se contenter des vérificateurs de Flutter, sans garde maison.** Écarté :
`labeledTapTargetGuideline` accepte un tooltip seul, soit exactement le défaut à
corriger.

**Déclarer la conformité WCAG 2.1 AA de l'application.** Écarté : sans passage
au lecteur d'écran réel, la déclaration serait invérifiée. L'ADR décrit ce qui
est fait et ce qui ne l'est pas.

---

## Références

- [Accessibilité de la documentation](../accessibilite.md) — le volet documentaire, périmètre distinct
- [ADR 036 — State management Flutter](036-state-management-flutter-provider.md)
- ADR 042 — Contrôle du volume et temps d'écoute (PR distincte) : le curseur
  qu'elle ajoute au lecteur est annoncé en pourcentage par le même mécanisme
