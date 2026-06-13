# Architecture — StreamPulse

## Vue d'ensemble

StreamPulse est une application de streaming multi-plateforme composée d'un client Flutter,
d'une API REST en Go et d'une infrastructure d'observabilité complète basée sur la stack LGTM.

---

## Schéma d'architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         CLIENT                                      │
│                                                                     │
│   ┌─────────────────────────────────────────┐                       │
│   │           Application Flutter           │                       │
│   │  (iOS · Android · Web)                  │                       │
│   └──────────────────┬──────────────────────┘                       │
│                      │ HTTPS / REST                                 │
└──────────────────────┼──────────────────────────────────────────────┘
                       │
                       ▼ :8080
┌─────────────────────────────────────────────────────────────────────┐
│                      RÉSEAU INTERNE : streampulse-net               │
│                                                                     │
│   ┌────────────────────────────────────┐                            │
│   │            API Go (REST)           │                            │
│   │         api:8080                   │──────────────────────┐     │
│   └────────────┬───────────────────────┘      traces OTLP     │     │
│                │ SQL                           (gRPC :4317)   │     │
│                ▼ :5432                                        ▼     │
│   ┌────────────────────────┐           ┌────────────────────────┐   │
│   │   PostgreSQL 16        │           │   Tempo :3200          │   │
│   │   (postgres_data vol.) │           │   (traces distribuées) │   │
│   └────────────────────────┘           └────────────────────────┘   │
│                                                                     │
│   ┌──────────────────────────────────────────────────────────────┐  │
│   │                    STACK OBSERVABILITÉ                       │  │
│   │                                                              │  │
│   │  Prometheus :9090 ◄──── scrape /metrics ──── api:8080        │  │
│   │       │                                                      │  │
│   │       │              Loki :3100 ◄── logs push (OTLP/HTTP)    │  │
│   │       │                   │                                  │  │
│   │       └──────────────┐    │    ┌── Tempo :3200               │  │
│   │                      ▼    ▼    ▼                             │  │
│   │              ┌──────────────────────┐                        │  │
│   │              │   Grafana :3000      │ (grafana_data vol.)    │  │
│   │              │   (dashboards)       │                        │  │
│   │              └──────────────────────┘                        │  │
│   └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘

Ports exposés à l'hôte : 8080 (API) · 3000 (Grafana) · 9090 (Prometheus)
Ports internes uniquement : 5432 (PostgreSQL) · 3100 (Loki) · 3200 (Tempo)
                            4317/4318 (OTLP Tempo)
```

---

## Description des composants

| Composant | Image | Port interne | Rôle |
|---|---|---|---|
| **app Flutter** (`mobile/`) | — | — | Application mobile iOS + Android (Clean Architecture + provider) |
| **api** | build local (Go 1.22) | 8080 | API REST : logique métier, streaming, authentification JWT |
| **postgres** | `postgres:16-alpine` | 5432 | Base de données relationnelle : utilisateurs, contenus, sessions |
| **prometheus** | `prom/prometheus:latest` | 9090 | Collecte et stockage des métriques (scrape pull) |
| **loki** | `grafana/loki:latest` | 3100 | Agrégation et indexation des logs applicatifs |
| **tempo** | `grafana/tempo:latest` | 3200 | Stockage et requête des traces distribuées (OTLP) |
| **grafana** | `grafana/grafana:latest` | 3000 | Visualisation unifiée : métriques, logs, traces |

---

## Flux de données — Requête client

```
1. L'app Flutter envoie une requête REST HTTPS vers api:8080
2. L'API Go valide le JWT (middleware auth)
3. L'API interroge PostgreSQL sur postgres:5432
4. PostgreSQL retourne les données
5. L'API formate la réponse JSON et la renvoie au client Flutter
```

Pour les flux de streaming vidéo (HLS), l'API génère des URLs signées
pointant vers le stockage objet (prévu en phase ultérieure).

---

## Flux d'observabilité

### Métriques
```
1. L'API Go expose un endpoint /metrics (format Prometheus/OpenMetrics)
2. Prometheus scrape /metrics toutes les 15 secondes (pull)
3. Les métriques sont stockées dans le TSDB Prometheus
4. Grafana interroge Prometheus via datasource configurée
5. Les dashboards affichent latence, débit, erreurs, saturation
```

### Logs
```
1. L'API Go pousse ses logs structurés (JSON) vers Loki via OTLP HTTP
2. Loki indexe les labels (service, level, trace_id) et stocke les chunks
3. Grafana interroge Loki via datasource configurée
4. Le champ trace_id dans les logs crée un lien cliquable vers Tempo
```

### Traces
```
1. L'API Go instrumente chaque requête avec OpenTelemetry SDK
2. Les spans sont exportés vers Tempo via OTLP gRPC (tempo:4317)
3. Tempo stocke les traces en local (filesystem)
4. Grafana interroge Tempo : vue waterfall des spans par trace_id
5. Depuis une trace, on peut naviguer vers les logs Loki associés
```

---

## Justification des choix techniques

### Pourquoi Go pour le backend ?

- **Performance** : goroutines légères, faible empreinte mémoire — adapté au streaming concurrent
- **Binaire statique** : l'image Docker finale fait < 30 MB (pas de runtime JVM/Node)
- **Bibliothèque standard riche** : HTTP/2, TLS, JSON natifs sans dépendances
- **Typage fort** : détection d'erreurs à la compilation, refactoring sûr
- **Écosystème** : excellente intégration OpenTelemetry, GORM, pgx pour PostgreSQL

### Pourquoi Flutter pour le client ?

- **Cross-platform** : une codebase → iOS et Android (cibles actuelles)
- **Dart** : langage typé, AOT-compilé, performances proches du natif
- **Hot reload** : itérations de développement rapides
- **Material 3 / Cupertino** : UI adaptée à chaque plateforme cible

---

## Architecture Flutter (`mobile/`)

L'application mobile suit la **Clean Architecture** adaptée mobile, découpée en trois couches par feature.

### Organisation des dossiers

```
mobile/lib/
├── main.dart              # Point d'entrée — ProviderScope + runApp
├── app/
│   ├── app.dart           # Widget racine MaterialApp.router
│   └── router/            # Configuration go_router
├── core/                  # Utilitaires transverses (pas de logique métier)
│   ├── constants/         # ApiConstants, AppConstants
│   ├── errors/            # Failures (domaine) et Exceptions (infra)
│   ├── network/           # DioClient avec intercepteurs JWT
│   ├── storage/           # SecureStorage (tokens JWT)
│   └── theme/             # AppTheme, AppColors, AppTypography
└── features/              # Modules fonctionnels indépendants
    ├── auth/
    ├── streams/
    └── library/
