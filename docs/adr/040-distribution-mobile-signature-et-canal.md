# ADR 040 — Distribution mobile : signature Android dégradable, pas de canal iOS

**Date** : 2026-08-20
**Statut** : Accepté
**Ticket** : [STR-239](https://linear.app/streampulse/issue/STR-239)

---

## Contexte

Le sujet demande la mise en production **et** la distribution aux utilisateurs
(critères `Ce3.4.1` et `Ce3.4.2`). Le backend est déployé et joignable
(`https://api.streampulse.win/health` → 200) ; l'application mobile, elle,
n'était ni construite en CI, ni signable, ni distribuée nulle part.

Trois défauts se cumulaient :

1. `mobile/android/app/build.gradle.kts` conservait le TODO du template Flutter
   et signait la release avec **la clé de debug**. Le build « réussissait », ce
   qui rendait le défaut facile à ne jamais voir.
2. Aucune workflow ne construisait l'application. Ni Fastlane, ni TestFlight, ni
   Play Store, ni Firebase App Distribution.
3. Un APK compilé aurait embarqué le défaut `http://localhost:8080` et n'aurait
   joint aucune API.

## Décision

### 1. La signature Android **dégrade** au lieu d'échouer

Gradle lit la clé dans `android/key.properties`, puis dans les variables
d'environnement. **Quand aucune n'est disponible, le build de release retombe
sur la clé de debug** au lieu de s'arrêter.

Le repli est rendu bruyant à trois endroits : un message Gradle en niveau
`error`, un `::warning::` dans le résumé de la CI, et un suffixe `-NON-SIGNE`
sur l'APK.

**Une configuration partielle dégrade comme une absente.** Les quatre secrets
sont exigés, et une valeur vide compte comme absente des deux côtés. La première
version ne testait que la présence du keystore côté CI, et `!= null` côté
Gradle — or un secret GitHub non défini mais référencé dans un bloc `env:` est
exporté avec la **chaîne vide**, que `System.getenv` rend telle quelle. Poser la
clé en oubliant un mot de passe suffisait donc à signer avec un secret vide et à
casser le build sur une erreur `jarsigner` qui ne nommait rien : le mode dégradé
dégradait en panne dure, et l'avertissement n'orientait vers aucun secret
(revue PR #326).

**L'AAB n'est produit que s'il est signable.** Un `.aab` ne s'installe pas — il
n'est qu'un format d'upload — et signé en debug il serait refusé par le Play
Store. En mode dégradé il ne mène nulle part : l'attacher afficherait sur la
page de release un livrable trompeur. L'APK, lui, s'installe et sert au test.

### 2. Le job de build vit dans `cd.yml`, pas dans une workflow `on: release`

`release-please` publie la release avec `GITHUB_TOKEN`, et un événement émis par
ce jeton ne déclenche aucune workflow. Une workflow `on: release` ne se serait
jamais exécutée — et n'aurait rien signalé.

Le job est **épinglé sur le commit taggé** (`ref: tag_name`). Sans `ref`,
`checkout` prend la tête de la branche par défaut au moment du déclenchement :
deux merges qui s'enchaînent sur `main` suffisent alors à publier, sous
`vX.Y.Z`, un binaire bâti depuis un commit plus récent que `vX.Y.Z`. Même
correctif que celui appliqué à `build-and-push` en #314.

Une garde en tête de job vérifie que le tag est résolu. En mode manifest,
`releases_created` est fiable mais `tag_name` dépend de la façon dont l'action
expose ses sorties racine : une valeur vide passerait la condition du job et
n'échouerait qu'à l'upload, après trente minutes de build.

### 3. iOS n'est pas distribué

L'application se compile et s'exécute sur simulateur. Elle n'est livrée à
personne.

## Alternatives écartées

### Échouer le build quand la clé de signature manque

L'option la plus « propre » sur le papier : pas de clé, pas d'artefact.

Écartée parce qu'elle transforme l'absence d'un secret en panne d'équipe.
`flutter run --release` deviendrait impossible pour tous ceux qui n'ont pas la
clé — c'est-à-dire pour tout le monde sauf une personne — alors que ce mode sert
à mesurer les performances réelles et à reproduire les bogues qui ne se
manifestent qu'en release. La CI, elle, cesserait de produire le moindre
artefact tant que personne n'a généré la clé, ce qui empêcherait de vérifier la
chaîne de bout en bout avant qu'elle existe.

Un build qui échoue pour une raison d'infrastructure n'apprend rien. Un build
qui réussit **en le disant très fort** laisse la chaîne vérifiable et rend
l'écart impossible à confondre avec un succès.

### Committer un keystore de développement partagé

Pratique, et adopté par de nombreux projets pour les builds internes.

Écartée sans hésitation : une clé de signature dans un dépôt est une clé
publique. Qui la détient peut publier une mise à jour de l'application sous la
même identité. Le confort ne compense pas la perte définitive du contrôle sur
les mises à jour.

### Générer la clé automatiquement en CI

Techniquement possible — `keytool` dans un job.

Écartée parce qu'elle est pire que de ne pas signer : une clé régénérée à chaque
run produit des artefacts que **rien ne relie entre eux**. Android refusant un
changement de clé, chaque version serait ininstallable par-dessus la
précédente. On obtiendrait la couleur de la signature sans aucune de ses
propriétés.

### Publier sur une piste interne Play Store

C'est la cible naturelle et ce que le ticket appelle « idéalement ».

Écartée pour l'instant : elle demande un compte développeur Google (25 $ une
fois) et une fiche produit, deux choses hors du périmètre du projet d'étude. La
chaîne technique n'en est pas moins prête — un AAB signé est ce que le Play
Store attend, et c'est l'artefact que la release produit.

### TestFlight pour iOS

Le seul canal de distribution iOS pour des testeurs distants.

Écartée : il exige un compte Apple Developer à 99 €/an, dont l'équipe ne dispose
pas. Ce n'est pas une contrainte technique qu'on pourrait contourner — Apple ne
propose aucune voie gratuite pour installer une application sur un appareil
qu'on n'a pas en main.

### Distribuer un `.ipa` non signé

Envisagée pour « avoir quelque chose » côté iOS.

Écartée parce qu'un `.ipa` non signé ne s'installe sur aucun appareil. Produire
un artefact que personne ne peut utiliser, uniquement pour cocher une case,
serait un faux-semblant — et se défendrait moins bien qu'une absence assumée et
expliquée.

## Conséquences

**Positives**

- Un tag de release produit un APK — et un AAB dès que la clé existe — sans
  intervention manuelle, depuis le commit effectivement taggé.
- Activer la signature ne demande que d'ajouter quatre secrets — aucun code à
  changer.
- L'écart est visible partout où quelqu'un peut le rencontrer : build local,
  résumé de CI, nom de fichier, certificat.
- Le retour utilisateur est rattaché à une version via un formulaire dédié
  (`Ce3.4.3`).

**Négatives, et assumées**

- Aucun artefact distribuable tant que la clé n'est pas générée, et **aucun AAB
  du tout** dans cet état.
- Un testeur ayant installé une version `-NON-SIGNE` devra **désinstaller**
  avant la première version signée : Android refuse le changement de clé.
- iOS reste hors distribution. Le critère `Ce3.4.2` — « l'ensemble des
  plateformes » — n'est donc pas tenu sur cette plateforme, et le dire
  franchement vaut mieux que de produire un artefact inerte.
- Le job mobile ne s'exécute qu'à la publication d'une release : il n'a pas
  encore tourné en conditions réelles. Sa partie build est vérifiée localement
  (APK de 57,9 Mo, certificat `CN=Android Debug` conforme au mode dégradé).
