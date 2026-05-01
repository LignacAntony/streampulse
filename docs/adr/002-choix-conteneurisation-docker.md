# ADR 002 — Conteneurisation avec Docker Compose pour l'environnement de développement

## Statut

Accepté — 2026-04-27

## Contexte

Le projet StreamPulse implique six services (API Go, PostgreSQL, Prometheus, Loki, Tempo, Grafana)
qui doivent fonctionner ensemble de manière cohérente sur les machines de tous les développeurs,
dans les runners CI GitHub Actions, et à terme en production.

Sans conteneurisation, chaque développeur installe et configure chaque dépendance manuellement.
Les problèmes classiques qui en découlent :

- "Fonctionne sur ma machine" (version PostgreSQL différente entre dev et prod)
- Conflits de ports entre projets
- Configuration de Prometheus différente selon les OS
- Impossibilité de reproduire un bug lié à l'état de la base de données

Le besoin est donc : **un environnement de développement local identique pour tous les contributeurs,
démarrable en une commande, sans friction.**

## Décision

Utiliser **Docker Compose v2** pour orchestrer tous les services en développement local.
Utiliser un **Dockerfile multi-stage Go** pour l'image de production de l'API.

### Docker Compose v2

- Un fichier `docker-compose.yml` à la racine décrit l'ensemble de la stack
- Réseau interne `streampulse-net` : les services communiquent par nom DNS (ex: `postgres:5432`)
- Volumes nommés (`postgres_data`, `grafana_data`) pour la persistance
- Variables d'environnement via `.env` (jamais de secrets hardcodés)
- Healthchecks sur chaque service avec `depends_on condition: service_healthy`

### Dockerfile multi-stage Go

- **Stage 1 (`golang:1.22-alpine`)** : compilation du binaire avec CGO désactivé
- **Stage 2 (`alpine:3`)** : image finale < 30 MB avec uniquement le binaire
- Utilisateur non-root (`appuser`) pour la sécurité en production

### Stratégie de versionnage des images

- **Tags majeurs** (ex: `postgres:16`, `grafana/grafana:11`) : à jour dans la version majeure,
  sans pinning à un patch spécifique
- Le changement de version majeure est une décision explicite (mise à jour du compose file via PR)
- Avantage : reçoit automatiquement les correctifs de sécurité dans la version majeure

## Alternatives considérées

### Développement sans conteneur (installation locale directe)

- **Pourquoi rejeté** : chaque développeur doit installer PostgreSQL 16, Prometheus, Loki, Tempo
  et Grafana manuellement. Les versions divergent. La configuration est répétée pour chaque machine.
  Le CI doit également installer toutes les dépendances, rendant les pipelines plus lents et fragiles.

### Podman + Podman Compose

- **Pourquoi rejeté** : Podman est une alternative valide (daemonless, rootless) mais l'écosystème
  Docker reste dominant. La documentation, les images officielles et les guides Grafana Labs
  utilisent tous Docker comme référence. Podman Compose est moins mature que Docker Compose v2.
  Le bénéfice (rootless par défaut) ne compense pas la friction supplémentaire pour une équipe
  déjà familiarisée avec Docker.

### Nix / NixOS

- **Pourquoi rejeté** : Nix offre une reproductibilité maximale (environnements déclaratifs purs)
  mais présente une courbe d'apprentissage très élevée. Incompatible avec les runners GitHub Actions
  standard sans configuration spécifique. Difficile à onboarder pour des nouveaux contributeurs.

### Kubernetes local (minikube / kind)

- **Pourquoi rejeté** : surcharge opérationnelle disproportionnée pour la phase de développement.
  Kubernetes est prévu pour la production (haute disponibilité, scalabilité horizontale) mais
  ajoute une complexité inutile en dev (namespaces, RBAC, ingress controllers, helm charts).
  La migration vers Kubernetes est prévue pour la phase de déploiement production.

## Conséquences

### Avantages

- **`docker compose up -d`** : démarre les 6 services en une commande
- **Reproductibilité** : même résultat sur macOS, Linux et Windows (WSL2)
- **Isolation** : réseau interne, pas d'impact sur d'autres projets locaux
- **CI-ready** : GitHub Actions utilise Docker nativement, le compose file est réutilisable
- **Image Go optimisée** : < 30 MB, démarrage < 1 seconde, surface d'attaque minimale
- **Secrets externalisés** : `.env` local, jamais commité (`.gitignore`)

### Inconvénients

- **Single-machine** : Docker Compose ne distribue pas les services sur plusieurs nœuds.
  Pour la production, une migration vers Kubernetes (ou Docker Swarm) sera nécessaire.
- **Ressources** : 6 services Docker simultanés consomment environ 2-4 GB de RAM en dev.
  Machines avec < 8 GB de RAM peuvent rencontrer des lenteurs.
- **Tempo storage éphémère** : le stockage des traces est sur le filesystem du conteneur.
  En production, il faudra configurer un backend objet (S3, GCS, Azure Blob).

## Références

- [Docker Compose v2 — Overview](https://docs.docker.com/compose/)
- [Docker multi-stage builds](https://docs.docker.com/build/building/multi-stage/)
- [Go Docker official images](https://hub.docker.com/_/golang)
- [Grafana Docker Compose example](https://grafana.com/docs/loki/latest/setup/install/docker/)
- ADR 001 : [Choix de la stack d'observabilité](001-choix-stack-observabilite.md)
