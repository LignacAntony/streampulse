# ADR 013 — Domaine streaming : stream_key, CRUD des flux et soft delete

**Date** : 2026-06-18 (mis à jour le 2026-06-27)
**Statut** : Accepté
**Ticket** : [STR-64](https://linear.app/streampulse/issue/STR-64) (sous-issues STR-65 à STR-69)

---

## Contexte

STR-64 ouvre la milestone **« Moteur de Streaming Live (Backend Go) »**. L'US couvre la
**création, la configuration et la gestion CRUD** d'un flux live par un diffuseur (titre,
description, visibilité) **avant** la diffusion. Le flux est persisté avec un statut initial, un
identifiant unique, et le diffuseur récupère une **URL de stream source** vers laquelle pousser.

La table `streams` existe déjà (migration `000002`) : `id`, `user_id`, `title`, `description`,
`category`, `status` (`idle | live | ended`), `is_public`, `started_at`, `ended_at`, timestamps.
Elle portait `UNIQUE (user_id, title)` (migration `000006`) — **contrainte retirée** ici (cf.
décision 5).

Le CDC (§4.3) fixe le transport d'ingest : **pas de RTMP** — le client diffuseur pousse l'audio
brut via un endpoint HTTP, et le backend Go segmente en HLS. L'URL de stream source est donc un
**endpoint HTTP du backend** (implémenté dans une US ultérieure de la milestone).

---

## Décision

### 1. `stream_key` dédié, stocké en clair, pour l'URL de stream source

- Migration `000012` : ajoute `stream_key TEXT NOT NULL UNIQUE` sur `streams`.
- Généré à la création : **32 octets `crypto/rand` → base64url** (sans padding).
- Stocké **en clair** : le diffuseur doit pouvoir **relire** son URL source dans son dashboard
  (modèle Twitch/OBS). Un hachage rendrait l'URL illisible après la création.
- URL renvoyée : `{STREAM_INGEST_BASE_URL}/api/streams/ingest/{stream_key}` — nouvelle variable
  d'environnement (12-Factor, cf. ADR 004), défaut dev `http://localhost:8080`.
