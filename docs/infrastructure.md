# Infrastructure Docker — StreamPulse

Ce document décrit l'infrastructure de développement local du projet StreamPulse,
basée sur Docker Compose. Il couvre les services, les variables d'environnement,
les procédures opérationnelles et le troubleshooting.

---

## Services

| Service | Image | Rôle | Port interne | Port hôte | Healthcheck |
|---|---|---|---|---|---|
| `postgres` | `postgres:16-alpine` | Base de données relationnelle | 5432 | — | `pg_isready` |
| `api` | build local (Go 1.22) | API REST Go (stub de démarrage) | 8080 | **8080** | `GET /health` |
| `prometheus` | `prom/prometheus:latest` | Collecte de métriques | 9090 | **9090** | `GET /-/healthy` |
| `loki` | `grafana/loki:latest` | Agrégation de logs | 3100 | — | — (image distroless) |
| `tempo` | `grafana/tempo:latest` | Traces distribuées (OTLP) | 3200, 4317, 4318 | — | — (image distroless) |
| `grafana` | `grafana/grafana:latest` | Visualisation observabilité | 3000 | **3000** | `GET /api/health` |

> **Note Loki / Tempo :** les images `grafana/loki:latest` et `grafana/tempo:latest` sont des images distroless (pas de shell, pas de `wget` ni `curl`). Il est impossible d'y exécuter un healthcheck HTTP depuis l'intérieur du conteneur. Ces services démarrent correctement — Grafana les attend via `service_started` plutôt que `service_healthy`.

**Réseau interne :** `streampulse-net` (bridge Docker)
**Volumes nommés :** `postgres_data` (données PostgreSQL), `grafana_data` (dashboards, préférences)

---

## Variables d'environnement

Toutes les variables sont définies dans `.env` (copié depuis `.env.example`).
Aucune valeur secrète ne doit être committée dans le dépôt.

| Variable | Description | Valeur par défaut | Obligatoire |
|---|---|---|---|
| `POSTGRES_USER` | Nom de l'utilisateur PostgreSQL | `streampulse` | Oui |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL | `changeme` | **Oui — à changer** |
| `POSTGRES_DB` | Nom de la base de données | `streampulse_db` | Oui |
| `GRAFANA_ADMIN_PASSWORD` | Mot de passe admin Grafana | `changeme` | **Oui — à changer** |
| `API_PORT` | Port exposé de l'API Go sur l'hôte | `8080` | Non |
| `GO_ENV` | Environnement Go (`development` / `production`) | `development` | Non |
| `JWT_SECRET` | Clé secrète pour la signature des tokens JWT | `change-this-to-a-long-random-secret` | **Oui — à changer** |

---

## Procédure de premier lancement

Suivre ces étapes dans l'ordre lors de la première installation sur une nouvelle machine.

**Prérequis :** Docker Desktop (ou Docker Engine + Docker Compose v2), Git

```bash
# 1. Cloner le dépôt
git clone https://github.com/thierrymaignan/streampulse.git
cd streampulse

# 2. Créer le fichier .env à partir du modèle
cp .env.example .env

# 3. Éditer .env et remplacer toutes les valeurs "changeme"
#    Minimum requis :
#      POSTGRES_PASSWORD=un-mot-de-passe-fort
#      GRAFANA_ADMIN_PASSWORD=un-autre-mot-de-passe
#      JWT_SECRET=une-chaine-aleatoire-de-32-caracteres-minimum
nano .env   # ou votre éditeur préféré

# 4. Démarrer tous les services
docker compose up -d

# 5. Vérifier l'état des services (attendre ~30 secondes)
docker compose ps

# 6. Accéder à Grafana
#    URL    : http://localhost:3000
#    Login  : admin
#    Mot de passe : valeur de GRAFANA_ADMIN_PASSWORD dans .env
```

**Résultat attendu de `docker compose ps` :**

```
NAME                    STATUS                   PORTS
streampulse-postgres-1  Up (healthy)             5432/tcp
streampulse-api-1       Up (healthy)             0.0.0.0:8080->8080/tcp
streampulse-prometheus-1 Up (healthy)            0.0.0.0:9090->9090/tcp
streampulse-loki-1      Up                       3100/tcp
streampulse-tempo-1     Up                       3200/tcp, 4317/tcp, 4318/tcp
streampulse-grafana-1   Up (healthy)             0.0.0.0:3000->3000/tcp
```

> Loki et Tempo affichent `Up` (sans `healthy`) — c'est normal, leurs images ne permettent pas de healthcheck interne.

---

## Commandes du quotidien

