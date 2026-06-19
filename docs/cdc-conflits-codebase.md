# Conflits CDC ↔ Codebase

Ce document recense les points où le **CDC (brouillon brainstorm)** diverge de l'état réel du
code. Le CDC a été rédigé en amont ; le code a depuis fixé des conventions (ADR 004 à 013). La
règle est d'**adapter le CDC au code**, pas l'inverse — sauf décision explicite consignée en ADR.

Établi pendant [STR-64](https://linear.app/streampulse/issue/STR-64). À tenir à jour à chaque
nouveau conflit détecté.

---

## 1. Conflits à réécrire dans le CDC

| Sujet | Le CDC dit | Le code fait | Action |
|---|---|---|---|
| Architecture backend | Clean Architecture + DDD global (§4.2) | **handler / service / repository** par feature (ADR 008) | Réécrire le CDC → handler/service/repository |
| Framework HTTP | Gin ou Chi (§3.2.1, §4.2) | `stdlib net/http` + `http.ServeMux` | Réécrire le CDC → stdlib |
| Accès base de données | GORM ou sqlx (§3.2.1) | **sqlc** (queries SQL → Go typé, ADR 007) | Réécrire le CDC → sqlc |
| Layout des packages | `internal/domain/`, `internal/application/`, `internal/transport/http/` (§4.2) | feature-first : `internal/<feature>/` (`auth`, `profiles`, `streaming`) | Réécrire le CDC → feature-first |
| Point d'entrée | `cmd/server/` (§4.2) | `cmd/api/` | Réécrire le CDC → `cmd/api/` |
| Statut de flux « inactif » | Flux créé « inactif » (ticket STR-64) | Enum `idle \| live \| ended`, défaut `idle` | Garder `idle` = inactif ; corriger le wording du CDC/ticket |

Le domaine `streaming` (STR-64) suit la même convention `handler/service/repository` que le reste
du backend (cf. [ADR 013](adr/013-domaine-streaming.md)) — il n'y a donc **pas** de divergence
d'architecture interne à réconcilier, seulement le texte du CDC à mettre à jour.

## 2. Suivis (tickets dédiés)

- [ ] **Promotion `user → broadcaster`** : aucun endpoint n'existe ; seuls les broadcasters
  seedés/admin peuvent créer un flux. Nécessaire pour qu'un compte standard devienne diffuseur.
- [ ] **Régénération + durcissement du `stream_key`** : aujourd'hui en clair (risque MVP accepté,
  ADR 013) ; prévoir régénération côté diffuseur et chiffrement at-rest.

## 3. À auditer ultérieurement

Sections du CDC non encore confrontées au code (observabilité OTEL, logger zerolog/zap, moteur
HLS `gohlslib`, WebSocket chat). À vérifier au fil des tickets de la milestone streaming.
