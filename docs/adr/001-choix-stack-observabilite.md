# ADR 001 — Choix de la stack d'observabilité : LGTM

## Statut

Accepté — 2026-04-27

## Contexte

StreamPulse est une application de streaming en temps réel. Les plateformes de streaming
présentent des patterns de charge imprévisibles (pics de connexions, latences réseau variables,
erreurs transitoires de lecture vidéo) qui rendent l'observabilité critique pour :

- détecter les régressions de performance avant qu'elles impactent les utilisateurs
- corréler les erreurs entre l'API, la base de données et les services tiers
- satisfaire le critère RNCP Bloc 3 de maîtrise de l'infrastructure et de la supervision

L'observabilité moderne repose sur trois piliers :

| Pilier | Question | Outil |
|---|---|---|
| **Métriques** | Combien ? Comment évolue la charge ? | Prometheus |
| **Logs** | Que s'est-il passé ? Quel message d'erreur ? | Loki |
| **Traces** | Où le temps est-il passé dans la chaîne d'appels ? | Tempo |

L'enjeu est de choisir des outils qui couvrent ces trois piliers, s'intègrent entre eux
et restent opérables par une petite équipe sans budget d'outils SaaS.

## Décision

Adopter la stack **LGTM** (Loki · Grafana · Tempo · Prometheus) :

- **Prometheus** : collecte les métriques de l'API Go via scrape pull sur `/metrics`
- **Loki** : agrège les logs structurés (JSON) de l'API via push OTLP/HTTP
- **Tempo** : stocke les traces distribuées reçues via OTLP gRPC (standard OpenTelemetry)
- **Grafana** : tableau de bord unifié pour les trois sources de données, avec corrélation native (log → trace, trace → log)

L'instrumentation côté API sera réalisée avec le SDK officiel **OpenTelemetry Go**,
qui est agnostique du backend et permet de changer de stack sans toucher au code applicatif.

## Alternatives considérées

### ELK Stack (Elasticsearch + Logstash + Kibana)

- **Pourquoi rejeté** : Elasticsearch est lourd en RAM (minimum 4 GB en JVM), complexe à opérer,
  et nécessite Logstash comme pipeline intermédiaire. Kibana ne gère pas nativement
  les métriques Prometheus ni les traces distribuées, ce qui oblige à ajouter APM d'Elastic.
  Le coût opérationnel est disproportionné pour une petite équipe.
  De plus, Elastic a introduit des restrictions de licence (SSPL) en 2021.

### Datadog

- **Pourquoi rejeté** : solution SaaS propriétaire, coût prohibitif à l'échelle (facturation à l'hôte + par Go de logs).
  Crée une dépendance forte à un fournisseur. Incompatible avec une approche cloud-agnostique
  et avec les contraintes de budget d'un projet en phase de démarrage.
  Pas adapté pour un déploiement on-premise.

### New Relic

- **Pourquoi rejeté** : mêmes problèmes de vendor lock-in que Datadog. Le modèle freemium
  est limité (100 GB/mois) et les fonctionnalités avancées (alerting, SLO) sont payantes.
  La courbe d'apprentissage est élevée pour une stack propriétaire.

### Victoria Metrics + Grafana (sans Loki/Tempo)

- **Pourquoi rejeté** : Victoria Metrics est excellente pour les métriques mais ne couvre pas
  les logs ni les traces. Compléter avec Jaeger (traces) et un agrégateur de logs séparé
  augmente la complexité d'opération sans bénéfice sur la cohérence des outils.

## Conséquences

### Avantages

- **Open-source** : aucune licence commerciale, déploiement on-premise ou cloud au choix
- **Intégration native** : Grafana connaît les formats Loki, Tempo et Prometheus — corrélation logs/traces cliquable
- **Standard industrie** : OpenTelemetry est le standard CNCF, adopté par tous les clouds majeurs
- **Légèreté** : Loki indexe uniquement les labels (pas le contenu complet des logs) → 10x moins de RAM qu'Elasticsearch
- **Extensibilité** : Prometheus supporte des centaines d'exporters (PostgreSQL, Redis, Nginx…)
- **Dashboards préfabriqués** : Grafana Labs propose des dashboards communautaires pour Go, PostgreSQL, Node.js

### Inconvénients

- **Loki** : moins mature qu'Elasticsearch pour les recherches full-text complexes
- **Tempo** : stockage filesystem en dev non adapté à la production (à migrer vers S3/GCS)
- **Courbe d'apprentissage** : Loki et Tempo sont des outils plus récents, moins documentés que ELK
- **Scalabilité** : la stack monolithique Docker Compose convient au dev mais devra être migrée
  vers un déploiement distribué (Kubernetes + Helm charts Grafana) en production

## Références

- [Grafana LGTM Stack](https://grafana.com/go/webinar/getting-started-with-grafana-lgtm-stack/)
- [OpenTelemetry Go SDK](https://opentelemetry.io/docs/languages/go/)
- [Loki architecture](https://grafana.com/docs/loki/latest/get-started/architecture/)
- [Tempo architecture](https://grafana.com/docs/tempo/latest/operations/architecture/)
- [Prometheus data model](https://prometheus.io/docs/concepts/data_model/)
- ADR 002 : [Conteneurisation avec Docker Compose](002-choix-conteneurisation-docker.md)
