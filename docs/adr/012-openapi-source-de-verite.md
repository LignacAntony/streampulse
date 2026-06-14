# ADR 012 — OpenAPI comme source de vérité du contrat HTTP + client Flutter généré

**Date** : 2026-06-11
**Statut** : Accepté
**Ticket** : [STR-106](https://linear.app/streampulse/issue/STR-106)

---

## Contexte

Jusqu'ici, les contrats HTTP de l'auth étaient maintenus **à la main des deux côtés** :
sérialisation manuelle dans les handlers Go, et DTOs Dart écrits à la main
(`UserModel`, `TokenPairModel`) dans `mobile/lib/features/auth/data/models/`. Rien ne
garantissait que le backend et l'app restent synchronisés — un renommage de champ ou un
changement de type côté serveur ne se voyait qu'au runtime, sous forme d'erreur de parsing.

Il fallait :

1. Une **source de vérité unique** pour le contrat HTTP des routes déjà implémentées.
2. Une documentation interactive consultable pendant le développement.
3. Un **client Dart/Dio typé** dérivé de cette source, pour supprimer le drift et le
   boilerplate de (dé)sérialisation côté mobile.

L'architecture Go (handler / service / repository, [ADR 008](008-architecture-handler-service-repository.md))
et Flutter (Clean Architecture + provider, [ADR 005](005-architecture-flutter-clean.md)) ne
changent pas ; cet ADR couvre uniquement l'introduction d'OpenAPI et du pipeline de génération.

---

## Décision

### 1. Spec OpenAPI 3.0.3 statique, embarquée dans le binaire Go

Le contrat vit dans `backend/internal/openapi/openapi.yaml`, écrit à la main et embarqué via
`//go:embed`. La spec ne documente **que les routes réellement exposées aujourd'hui**
(`/health`, `/metrics`, les 6 routes `/api/auth/*`) — pas d'endpoint aspirationnel.

Un test (`openapi_test.go`) valide la spec au build via `kin-openapi` (`openapi3.Validate`),
plus des smoke-tests sur les handlers (YAML servi, redirection, UI).

- `additionalProperties: false` est conservé sur les **schémas de requête** (rejette les
  payloads parasites en entrée).
- `additionalProperties: false` est **retiré des schémas de réponse** : sinon la spec se
  contredirait dès l'ajout d'un champ en réponse côté backend, cassant tout consommateur
  strict ou test de contrat. Les réponses restent ouvertes à l'extension.

### 2. Documentation Swagger UI servie hors production uniquement

`backend/internal/openapi/openapi.go` expose trois handlers, montés dans `main.go` :

- `GET /swagger/openapi.yaml` — spec YAML brute,
- `GET /swagger/` — Swagger UI embarquée (`swaggest/swgui`),
- `GET /swagger` → redirection 308 vers `/swagger/`.

Ces handlers ne sont enregistrés **que si `!cfg.IsProd()`**. En production (`GO_ENV=production`),
la surface de l'API n'est pas publiée sur l'environnement public déployé par la CD.

### 3. Client Dart/Dio généré et vendoré dans le monorepo

`make generate-openapi-client` lance `openapitools/openapi-generator-cli:v7.23.0` (image Docker
**pinnée**) qui produit un package `dart-dio` + `json_serializable` dans
`mobile/packages/streampulse_api/`, déclaré comme dépendance locale (`path:`) de l'app.

- Les `*.g.dart` générés sont **commités volontairement** (négation ciblée dans `.gitignore`) :
  l'app et la CI compilent sans relancer `build_runner` ni Docker.
- Le post-traitement du `pubspec.yaml`/`analysis_options.yaml` généré (alignement des
  contraintes sur celles de l'app) est **gardé par des `grep` qui échouent bruyamment** si le
  template du générateur change, plutôt que de patcher silencieusement dans le vide.

### 4. Frontière data : DTO généré → entité domaine via mappers

La couche data manipule les DTOs générés (`UserResponse`, `TokenPairResponse`), mais la
conversion vers les entités domaine pures (`User`, `TokenPair`) est centralisée dans des
extensions `toEntity()` (`auth_dto_mappers.dart`). `AuthRepositoryImpl` reste mince et le
type généré ne fuit pas au-delà de la couche data. Les entités domaine **n'importent jamais**
le package généré (DIP, cf. [ADR 005](005-architecture-flutter-clean.md)).

Le `DioClient` existant ([ADR 009](009-authentification-flutter.md)) est réutilisé : `baseUrl`,
logs, injection du `Bearer` et refresh sérialisé sur 401 sont conservés. Le refresh passe par
le `_refreshDio` séparé (pas de récursion d'intercepteur).

---

## Alternatives considérées

### Conserver les DTOs Dart écrits à la main (statu quo)

- **Avantage** : zéro outillage, zéro dépendance Docker.
- **Rejet** : drift silencieux backend/mobile, boilerplate de (dé)sérialisation dupliqué,
  aucune doc interactive.

### Génération de la spec depuis des annotations Go (swaggo)

- **Avantage** : spec dérivée du code serveur, pas de fichier à maintenir séparément.
- **Rejet** : pollue les handlers d'annotations, et le générateur swaggo reste sur OpenAPI 2.0
  / un support 3.x partiel. Une spec statique relue à la main est plus lisible et sert
  directement de contrat au stade actuel (8 routes).

### Génération du client à la volée en CI (pas de `*.g.dart` commités)

- **Avantage** : aucun artefact généré dans le dépôt.
- **Rejet** : impose Docker + `build_runner` avant toute compilation de l'app et en CI,
  ralentit les builds et fragilise le pipeline. Commiter le généré rend l'app compilable
  immédiatement.

### Exposer Swagger UI dans tous les environnements

- **Avantage** : doc toujours accessible.
- **Rejet** : publie la surface complète de l'API sur l'environnement public. Gating sur
  `GO_ENV` pour ne l'exposer qu'en dev/test.

---

## Conséquences

### Avantages

- **Source de vérité unique** : le contrat HTTP est versionné, validé au build, et le client
  mobile en dérive mécaniquement.
- **Moins de boilerplate mobile** : (dé)sérialisation et signatures typées générées.
- **Doc interactive** en dev sans exposition en prod.
- **Builds rapides** : généré commité, pas de Docker/`build_runner` en CI.

### Inconvénients

- **Spec maintenue à la main** : toute nouvelle route doit être ajoutée à `openapi.yaml` puis
  le client régénéré. Discipline à tenir (à terme, envisager un test de cohérence routes↔spec).
- **Artefacts générés dans le dépôt** : `mobile/packages/streampulse_api/` gonfle les diffs à
  chaque régénération.
- **Post-traitement du pubspec généré** : dépend du format de sortie du générateur ; pinné en
  `v7.23.0` et gardé par `grep`, mais à revérifier lors d'un bump de version.

### Impact sur les tests

- **Backend** : `openapi_test.go` (validation spec + smoke handlers).
- **Mobile** : `auth_repository_impl_test.dart` mis à jour pour les DTOs générés ;
  `user_model_test.dart` supprimé (modèles faits main retirés).

---

## Références

- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture + provider côté Flutter.
- [ADR 008](008-architecture-handler-service-repository.md) — Architecture handler/service/repository Go.
- [ADR 009](009-authentification-flutter.md) — `DioClient`, refresh sérialisé, logout best-effort.
- `backend/internal/openapi/` — spec, handlers, test de validation.
- `Makefile` — cible `generate-openapi-client`.
- `mobile/packages/streampulse_api/` — client généré vendoré.
- `mobile/lib/features/auth/data/mappers/auth_dto_mappers.dart` — DTO → entité domaine.
