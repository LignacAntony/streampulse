# Documentation technique — StreamPulse

Ce dossier contient l'ensemble de la documentation technique du projet StreamPulse.
Les documents sont destinés à être lus par tout contributeur ou évaluateur externe
souhaitant comprendre l'architecture, l'infrastructure et les décisions prises.

---

## Ordre de lecture recommandé

1. [architecture.md](architecture.md) — Vue d'ensemble du système : composants, flux de données, choix techniques. **Commencer ici.**
2. [infrastructure.md](infrastructure.md) — Infrastructure Docker : services, variables d'environnement, commandes du quotidien, procédure de premier lancement, troubleshooting, pipeline CI/CD.
3. [adr/001-choix-stack-observabilite.md](adr/001-choix-stack-observabilite.md) — Décision d'architecture : stack d'observabilité LGTM (Loki, Grafana, Tempo, Prometheus).
4. [adr/002-choix-conteneurisation-docker.md](adr/002-choix-conteneurisation-docker.md) — Décision d'architecture : conteneurisation avec Docker Compose.
5. [adr/003-choix-cicd-github-actions.md](adr/003-choix-cicd-github-actions.md) — Décision d'architecture : pipeline CI/CD avec GitHub Actions et GHCR.
6. [adr/003-initialisation-base-de-donnees.md](adr/003-initialisation-base-de-donnees.md) — Décision d'architecture : initialisation de la base de données (schéma, migrations, seed).
7. [adr/004-config-12-factor-viper.md](adr/004-config-12-factor-viper.md) — Décision d'architecture : configuration 12-Factor App avec Viper.
8. [adr/005-architecture-flutter-clean.md](adr/005-architecture-flutter-clean.md) — Décision d'architecture : Clean Architecture + provider pour l'application mobile Flutter.
9. [adr/006-authentification-jwt.md](adr/006-authentification-jwt.md) — Décision d'architecture : authentification JWT (access token + refresh token avec rotation).
10. [adr/007-sqlc-generation-code-sql.md](adr/007-sqlc-generation-code-sql.md) — Décision d'architecture : accès base de données via sqlc (SQL → Go typé).
11. [adr/008-architecture-handler-service-repository.md](adr/008-architecture-handler-service-repository.md) — Décision d'architecture : layering handler / service / repository côté backend Go.
12. [adr/010-reinitialisation-mot-de-passe-backend.md](adr/010-reinitialisation-mot-de-passe-backend.md) — Décision d'architecture : sécurisation du workflow de réinitialisation de mot de passe (backend Go).
13. [adr/011-reinitialisation-mot-de-passe-flutter.md](adr/011-reinitialisation-mot-de-passe-flutter.md) — Décision d'architecture : deep links et gestion d'état Flutter pour la réinitialisation de mot de passe.
14. [adr/012-gestion-profil-utilisateur.md](adr/012-gestion-profil-utilisateur.md) — Décision d'architecture : table `profiles` dédiée (1-1 avec `users`), création automatique par trigger, préférences modifiables.

---

## Index complet

| Fichier | Description |
|---|---|
| [architecture.md](architecture.md) | Architecture globale, schéma ASCII, flux requête et observabilité, justification des choix |
| [infrastructure.md](infrastructure.md) | Services Docker, variables d'environnement, procédures opérationnelles, troubleshooting, pipeline CI/CD |
| [adr/001-choix-stack-observabilite.md](adr/001-choix-stack-observabilite.md) | ADR 001 — Choix de la stack LGTM pour l'observabilité |
| [adr/002-choix-conteneurisation-docker.md](adr/002-choix-conteneurisation-docker.md) | ADR 002 — Conteneurisation avec Docker Compose |
| [adr/003-choix-cicd-github-actions.md](adr/003-choix-cicd-github-actions.md) | ADR 003 — Pipeline CI/CD avec GitHub Actions et GHCR |
| [adr/003-initialisation-base-de-donnees.md](adr/003-initialisation-base-de-donnees.md) | ADR 003 — Initialisation de la base de données : schéma, migrations, seed |
| [adr/004-config-12-factor-viper.md](adr/004-config-12-factor-viper.md) | ADR 004 — Configuration 12-Factor App avec Viper |
| [adr/005-architecture-flutter-clean.md](adr/005-architecture-flutter-clean.md) | ADR 005 — Architecture Flutter : Clean Architecture + provider |
| [adr/006-authentification-jwt.md](adr/006-authentification-jwt.md) | ADR 006 — Authentification JWT : access token + refresh token avec rotation |
| [adr/007-sqlc-generation-code-sql.md](adr/007-sqlc-generation-code-sql.md) | ADR 007 — Accès base de données : sqlc (SQL → Go typé) |
| [adr/008-architecture-handler-service-repository.md](adr/008-architecture-handler-service-repository.md) | ADR 008 — Layering backend Go : handler / service / repository |
| [adr/009-authentification-flutter.md](adr/009-authentification-flutter.md) | ADR 009 — Authentification Flutter : stockage sécurisé, refresh automatique, logout best-effort |
| [adr/010-reinitialisation-mot-de-passe-backend.md](adr/010-reinitialisation-mot-de-passe-backend.md) | ADR 010 — Réinitialisation mot de passe : token haché, anti-énumération, transaction atomique, mailer |
| [adr/011-reinitialisation-mot-de-passe-flutter.md](adr/011-reinitialisation-mot-de-passe-flutter.md) | ADR 011 — Réinitialisation mot de passe Flutter : deep links custom scheme, AsyncNotifier<bool> |
| [adr/012-gestion-profil-utilisateur.md](adr/012-gestion-profil-utilisateur.md) | ADR 012 — Gestion du profil : table `profiles` dédiée, trigger de création auto, préférences |
| [../CHANGELOG.md](../CHANGELOG.md) | Historique des versions généré automatiquement par release-please |

---

## Architecture Decision Records (ADR)

Les ADR documentent toutes les décisions d'architecture significatives du projet.
Chaque décision est tracée avec son contexte, les alternatives considérées et les conséquences.

**Convention :** toute nouvelle décision d'architecture → nouvel ADR dans `docs/adr/`
avec le numéro suivant (prochain : `012-...`).

Format utilisé : [Lightweight ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) (Michael Nygard).

---

## Liens utiles

- Projet Linear (tickets) : https://linear.app/streampulse
- Dépôt GitHub : https://github.com/LignacAntony/streampulse
- Guide de contribution : [CONTRIBUTING.md](../CONTRIBUTING.md)