```bash
# Démarrer tous les services
docker compose up -d

# Arrêter tous les services (volumes conservés)
docker compose down

# Arrêter et supprimer les volumes nommés (reset complet)
docker compose down -v

# Voir les logs de tous les services (flux continu)
docker compose logs -f

# Voir les logs d'un service spécifique
docker compose logs -f api
docker compose logs -f grafana

# Vérifier l'état et la santé des services
docker compose ps

# Reconstruire l'image de l'API Go (après modification du code)
docker compose build api && docker compose up -d api

# Redémarrer un seul service
docker compose restart api

# Ouvrir un shell PostgreSQL
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Voir les targets Prometheus (API bien scrapée ?)
curl http://localhost:9090/api/v1/targets
```

---

## URLs d'accès local

| Service | URL | Identifiants |
|---|---|---|
| **Grafana** | http://localhost:3000 | `admin` / `$GRAFANA_ADMIN_PASSWORD` |
| **Prometheus** | http://localhost:9090 | — |
| **API Go** | http://localhost:8080 | — (JWT requis selon les routes) |
| API — Health | http://localhost:8080/health | — |
| API — Métriques | http://localhost:8080/metrics | — |

---

## Vérifier la santé des services

```bash
# Vue d'ensemble : tous les services et leur état
docker compose ps

# Santé individuelle (retourne 200 si OK)
curl -s -o /dev/null -w "%{http_code}" http://localhost:9090/-/healthy   # Prometheus
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/api/health  # Grafana
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health      # API Go

# Targets Prometheus (voir si l'API est bien scrapée)
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'
```

---

## Dépendances entre services

```
grafana ──depends_on──► prometheus (service_healthy)
grafana ──depends_on──► loki       (service_started)
grafana ──depends_on──► tempo      (service_started)
api     ──depends_on──► postgres   (service_healthy)
```

- Grafana attend que Prometheus soit **healthy** et que Loki/Tempo soient **démarrés**.
- L'API ne démarre qu'une fois PostgreSQL **healthy**.
- Loki et Tempo n'ont pas de `depends_on` — ils démarrent indépendamment.

---

## Troubleshooting

### 1. Port déjà utilisé (port conflict)

**Symptôme :** `Error starting userland proxy: listen tcp 0.0.0.0:8080: bind: address already in use`

**Cause :** Un autre processus utilise le port 8080, 3000 ou 9090.

```bash
# Identifier le processus
lsof -i :8080
# Arrêter le processus ou changer le port dans .env
echo "API_PORT=8081" >> .env
docker compose up -d
```

---

### 2. Variables d'environnement vides (warnings au démarrage)

**Symptôme :** `WARN The "POSTGRES_USER" variable is not set. Defaulting to a blank string.`

**Cause :** Le fichier `.env` n'existe pas. PostgreSQL refuse de démarrer sans `POSTGRES_USER`.

```bash
cp .env.example .env
# Éditer les valeurs "changeme"
docker compose down && docker compose up -d
```

---

### 3. Service bloqué en "starting" (healthcheck qui échoue)

**Symptôme :** `docker compose ps` affiche `Up (health: starting)` depuis plus de 2 minutes.

**Diagnostic :**
```bash
docker compose logs <service>   # lire les erreurs de démarrage
docker inspect --format='{{json .State.Health}}' streampulse-<service>-1 | jq
```

**Cause fréquente :** PostgreSQL — le mot de passe dans `.env` ne correspond pas au volume existant.
```bash
docker compose down -v && docker compose up -d
```

---

### 4. L'API ne peut pas se connecter à PostgreSQL

**Symptôme :** logs de l'API : `connection refused` ou `password authentication failed`

```bash
# Vérifier que PostgreSQL est bien healthy
docker compose ps postgres
# Vérifier les variables dans .env
grep POSTGRES .env
# Tester la connexion directement
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c "\l"
```

---

### 5. Grafana ne voit pas Prometheus comme datasource

**Symptôme :** Grafana affiche une erreur de connexion sur la datasource Prometheus.

```bash
# Vérifier que Prometheus est bien démarré
curl http://localhost:9090/-/healthy
# Vérifier que Prometheus scrape bien l'API
curl http://localhost:9090/api/v1/targets
# Redémarrer Grafana pour recharger le provisioning
docker compose restart grafana
```

---

### 6. Volume PostgreSQL corrompu

**Symptôme :** PostgreSQL démarre mais échoue au healthcheck avec des erreurs de fichiers système.

```bash
# Reset complet (ATTENTION : supprime toutes les données)
docker compose down -v
docker compose up -d
```
