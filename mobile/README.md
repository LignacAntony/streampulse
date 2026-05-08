# StreamPulse — Application mobile Flutter

Application mobile (iOS · Android · Web) de la plateforme StreamPulse. Consomme l'API Go documentée dans [`../docs/architecture.md`](../docs/architecture.md).

L'architecture suit Clean Architecture + Riverpod, formalisée dans [ADR 005](../docs/adr/005-architecture-flutter-clean.md).

---

## Prérequis

| Outil | Version |
|---|---|
| Flutter | ≥ 3.27 (canal stable) |
| Dart | ≥ 3.4 |
| API backend StreamPulse | accessible sur `http://localhost:8080` (cf. [`../README.md`](../README.md)) |

```bash
flutter doctor
flutter --version
```

---

## Installation

```bash
cd mobile
flutter pub get
```

---

## Lancer l'application

L'URL de l'API est configurée à la compilation via la variable `API_BASE_URL`
(cf. `lib/core/constants/api_constants.dart`). Valeur par défaut :
`http://10.0.2.2:8080` (boucle vers `localhost` depuis l'émulateur Android).

### Émulateur Android

```bash
flutter run -d emulator-5554
```

### Simulateur iOS

```bash
flutter run -d <id-simulateur> \
  --dart-define=API_BASE_URL=http://localhost:8080
```

### Device physique (sur le même réseau Wi-Fi que le Mac)

```bash
# Remplacer 192.168.1.42 par l'IP locale du Mac (ipconfig getifaddr en0)
flutter run --dart-define=API_BASE_URL=http://192.168.1.42:8080
```

### Web (debug rapide)

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

---

## Configuration locale via `.env.json`

Plutôt que de retaper `--dart-define=...` à chaque lancement, le projet utilise
le mécanisme natif `--dart-define-from-file` (Flutter 3.7+).

1. Copier le template :
   ```bash
   cp mobile/.env.example.json mobile/.env.json
   ```
2. Éditer `mobile/.env.json` selon le device cible :
   ```json
   { "API_BASE_URL": "http://localhost:8080" }
   ```
3. Lancer :
   ```bash
   flutter run --dart-define-from-file=.env.json
   ```

### Android Studio / IntelliJ

`Run` → `Edit Configurations…` → champ **Additional run args** :

```
--dart-define-from-file=.env.json
```

Cocher **Store as project file** pour partager la config (`.run/main.dart.run.xml`).

`mobile/.env.json` est gitignoré (par device, par dev).
`mobile/.env.example.json` est versionné comme référence.

---

## Dev sur device Android physique branché en USB (recommandé)

Cette méthode bypass complètement Wi-Fi et firewall : `adb` crée un tunnel
USB de `localhost:8080` côté téléphone vers `localhost:8080` côté Mac.

### Prérequis (à faire une fois)

1. Activer le **mode développeur** sur le téléphone : Settings → À propos →
   tapper 7× sur "Numéro de build".
2. Activer **Débogage USB** : Settings → Options développeur → Débogage USB.
3. Brancher le téléphone en USB et **autoriser le PC** dans le popup
   "Autoriser le débogage USB ?".
4. Ajouter `adb` au PATH (`~/.zshrc` ou `~/.bashrc`) :
   ```bash
   export ANDROID_HOME="$HOME/Library/Android/sdk"
   export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
   ```
   Puis `source ~/.zshrc`. Vérifier : `adb version`.

### Lancement quotidien

1. Démarrer le backend :
   ```bash
   cd /chemin/vers/streampulse
   docker compose up -d
   until curl -sf http://localhost:8080/health > /dev/null; do sleep 2; done
   ```

2. Vérifier le device :
   ```bash
   adb devices
   # → R5CW21WXQ3K  device   (et pas "unauthorized")
   ```

3. Ouvrir le tunnel USB :
   ```bash
   adb reverse tcp:8080 tcp:8080
   adb reverse --list   # doit afficher "UsbFfs tcp:8080 tcp:8080"
   ```

4. S'assurer que `mobile/.env.json` pointe vers `localhost` :
   ```json
   { "API_BASE_URL": "http://localhost:8080" }
   ```

5. Run depuis Android Studio (▶️) ou CLI :
   ```bash
   flutter run --dart-define-from-file=.env.json
   ```

### Pièges fréquents

| Symptôme | Cause | Fix |
|---|---|---|
| `adb: command not found` | PATH | Ajouter `$ANDROID_HOME/platform-tools` au PATH |
| `device unauthorized` | Popup pas validé | Re-brancher le câble, accepter "Autoriser ce PC" |
| `No route to host` | Pas de tunnel | Re-run `adb reverse tcp:8080 tcp:8080` après chaque replug |
| `Cleartext HTTP traffic not permitted` | Android 9+ block | `usesCleartextTraffic="true"` déjà activé dans `AndroidManifest.xml` (dev only) |
| Tunnel perdu après debranchement | Comportement normal d'`adb` | Re-run la commande `adb reverse` à chaque replug |

⚠️ `usesCleartextTraffic="true"` est OK en dev mais doit être remplacé par
un `network_security_config.xml` scopé en prod (HTTPS only).

---

## Tests & analyse

```bash
flutter analyze                  # lint statique
flutter test                     # tests unitaires + widgets
flutter test --coverage          # tests + génération coverage/lcov.info
```

---

## Structure du code

```
mobile/lib/
├── app/                    # Composition racine + routeur
│   ├── app.dart            # MaterialApp.router
│   └── router/             # GoRouter + redirect auth
├── core/                   # Utilitaires partagés (no feature ↔ feature)
│   ├── constants/          # API endpoints, durées, breakpoints
│   ├── errors/             # Exceptions / Failures
│   ├── network/            # DioClient + interceptors (auth, logs)
│   ├── storage/            # SecureStorage (tokens JWT)
│   └── theme/              # Palette + typographie + ThemeData
└── features/<feature>/     # Une feature = un dossier indépendant
    ├── data/               # Datasources (HTTP/local) + models JSON + repo impl
    ├── domain/             # Entités pures + interface repository (Principe D)
    └── presentation/       # Widgets, screens, providers Riverpod
```

Le pattern data / domain / presentation est imposé par [ADR 005](../docs/adr/005-architecture-flutter-clean.md).

---

## Feature `auth` — état actuel

| Élément | Référence |
|---|---|
| Écran d'inscription | `lib/features/auth/presentation/screens/register_screen.dart` (route `/register`) |
| Validation formulaire | `lib/features/auth/presentation/utils/register_validators.dart` (testée à part) |
| Client HTTP | `lib/features/auth/data/datasources/auth_remote_data_source.dart` |
| Repository | `lib/features/auth/data/repositories/auth_repository_impl.dart` |
| Controller Riverpod | `lib/features/auth/presentation/providers/register_controller.dart` |
| Endpoint backend consommé | `POST /api/auth/register` |

Mapping des erreurs serveur :

| Code HTTP | Exception levée | UI |
|---|---|---|
| 201 | — | SnackBar « Compte créé » + redirect `/login` |
| 400 | `ValidationException` | SnackBar avec le message renvoyé par l'API |
| 409 | `DuplicateAccountException` | SnackBar « email or username already taken » |
| 5xx | `ServerException` | SnackBar « Erreur serveur (xxx) » |
| Timeout / offline | `NetworkException` | SnackBar « Pas de connexion réseau » |

---

## Conventions

- **Lint** : `flutter_lints` + règles supplémentaires dans `analysis_options.yaml`. Aucun warning toléré (`flutter analyze` doit être vert).
- **State management** : Riverpod 2.x (`flutter_riverpod`, `AsyncNotifier` pour les flux asynchrones).
- **Navigation** : `go_router`. Routes publiques (sans token) déclarées dans la liste `_publicRoutes` de `app/router/app_router.dart`.
- **Stockage des tokens** : `flutter_secure_storage` (Keychain iOS / EncryptedSharedPreferences Android).
- **Tests** : un fichier `<truc>_test.dart` par classe métier ; widget tests pour les écrans (clés `Key('...')` stables pour cibler les widgets).

---

## Dépannage

**Erreur réseau côté Android émulateur** : `10.0.2.2` est l'alias localhost. Si l'API tourne sur un autre port, override via `--dart-define=API_BASE_URL=http://10.0.2.2:<port>`.

**Erreur réseau côté iOS simulateur** : utiliser `localhost` directement (`--dart-define=API_BASE_URL=http://localhost:8080`).

**Erreur 415 sur `/api/auth/register`** : le client doit envoyer `Content-Type: application/json`. Le `DioClient` le fait automatiquement (cf. `BaseOptions.headers`).
