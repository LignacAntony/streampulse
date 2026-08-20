# Accessibilité de la documentation

Ce document déclare le niveau d'accessibilité visé par la **documentation** de
StreamPulse, les règles qui l'assurent, et les écarts qui subsistent.

> **Périmètre.** Il porte sur les documents de `docs/` et le `README`. Il ne
> porte **pas** sur l'accessibilité de l'application Flutter elle-même, qui est
> un chantier distinct et n'est pas couverte ici. Les deux comptent, séparément,
> et confondre les deux reviendrait à déclarer conforme quelque chose qui ne
> l'est pas.

---

## 1. Niveau visé et déclaré

**WCAG 2.1 niveau AA**, appliqué au contenu documentaire.

Le RGAA n'est pas retenu comme référentiel de déclaration : il est conçu pour
des services en ligne publics et une bonne part de ses critères porte sur des
composants d'interface — formulaires, navigation, médias temporels — qu'une
documentation Markdown ne contient pas. WCAG 2.1 AA couvre ce qui s'applique
réellement ici, sans se donner une conformité sur des critères hors sujet.

## 2. Ce que cela impose, et comment c'est tenu

| Règle | Critère | Comment elle est appliquée |
|---|---|---|
| Toute image porte une alternative textuelle | 1.1.1 | Chaque capture d'écran du manuel est doublée d'une description dans le corps du texte, jamais seulement dans l'attribut `alt` |
| Tout schéma a un équivalent textuel | 1.1.1 | Les diagrammes Mermaid sont suivis d'un paragraphe « Équivalent textuel » qui décrit le même contenu |
| L'information ne repose pas sur la seule couleur | 1.4.1 | Les tableaux de statut utilisent des **mots** (« oui », « non », « propriétaire »), pas uniquement des pastilles colorées |
| La structure est portée par le balisage | 1.3.1 | Titres hiérarchisés sans saut de niveau, tableaux avec ligne d'en-tête, listes réelles |
| La lecture ne dépend pas de la mise en forme spatiale | 1.3.2 | Aucune information n'est portée par un alignement en espaces ou un dessin en caractères |
| Les liens sont explicites hors contexte | 2.4.4 | Pas de « cliquer ici » : le libellé nomme la cible |
| La langue est déclarée | 3.1.1 | Documents en français ; les termes anglais conservés sont définis au glossaire |

## 3. Conséquences concrètes sur la rédaction

**Un document doit rester complet une fois ses images retirées.** C'est le test
que nous appliquons : si supprimer les captures rend une étape incompréhensible,
le texte est insuffisant, pas l'illustration manquante. Le
[manuel utilisateur](manuel-utilisateur.md) est écrit dans cet ordre — le texte
d'abord, les captures en appui.

**Les diagrammes sont en Mermaid, pas en dessin de caractères.** Un diagramme
Mermaid est du texte structuré : un lecteur d'écran en restitue les nœuds et les
liens. Un schéma en caractères de dessin de boîtes est vocalisé caractère par
caractère — « tiret tiret tiret barre verticale » — ce qui est activement
pénible, pas simplement inutile. Voir [diagrammes.md](diagrammes.md).

**Les tableaux restent lisibles en linéaire.** Un lecteur d'écran parcourt un
tableau cellule par cellule ; nous gardons donc peu de colonnes et des en-têtes
qui se suffisent.

## 4. Version imprimable

Les documents sont du Markdown : ils s'impriment depuis n'importe quel
visualiseur, ou se convertissent en PDF avec la structure de titres préservée
— condition pour que le PDF reste navigable par technologie d'assistance.

Aucune mise en page ne repose sur des espaces ou des tabulations, ce qui garantit
que la conversion ne détruit pas le sens.

## 5. Glossaire

La documentation reste dense. Les termes qu'on ne peut pas éviter :

| Terme | Ce que c'est |
|---|---|
| **Flux** (ou *direct*) | Une diffusion audio en temps réel, créée par un diffuseur |
| **Clé de diffusion** | Le secret qui autorise à envoyer de l'audio sur un flux donné |
| **Ingest** | L'action d'envoyer l'audio vers le serveur, du côté du diffuseur |
| **HLS** | La technique de diffusion employée : le son est découpé en petits fichiers successifs que le lecteur récupère l'un après l'autre |
| **Segment** | Un de ces petits fichiers, environ dix secondes de son |
| **Manifeste** (`.m3u8`) | La liste des segments disponibles, que le lecteur relit régulièrement |
| **Playlist** | Une liste de pistes personnelles — sans rapport avec le manifeste ci-dessus, malgré le mot |
| **Piste** | Un fichier audio téléversé par un utilisateur |
| **File d'attente** | Ce que le lecteur va jouer, dans l'ordre, une fois une playlist lancée |
| **Jeton** (*token*) | La preuve d'identité que l'application présente au serveur à chaque requête |
| **Favori** | Un flux mis de côté pour le retrouver depuis l'accueil |
| **Rôle** | Le niveau de droits d'un compte : auditeur, diffuseur, administrateur |
| **ADR** | *Architecture Decision Record* — une note qui explique **pourquoi** un choix technique a été fait |
| **Journal d'audit** | La trace des actions d'administration : qui a fait quoi, quand |

## 6. Écarts connus

1. **`architecture.md` contient encore des schémas en caractères de dessin de
   boîtes** — 79 lignes concernées. C'est le principal manquement de cette
   déclaration, et il est **actif** : un lecteur d'écran les vocalise
   caractère par caractère.

   Atténuation immédiate : les mêmes contenus existent en Mermaid, avec
   équivalents textuels, dans [diagrammes.md](diagrammes.md). Un lecteur
   utilisant une technologie d'assistance doit être orienté vers ce document.

   La reprise d'`architecture.md` est délibérément laissée hors de cette
   modification : le fichier est en cours de réécriture par ailleurs, et deux
   réécritures concurrentes du même fichier se résoudraient mal. À traiter dès
   cette réécriture fusionnée.

2. **Une seule capture d'écran est produite** — l'écran de connexion. Le manuel
   est rédigé pour être complet sans images — c'est la règle du § 3 — mais leur
   rareté prive les personnes qui s'appuient sur le repérage visuel d'un point
   d'ancrage. Les captures manquantes demandent de naviguer dans l'application,
   donc d'y envoyer des appuis, ce que l'outillage disponible ne permettait pas
   au moment de la rédaction.

3. **La documentation n'existe qu'en français.** Le critère de bilinguisme est
   traité séparément (ticket « version anglaise de la documentation ») et n'est
   pas couvert par cette déclaration.

4. **Aucun audit par une personne utilisant réellement une technologie
   d'assistance** n'a été mené. Les règles ci-dessus sont appliquées de bonne
   foi ; elles n'ont pas été confrontées à l'usage. C'est la limite honnête de
   cette déclaration.

5. **Pas de version audio de la documentation.** Le critère demande une
   documentation « lisible, audible » : l'audible repose ici sur la synthèse
   vocale du lecteur d'écran, pas sur un enregistrement. C'est un choix — un
   enregistrement dériverait du texte à la première mise à jour — mais c'en est
   un, et il est déclaré comme tel.

## 7. Signaler un problème d'accessibilité

Ouvrir une issue sur le dépôt du projet en décrivant le document concerné, la
technologie d'assistance utilisée et ce qui bloque. Les problèmes
d'accessibilité sont traités au même rang qu'un défaut fonctionnel.
