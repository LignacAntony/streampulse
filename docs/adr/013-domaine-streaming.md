# ADR 013 — Domaine streaming : ingest HLS et stream_key

**Date** : 2026-06-18
**Statut** : Accepté
**Ticket** : [STR-64](https://linear.app/streampulse/issue/STR-64)

---

## Contexte

STR-64 ouvre la milestone **« Moteur de Streaming Live (Backend Go) »**. C'est le premier
endpoint du domaine : un diffuseur crée et configure un flux live (titre, description,
visibilité) **avant** de diffuser. Le flux est persisté avec un statut initial, un identifiant
unique, et le diffuseur récupère une **URL de stream source** vers laquelle pousser son flux.

La table `streams` existe déjà (migration `000002`) : `id`, `user_id`, `title`, `description`,
`category`, `status` (`idle | live | ended`), `is_public`, `started_at`, `ended_at`, timestamps,
plus `UNIQUE (user_id, title)` (migration `000006`). Il manque cependant de quoi **matérialiser
l'URL de stream source**.

Le CDC (§4.3) fixe le transport d'ingest : **pas de RTMP** — le client diffuseur pousse l'audio
brut via un endpoint HTTP, et le backend Go segmente en HLS (`.ts` + manifeste `.m3u8`). L'URL de
stream source est donc un **endpoint HTTP du backend**, pas une URL RTMP externe.

---

## Décision

### 1. `stream_key` dédié, stocké en clair, pour l'URL de stream source

- Migration `000012` : ajoute `stream_key TEXT NOT NULL UNIQUE` sur `streams`.
- Généré à la création : **32 octets `crypto/rand` → base64url** (sans padding).
- Stocké **en clair** : le diffuseur doit pouvoir **relire** son URL source dans son dashboard
  (modèle Twitch/OBS). Un hachage rendrait l'URL illisible après la création.
- URL renvoyée :
  `{STREAM_INGEST_BASE_URL}/api/streams/ingest/{stream_key}`
  — nouvelle variable d'environnement (12-Factor, cf. ADR 004), défaut dev `http://localhost:8080`.
- **Sécurité** : un secret en clair en base implique qu'une lecture DB expose toutes les clés
  (risque **accepté pour le MVP**). La régénération de clé et le durcissement (chiffrement
  at-rest) sont des tickets ultérieurs.

### 2. Statut initial `idle`

Le ticket emploie le mot « inactif » ; le schéma existant utilise déjà `idle`
(`CHECK status IN ('idle','live','ended')`). On **garde `idle`** (= inactif), aucune migration
d'enum. Le mapping `inactif → idle` est documenté dans `docs/cdc-conflits-codebase.md`.

### 3. Création réservée au rôle `broadcaster`

`POST /api/streams` est protégé par `RequireAuth` + `RequireRole("broadcaster")`. Un compte
`user` ne peut pas créer de flux. La **promotion `user → broadcaster` est hors scope** (aujourd'hui
seuls les broadcasters seedés / promus par un admin existent ; aucun endpoint de promotion) →
ticket dédié, tracé dans `docs/cdc-conflits-codebase.md`.

### 4. Contrat `POST /api/streams`

- **Request** : `{ title (3–120), description? (≤ 2000), is_public (bool), category? (liste blanche) }`,
  `additionalProperties: false`.
- **Response 201** : objet `stream` complet, incluant `stream_key` **et** `stream_source_url`.
- Titre dupliqué pour un même diffuseur (`UNIQUE (user_id, title)`) → **409 Conflict** (le
  repository convertit `pgerrcode.UniqueViolation` en erreur de domaine, cf. ADR 008).

### 5. Structure : handler / service / repository (ADR 008)

Le domaine `streaming` suit la convention **handler / service / repository** du projet
([ADR 008](008-architecture-handler-service-repository.md)), comme `auth` et `profiles` :

```
internal/streaming/
├── handler.go      # HTTP stdlib : décodage, validation surface, codes statut, URL source
├── service.go      # types domaine (Stream), validation, interfaces Repository + KeyGenerator, CreateStream
├── repository.go   # accès PostgreSQL via sqlc, conversion 23505 → apperror.Conflict
├── keygen.go       # génération du stream_key (crypto/rand)
├── queries/ + db/  # SQL annoté + code sqlc généré
└── *_test.go       # tests stdlib (fakeRepo / fakeKeys / stub handler)
```

Le CDC (§4.2) évoquait une Clean Architecture / DDD à part : elle **n'est pas adoptée** ici, pour
rester cohérent avec le reste du backend et éviter le boilerplate usecase jugé disproportionné
(cf. alternative rejetée dans l'ADR 008). L'écart CDC ↔ code est tracé dans
`docs/cdc-conflits-codebase.md`.

---

## Alternatives considérées

- **URL = `id` + auth JWT** : rejeté — le JWT (exp. 15 min) est inadapté à un push long, et il
  n'offre pas de secret régénérable indépendamment du compte.
- **`stream_key` haché** (comme `refresh_tokens`) : rejeté — le diffuseur ne pourrait jamais
  relire son URL source → mauvaise UX pour un dashboard de diffusion.
- **Migrer l'enum vers `inactive`** : rejeté — casse l'existant (schéma + seeder) pour un gain
  sémantique nul.
- **Clean Architecture / DDD + Gin/GORM du CDC** : rejeté — incohérent avec `auth`/`profiles`,
  boilerplate disproportionné et dépendances lourdes pour ce domaine. On suit l'ADR 008.

---

## Conséquences

### Avantages

- URL de stream source **stable, lisible et régénérable** (régénération en ticket futur).
- Domaine **isolé et testable** : tests par couche sans DB (fakeRepo / fakeKeys / stub handler).
- **Zéro dépendance nouvelle lourde** et **cohérence** avec `auth`/`profiles` : on réutilise
  `stdlib`, `sqlc`, `apperror`, `httpjson`, le middleware `auth` et le pool `pgx` existants.

### Inconvénients

- **Clé en clair** en base (risque accepté MVP).
- **Promotion broadcaster manquante** : un `user` normal ne peut pas créer de flux tant que le
  ticket dédié n'est pas livré.

---

## Références

- [ADR 008](008-architecture-handler-service-repository.md) — handler/service/repository (convention suivie).
- [ADR 007](007-sqlc-generation-code-sql.md) — génération du code SQL via sqlc.
- [ADR 004](004-config-12-factor-viper.md) — configuration 12-Factor (`STREAM_INGEST_BASE_URL`).
- [ADR 012](012-openapi-source-de-verite.md) — OpenAPI source de vérité du contrat HTTP.
- `docs/cdc-conflits-codebase.md` — conflits CDC ↔ codebase + suivis hors scope.
- CDC §4.3 — moteur de streaming HLS.
