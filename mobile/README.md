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
