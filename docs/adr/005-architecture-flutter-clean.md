# ADR 005 — Architecture Flutter : Clean Architecture + Riverpod

> **SUPERSEDED (partiellement) par [ADR 036 — `provider` plutôt que Riverpod](036-state-management-flutter-provider.md).**
>
> Le volet **state management** ci-dessous — Riverpod, `riverpod_annotation`, « Riverpod
> Notifiers », et le rejet du package `provider` en fin de document — **ne décrit plus le code
> livré**. Riverpod a bien été utilisé du 2026-05-04 au 2026-06-04, puis **interdit par l'équipe
> pédagogique** : la couche présentation a été migrée vers `provider` + `ChangeNotifier`
> (`8e912ec`). Le motif, le coût assumé et les compensations sont dans
> l'[ADR 036](036-state-management-flutter-provider.md).
>
> Tout le reste de cette ADR **reste en vigueur** : Clean Architecture par feature,
> `go_router`, `just_audio` / `audio_service`, `dio`, `flutter_secure_storage`.
>
> Le texte d'origine est conservé **tel quel** : une ADR est un journal de décisions, pas une
> description de l'état courant. La décision a bien été prise ainsi, puis révisée.

**Date** : 2026-05-04  
**Statut** : ~~Accepté~~ → **Superseded by [ADR 036](036-state-management-flutter-provider.md)** (2026-08-19) sur le volet state management  
**Ticket** : STR-92 (US-01-06 — Initialisation du projet Flutter mobile)

---

## Contexte

StreamPulse est une plateforme audio hybride avec deux modes majeurs : live streaming (HLS) et
bibliothèque à la demande. L'application mobile doit gérer des états complexes (lecture audio,
connexion WebSocket, authentification JWT avec refresh) tout en restant maintenable et testable.

Nous ciblons iOS et Android uniquement. L'équipe est composée de développeurs Flutter juniors
à seniors, et l'architecture doit guider naturellement les contributions futures.

---

## Décision

Adopter la **Clean Architecture** adaptée mobile, avec **Riverpod** (+ `riverpod_annotation`)
comme solution de state management, et **go_router** pour la navigation déclarative.

### Structure retenue

```
features/<nom>/
├── data/repositories/     # Implémentations concrètes
├── domain/
│   ├── entities/          # Entités pures (pas de dépendances infra)
│   ├── repositories/      # Interfaces abstraites (Principe D)
│   └── usecases/          # Logique métier isolée
└── presentation/
    ├── screens/           # Widgets Flutter
    └── providers/         # Riverpod Notifiers
```

### Packages retenus

| Package | Version | Justification |
|---|---|---|
| `flutter_riverpod` + `riverpod_annotation` | ^2.5.1 / ^2.3.5 | State management déclaratif, code generation, testabilité native |
| `go_router` | ^14.2.0 | Navigation déclarative type-safe, deep linking, redirect hooks |
| `just_audio` | ^0.9.40 | Lecture HLS native iOS/Android, gestion de files de lecture |
| `audio_service` | ^0.18.12 | Background audio, contrôles système (lockscreen, notification) |
| `dio` | ^5.4.3+1 | Intercepteurs JWT (refresh token automatique), multipart upload |
| `flutter_secure_storage` | ^9.0.0 | EncryptedSharedPreferences Android, Keychain iOS |
| `equatable` | ^2.0.5 | Comparaison structurelle des entités sans boilerplate |
| `freezed_annotation` | ^2.4.1 | Data classes immutables, sealed classes pour les états |

---

## Principes SOLID appliqués

- **S** : chaque classe a une responsabilité unique (`SecureStorage` = tokens, `DioClient` = HTTP)
- **O** : `Failure` est extensible sans modification de la classe abstraite
- **L** : tous les sous-types de `Failure` sont substituables
- **I** : `AuthRepository` expose uniquement les méthodes nécessaires par feature
- **D** : `DioClient` reçoit `SecureStorage` par injection, pas d'instanciation interne

---

## Alternatives considérées

### BLoC / Cubit (flutter_bloc)
- **Pour** : architecture éprouvée, séparation stricte Events/States
- **Contre** : verbosité importante (un fichier par event/state), courbe d'apprentissage élevée,
  moins adapté aux providers réactifs imbriqués du streaming audio

### GetX
- **Pour** : peu de boilerplate, routes déclaratives intégrées
- **Contre** : couplage fort entre navigation, état et dépendances — violation des principes SOLID.
  Difficile à tester unitairement. Anti-pattern pour les équipes multi-développeurs.

### Provider simple (provider package)
- **Pour** : simple, officiel Flutter
- **Contre** : pas de code generation, gestion manuelle des dépendances entre providers,
  moins performant sur les invalidations sélectives (Riverpod résout ces problèmes)

---

## Conséquences

### Positives
- Séparation claire des responsabilités → chaque couche est testable indépendamment
- La couche `domain/` est agnostique framework : les entités et use cases ne dépendent que de Dart
- Riverpod génère le code des providers → moins d'erreurs, meilleur tooling IDE
- go_router simplifie la gestion des redirections conditionnelles (auth guards)

### Contraintes
- **Code generation obligatoire** avant de lancer l'app :
  ```bash
  flutter pub run build_runner build --delete-conflicting-outputs
  ```
- Les fichiers `*.g.dart` et `*.freezed.dart` sont dans `.gitignore` — chaque développeur
  doit les générer localement
- L'ajout d'un use case ou d'un repository demande de créer plusieurs fichiers (overhead initial)
  mais garantit la maintenabilité à long terme

---

## Références

- [Documentation Riverpod](https://riverpod.dev)
- [go_router documentation](https://pub.dev/packages/go_router)
- [Clean Architecture — Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- ADR 003 — CI/CD GitHub Actions (pipeline Flutter intégré)
