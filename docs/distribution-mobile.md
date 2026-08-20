# Distribution de l'application mobile

Comment l'application Android est construite, signée et livrée — et pourquoi
iOS ne l'est pas.

**Documents liés** — [adr/040-distribution-mobile-signature-et-canal.md](adr/040-distribution-mobile-signature-et-canal.md)
(la décision et ses alternatives), [manuel-utilisateur.md](manuel-utilisateur.md)
(installation côté utilisateur), [infrastructure.md](infrastructure.md).

---

## 1. Ce qui se passe à chaque release

`release-please` publie une release à partir des Conventional Commits, puis le
job `mobile` de la workflow **CD** construit et attache deux artefacts :

| Artefact | À quoi il sert |
|---|---|
| `streampulse-vX.Y.Z.aab` | Android App Bundle — le format attendu par le Play Store |
| `streampulse-vX.Y.Z.apk` | Installation directe sur un appareil, sans magasin |

Les deux sont construits avec `--dart-define=API_BASE_URL=https://api.streampulse.win`.
Sans ce passage, l'application embarquerait son défaut de développement
(`http://localhost:8080`) et ne joindrait aucune API une fois installée.

> Le job est une étape de `cd.yml` et non une workflow déclenchée par
> `on: release`. `release-please` publie la release avec `GITHUB_TOKEN`, et un
> événement émis par ce jeton **ne déclenche aucune workflow** : un
> `on: release` ne se serait jamais exécuté, sans rien signaler.

## 2. Signature — état actuel

**La clé de release n'existe pas encore.** Tant qu'elle manque, la chaîne
fonctionne en **mode dégradé** :

- le build **réussit**, signé avec la clé de debug ;
- les artefacts sont suffixés **`-NON-SIGNE`** ;
- Gradle émet un avertissement en `error` pendant le build ;
- la CI émet un `::warning::` visible sur le résumé du run.

Un tel artefact s'installe et se teste, mais il est **refusé par le Play Store**.

Le repli est délibéré. L'alternative — échouer quand la clé manque — bloquerait
toute release et interdirait `flutter run --release` à quiconque n'a pas la clé,
c'est-à-dire à toute l'équipe. Un build qui échoue pour une raison
d'infrastructure n'apprend rien ; un build qui réussit en le disant très fort,
si.

⚠️ **Un artefact signé en debug ne pourra jamais être mis à jour par une
version signée** : Android refuse un changement de clé de signature. Les
testeurs devront désinstaller avant d'installer la première version signée.

## 3. Activer la signature

À faire **une fois**, par la personne qui détiendra la clé.

> La clé de signature n'est pas un secret de plus. Qui la détient contrôle
> toutes les mises à jour futures de l'application ; la perdre interdit
> définitivement de mettre à jour une application publiée sous la même
> identité. Elle ne doit jamais entrer dans le dépôt.

### 3.1 Générer le keystore

```bash
keytool -genkey -v \
  -keystore ~/streampulse-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias streampulse
```

Conserver le fichier **et** les mots de passe hors du dépôt, sauvegardés
ailleurs que sur le poste qui les a créés.

### 3.2 Déclarer les secrets GitHub

**Settings → Secrets and variables → Actions** :

| Secret | Contenu |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/streampulse-release.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Mot de passe du keystore |
| `ANDROID_KEY_ALIAS` | `streampulse` |
| `ANDROID_KEY_PASSWORD` | Mot de passe de la clé |

Rien d'autre à modifier : le job détecte la présence de
`ANDROID_KEYSTORE_BASE64` et bascule seul. Le suffixe `-NON-SIGNE` disparaît.

### 3.3 Signer depuis un poste de développement

Créer `mobile/android/key.properties` — déjà couvert par le `.gitignore` :

```properties
storeFile=/chemin/absolu/vers/streampulse-release.jks
storePassword=…
keyAlias=streampulse
keyPassword=…
```

Gradle lit ce fichier en premier, puis retombe sur les variables
d'environnement `ANDROID_KEYSTORE_*`.

## 4. Vérifier ce qui a été produit

```bash
apksigner verify --print-certs streampulse-vX.Y.Z.apk
```

- `CN=Android Debug` → artefact **non distribuable**
- Le nom déclaré à la génération → artefact signé

## 5. iOS

**Non distribué, et c'est une décision assumée**, pas un oubli. Le détail et
les alternatives écartées sont dans
[l'ADR 040](adr/040-distribution-mobile-signature-et-canal.md).

En deux lignes : TestFlight exige un compte Apple Developer payant, dont
l'équipe ne dispose pas. Aucune autre voie ne permet de distribuer une
application iOS à des utilisateurs qui ne sont pas devant la machine de build.
L'application **se compile et s'exécute** sur simulateur ; elle ne se distribue
pas.

## 6. Retour des utilisateurs

Chaque release affiche le canal de retour dans ses notes, et le dépôt porte un
formulaire dédié (**Issues → Retour utilisateur**) qui demande la version
installée. Sans ce champ, un retour n'est pas rattachable à une version, et
« ça ne marche pas » devient intraçable.

## 7. Ce qui manque encore

1. **Aucune clé de signature générée** — tout ce qui précède fonctionne en mode
   dégradé tant que c'est le cas.
2. **Aucun magasin.** Les artefacts vivent dans les GitHub Releases. Une piste
   interne Play Store ou Firebase App Distribution demanderait un compte
   développeur Google (25 $ une fois) et n'a pas été ouverte.
3. **Aucune distribution iOS**, cf. § 5.
4. **Le job mobile n'a jamais tourné en conditions réelles** : il ne se
   déclenche que sur une release, et aucune n'a été publiée depuis son ajout.
   La partie build est en revanche vérifiée localement — APK de 57,9 Mo produit,
   certificat inspecté.
