# ADR 003 — Choix de GitHub Actions pour la CI/CD

- **Date :** 2026-04-27
- **Statut :** Accepté
- **Ticket Linear :** STR-17

---

## Contexte

Le projet StreamPulse nécessite une automatisation complète du cycle de vie du code :
linting, tests, build, scan de sécurité et déploiement sur le VPS de production.
Cette automatisation doit s'intégrer naturellement avec le dépôt GitHub déjà en place
et être activée dès le premier merge sur `main`.

---

## Décision

Utiliser **GitHub Actions** comme plateforme de CI/CD, avec **GitHub Container Registry (GHCR)**
comme registry d'images Docker.

Trois workflows sont définis :

| Workflow | Fichier | Rôle |
|---|---|---|
| CI | `ci.yml` | Lint + tests + build à chaque push/PR |
| CD | `cd.yml` | Build image Docker + push GHCR + déploiement SSH sur le VPS |
| Security | `security.yml` | Scan Trivy (filesystem) + analyse statique gosec |

---

## Alternatives considérées

### GitLab CI
- **Avantage :** pipelines natifs très puissants, registry intégré.
- **Rejet :** le dépôt est hébergé sur GitHub ; migrer vers GitLab crée de la friction
  inutile (deux plateformes, webhooks, gestion d'accès distincte).

### Jenkins
- **Avantage :** très flexible, auto-hébergé.
- **Rejet :** nécessite de maintenir un serveur Jenkins dédié, ce qui ajoute de la
  complexité opérationnelle incompatible avec la phase actuelle du projet.
  Le coût d'infrastructure n'est pas justifié pour une équipe de cette taille.

### CircleCI
- **Avantage :** interface claire, bonne intégration Docker.
- **Rejet :** service tiers payant au-delà du tier gratuit limité (2 000 credits/mois),
  et moins intégré nativement avec GitHub que GitHub Actions.

---

## Conséquences

### Avantages

- **Zéro infrastructure CI à maintenir** : runners `ubuntu-latest` gérés par GitHub.
- **Intégration native GitHub** : accès direct à `GITHUB_TOKEN`, GHCR, Code Scanning
  (upload SARIF), statuts de PR, et `workflow_dispatch` depuis l'UI.
- **Cache Docker (`type=gha`)** : réduit significativement le temps de build des images
  Go multi-stage entre les runs successifs.
- **Centralisation** : code, issues, PRs, CI/CD et registry d'images au même endroit.
- **Coût** : gratuit pour les dépôts publics ; les dépôts privés bénéficient de
  2 000 minutes/mois sur le tier gratuit.

### Inconvénients

- **Dépendance à GitHub** : une panne ou un changement de politique tarifaire GitHub
  impacte directement la CI/CD. Risque faible mais à monitorer.
- **Secrets GitHub requis** : 6 secrets à configurer manuellement dans les Settings
  du dépôt (voir `docs/infrastructure.md` section "Pipeline CI/CD").
- **Runners éphémères** : pas de cache disque persistant entre les jobs sans
  `actions/cache` ou `cache-from: type=gha` explicite.