```

### Structure de chaque feature (Clean Architecture)

```
features/<nom>/
├── data/
│   └── repositories/      # Implémentations concrètes des interfaces domain
├── domain/
│   ├── entities/          # Entités pures (pas de dépendance infra)
│   ├── repositories/      # Interfaces abstraites (contrats — Principe D)
│   └── usecases/          # Cas d'utilisation (à créer par US)
└── presentation/
    ├── screens/           # Widgets Flutter (UI)
    └── providers/         # ChangeNotifier providers (state management)
```

### Packages clés

| Package | Rôle |
|---|---|
| `provider` | State management — `ChangeNotifier` + `context.watch` / `context.read` |
| `go_router` | Navigation déclarative type-safe |
| `just_audio` + `audio_service` | Lecture audio HLS natif + background playback |
| `dio` | Client HTTP avec intercepteurs JWT |
| `flutter_secure_storage` | Stockage chiffré des tokens (EncryptedSharedPreferences Android) |

*Voir [ADR 005](adr/005-architecture-flutter-clean.md) pour l'analyse complète des alternatives.*

### Pourquoi la stack LGTM (Loki + Grafana + Tempo + Prometheus) ?

- **Open-source** : aucun coût de licence, déploiement on-premise possible
- **Intégration native** : les quatre outils sont du même éditeur (Grafana Labs), interfaces fluides
- **OpenTelemetry compatible** : standard industrie pour logs, métriques, traces — pas de vendor lock-in
- **Légèreté** : Loki n'indexe que les labels (pas le contenu complet) → moins de RAM que ELK
- **Critère RNCP** : démontre la maîtrise d'une infrastructure d'observabilité de niveau production

*Voir [ADR 001](adr/001-choix-stack-observabilite.md) pour l'analyse complète des alternatives.*

### Pourquoi Docker Compose pour le développement ?

- **Reproductibilité** : un seul fichier décrit l'environnement complet
- **Isolation** : réseau interne `streampulse-net`, pas de conflits de ports
- **Simplicité** : `docker compose up -d` démarre les 6 services en une commande
- **Parité dev/CI** : même stack utilisée en local et dans les runners GitHub Actions

*Voir [ADR 002](adr/002-choix-conteneurisation-docker.md) pour l'analyse complète.*

---

## Réseau et ports

```
┌─────────────────────────────────────────────────────┐
│                    HÔTE                             │
│                                                     │
│  localhost:8080 ──► api:8080                        │
│  localhost:3000 ──► grafana:3000                    │
│  localhost:9090 ──► prometheus:9090                 │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │          streampulse-net (bridge)           │    │
│  │                                             │    │
│  │  api:8080      postgres:5432                │    │
│  │  prometheus:9090  loki:3100                 │    │
│  │  tempo:3200    grafana:3000                 │    │
│  │  tempo:4317 (OTLP gRPC — interne)           │    │
│  │  tempo:4318 (OTLP HTTP — interne)           │    │
│  └─────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

Les services `postgres`, `loki` et `tempo` ne sont **pas** exposés à l'hôte :
ils ne sont accessibles que par les autres conteneurs via le réseau interne.