- **Le `stream_key` (et l'URL source) n'est jamais exposé à un tiers** : ni dans la liste, ni
  dans la vue d'un flux dont le demandeur n'est pas propriétaire.
- **Sécurité** : un secret en clair en base implique qu'une lecture DB expose toutes les clés
  (risque **accepté pour le MVP**). Régénération et chiffrement at-rest = tickets ultérieurs.

### 2. Statut initial `idle`

Le ticket emploie « inactif » ; le schéma utilise déjà `idle` (`CHECK status IN
('idle','live','ended')`). On **garde `idle`** (= inactif), aucune migration d'enum.

### 3. Rôles & propriété

- **Création** réservée au rôle `broadcaster` (`RequireRole`).
- **Lecture/édition/suppression** : `RequireAuth` ; la **propriété est vérifiée dans le service**
  (un flux ne peut être modifié/supprimé que par son propriétaire).
- La **promotion `user → broadcaster` est hors scope** (aucun endpoint aujourd'hui) → ticket
  dédié, tracé dans `docs/cdc-conflits-codebase.md`.

### 4. Surface HTTP (CRUD)

| Méthode | Route | Auth | Comportement |
|---|---|---|---|
| `POST` | `/api/streams` | broadcaster | crée un flux `idle`, **201** objet complet (+ `stream_key` + `stream_source_url`) |
| `GET` | `/api/streams` | auth | liste paginée (`?limit`=20 max 100, `?offset`) des flux `is_public AND status='live' AND archived_at IS NULL`, **résumés sans secret** |
| `GET` | `/api/streams/{id}` | auth | propriétaire → objet complet ; autre + public → résumé ; autre + privé / archivé / absent → **404** |
| `PUT` | `/api/streams/{id}` | auth, owner | remplacement complet (`title` + `is_public` requis, `description`/`category` optionnels), **404** sinon |
| `DELETE` | `/api/streams/{id}` | auth, owner | soft delete, **204**, **404** sinon |

- **Validation** (STR-68) : `title` 3–120 (trimé), `description` ≤ **500**, `category` dans une
  liste blanche, `is_public` booléen. `additionalProperties: false` sur les requêtes.
- Routage en **patterns méthode** `http.ServeMux` (Go 1.22+) ; l'`id` du path est lu via
  `r.PathValue("id")` et converti sans paniquer (un UUID invalide → 404).

### 5. Titre non unique + soft delete (migration `000013`)

- **DROP de `UNIQUE (user_id, title)`** : le titre d'un flux n'a pas à être unique. Un diffuseur
  ne peut pas diffuser plusieurs flux en même temps (règle appliquée au passage en `live`, hors
  scope), peut réutiliser un nom dans le temps, et deux diffuseurs peuvent partager un titre (on
  différencie par le diffuseur). Conséquence : **aucun 409 sur le titre**, ni à la création ni à
  la mise à jour.
- **Soft delete** : colonne `archived_at TIMESTAMPTZ` (NULL = actif). `DELETE` pose
  `archived_at = NOW()` au lieu d'effacer la ligne ; **toutes les lectures filtrent
  `archived_at IS NULL`**. Nom `archived_at` (pas `deleted_at`) : « archivé » colle mieux à un
  flux passé. Index partiel `idx_streams_public_live` pour la liste.

### 6. Structure : handler / service / repository (ADR 008)

Le domaine `streaming` suit la convention **handler / service / repository**
([ADR 008](008-architecture-handler-service-repository.md)), comme `auth` et `profiles` :

```
internal/streaming/
├── handler.go      # HTTP stdlib : décodage, validation surface, codes statut, vues complète/résumé
├── service.go      # types domaine (Stream), validation, interfaces Repository/KeyGenerator, logique métier (propriété)
├── repository.go   # accès PostgreSQL via sqlc, conversions pgtype, parseUUID des ids du path
├── keygen.go       # génération du stream_key (crypto/rand)
├── queries/ + db/  # SQL annoté + code sqlc généré
└── *_test.go       # tests stdlib (fakeRepo / fakeKeys / stub handler)
```

La Clean Architecture / DDD du CDC (§4.2) **n'est pas adoptée** ici, pour rester cohérent avec le
reste du backend et éviter le boilerplate usecase (cf. ADR 008). Écart tracé dans
`docs/cdc-conflits-codebase.md`.

---

## Alternatives considérées

- **URL = `id` + auth JWT** : rejeté — JWT (exp. 15 min) inadapté à un push long, pas de secret
  régénérable indépendamment du compte.
- **`stream_key` haché** : rejeté — le diffuseur ne pourrait jamais relire son URL source.
- **Garder l'unicité du titre** : rejeté — pas de sens métier (cf. décision 5).
- **Hard delete** : rejeté — on conserve l'historique via `archived_at` (soft delete).
- **Migrer l'enum vers `inactive`** : rejeté — casse l'existant pour un gain nul.
- **Clean Architecture / DDD + Gin/GORM du CDC** : rejeté — incohérent avec `auth`/`profiles`.

---

## Conséquences

### Avantages

- Surface CRUD complète, **isolée et testable** : tests par couche sans DB (fakeRepo / fakeKeys /
  stub handler) ; chaîne `RequireAuth`/`RequireRole` réelle dans les tests handler.
- URL de stream source **stable et lisible** ; secrets jamais exposés à un tiers.
- **Zéro dépendance nouvelle lourde**, cohérence avec `auth`/`profiles` (stdlib, sqlc, apperror,
  httpjson, middleware `auth`, pool `pgx`).

### Inconvénients

- **Clé en clair** en base (risque accepté MVP).
- **Promotion broadcaster manquante** : un `user` normal ne peut pas créer de flux.
- **Soft delete** : toute nouvelle requête de lecture doit penser à filtrer `archived_at IS NULL`.

---

## Références

- [ADR 008](008-architecture-handler-service-repository.md) — handler/service/repository.
- [ADR 007](007-sqlc-generation-code-sql.md) — sqlc. [ADR 004](004-config-12-factor-viper.md) — config 12-Factor.
- [ADR 012](012-openapi-source-de-verite.md) — OpenAPI source de vérité du contrat HTTP.
- Migrations `000012` (stream_key) et `000013` (drop unicité titre + archived_at).
- `docs/cdc-conflits-codebase.md` — conflits CDC ↔ codebase + suivis hors scope.
