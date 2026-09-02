# Documentation technique — StreamPulse

Ce dossier contient l'ensemble de la documentation technique du projet StreamPulse.
Les documents sont destinés à être lus par tout contributeur ou évaluateur externe
souhaitant comprendre l'architecture, l'infrastructure et les décisions prises.

---

## Ordre de lecture recommandé

1. [architecture.md](architecture.md) — Vue d'ensemble du système : composants, flux de données, choix techniques. **Commencer ici.**
2. [infrastructure.md](infrastructure.md) — Infrastructure Docker : services, variables d'environnement, commandes du quotidien, procédure de premier lancement, troubleshooting, pipeline CI/CD.
3. **Socle technique** — les décisions structurantes, dans l'ordre où elles ont été prises :
   [ADR 001](adr/001-choix-stack-observabilite.md) (observabilité) ·
   [ADR 002](adr/002-choix-conteneurisation-docker.md) (Docker) ·
   [ADR 003](adr/003-choix-cicd-github-actions.md) (CI/CD) ·
   [ADR 004](adr/004-config-12-factor-viper.md) (configuration) ·
   [ADR 037](adr/037-initialisation-base-de-donnees.md) (base de données) ·
   [ADR 007](adr/007-sqlc-generation-code-sql.md) (sqlc).
4. **Backend Go** — [ADR 008](adr/008-architecture-handler-service-repository.md) (layering handler/service/repository) puis
   [ADR 006](adr/006-authentification-jwt.md) (JWT) et [ADR 012](adr/012-openapi-source-de-verite.md) (OpenAPI, contrat HTTP).
5. **Application mobile** — [ADR 005](adr/005-architecture-flutter-clean.md) (Clean Architecture), **corrigée par**
   [ADR 036](adr/036-state-management-flutter-provider.md) (`provider` plutôt que Riverpod — à lire ensemble),
   puis [ADR 009](adr/009-authentification-flutter.md) (auth mobile).
6. **Métier** — streaming ([ADR 013](adr/013-domaine-streaming.md), [ADR 015](adr/015-moteur-hls-segmentation-ffmpeg.md)),
   bibliothèque ([ADR 026](adr/026-domaine-playlists.md), [ADR 032](adr/032-domaine-track-upload-audio.md)),
   lecture audio ([ADR 023](adr/023-lecteur-audio-hls-mobile.md), [ADR 034](adr/034-lecture-dune-playlist-avec-file-dattente.md)).
7. **Observabilité en production** — [ADR 018](adr/018-logs-structures-zerolog-collecte-loki-alloy.md) (logs) ·
   [ADR 019](adr/019-metriques-prometheus-cardinalite-et-dashboards.md) (métriques) ·
   [ADR 020](adr/020-traces-opentelemetry-otlp-tempo.md) (traces) ·
   [ADR 021](adr/021-alertes-grafana-provisionnees-email.md) (alertes) ·
   [ADR 022](adr/022-metriques-metier-streaming-et-panel-live.md) (métriques métier).

---

## Périmètre bilingue

Le critère `Ce3.6.2` demande une documentation technique rédigée **en français
et en anglais**. Le corpus fait environ 75 000 mots ; tout traduire aurait
produit deux corpus qui divergent, ce qui est pire qu'un périmètre plus étroit
mais tenu.

Le périmètre est donc **déclaré**, et c'est cette déclaration qui le rend
défendable — un silence se lirait comme un oubli.

**Le français fait référence.** En cas de divergence entre les deux versions,
la française est la bonne, et l'écart est un défaut à signaler.

### Maintenu dans les deux langues

| Français | English | Ce que le document répond |
|---|---|---|
| [README.md](../README.md) | [README.en.md](../README.en.md) | Ce qu'est le projet, comment le lancer, quelles variables il attend |
| [architecture.md](architecture.md) | [en/architecture.md](en/architecture.md) | Comment les pièces s'assemblent, et pourquoi ces technologies |
| [infrastructure.md](infrastructure.md) | [en/operations.md](en/operations.md) | Comment lancer, observer et déployer la stack |
| [securite.md](securite.md) | [en/security.md](en/security.md) | Qui accède à quoi, comment les secrets sont protégés, ce qui est exposé |
| Toutes les ADR | [en/adr-index.md](en/adr-index.md) | Chaque décision d'architecture, résumée |
| — | [en/README.md](en/README.md) | Index anglais |

### Français uniquement, et pourquoi

Le motif est le même partout : **le public de ces documents est francophone**,
et une seconde version divergerait — ou, pire, dirait autre chose.

| Document | Motif |
|---|---|
| Manuel utilisateur, plan de formation, déclaration d'accessibilité | Écrits pour les personnes qui utilisent le produit et celles qui les forment |
| Politique de confidentialité, CGU | Textes juridiques. Deux versions d'un texte juridique sont deux textes qui peuvent se contredire — un risque réel, pas théorique |
| Cahier de recette, user stories | Artefacts de recette, lus par l'équipe et le jury |
| Les ADR intégrales | Résumées dans l'index anglais ; le code, les tableaux et les diagrammes qu'elles contiennent sont déjà neutres en langue |
| Runbook d'exploitation détaillé | Procédures de dépannage et de mise à jour du VPS, pour l'équipe qui exploite le service |
| Rapport de couverture de tests | Lu par l'équipe qui écrit le code et par le jury ; les chiffres et les noms de paquets qu'il contient sont déjà neutres en langue |
| Guide de distribution mobile | Procédure d'exploitation : secrets à poser, build à déclencher, artefact à récupérer — pour l'équipe qui livre |

### Ce qui garde le périmètre honnête

L'index anglais des décisions promet d'être **exhaustif**. Une ADR ajoutée sans
son entrée le rendrait menteur sans que personne s'en aperçoive — un lecteur
anglophone n'a aucun moyen de savoir ce qui lui manque.

`make check-adr-index` refuse donc toute ADR sans entrée, et la CI le rejoue à
chaque PR. L'asymétrie est voulue : une entrée qui précède son fichier est
tolérée et signalée (deux branches qui avancent en parallèle), l'inverse jamais.

### Note sur la langue du reste

Les messages de commit, les titres de PR et les tickets Linear sont **en
français** — convention de projet, décidée une fois. Les identifiants de code,
les champs d'API et la spécification OpenAPI sont **en anglais**, comme d'usage.

Cette spécification est d'ailleurs le seul artefact qui a toujours été
anglophone : avant ce travail, l'écart bilingue courait donc dans les deux sens
— une doc technique 100 % française et une référence d'API 100 % anglaise, aucun
document dans les deux langues.

---

## Documents transverses

| Fichier | Description |
|---|---|
| [architecture.md](architecture.md) | Architecture globale, schéma ASCII, flux requête et observabilité, justification des choix |
| [infrastructure.md](infrastructure.md) | Services Docker, variables d'environnement, procédures opérationnelles, troubleshooting, pipeline CI/CD |
| [cdc-conflits-codebase.md](cdc-conflits-codebase.md) | Écarts connus entre le cahier des charges et la codebase |
| [user-stories.md](user-stories.md) | Les user stories du produit, par épopée, avec leurs critères d'acceptation |
| [database.md](database.md) | Structure de la base de données : tables, relations, contraintes |
| [diagrammes.md](diagrammes.md) | Diagrammes UML, chacun accompagné de son équivalent textuel |
| [cahier-de-recette.md](cahier-de-recette.md) | Cahier de recette : 124 scénarios, statut et preuve de chacun |
| [manuel-utilisateur.md](manuel-utilisateur.md) | Manuel utilisateur — parcours auditeur, diffuseur et administrateur, sans ligne de commande |
| [plan-formation.md](plan-formation.md) | Plan de formation — publics, modalités, durées, évaluation, et adaptations pour les publics en situation de handicap |
| [accessibilite.md](accessibilite.md) | Déclaration d'accessibilité de la documentation (WCAG 2.1 AA), glossaire, écarts connus |
| [en/README.md](en/README.md) | **English** — index de la documentation anglaise et périmètre couvert |
| [securite.md](securite.md) | Schéma général de la sécurité — matrice rôles × routes, flux JWT, inventaire des secrets, surface d'attaque, modèle de menace |
| [rgpd.md](rgpd.md) | Dossier RGPD — registre des traitements, politique de rétention par magasin, droits des personnes |
| [politique-confidentialite.md](politique-confidentialite.md) | Politique de confidentialité destinée aux utilisateurs (embarquée dans l'application) |
| [cgu.md](cgu.md) | Conditions générales d'utilisation (embarquées dans l'application) |
| [couverture-de-tests.md](couverture-de-tests.md) | Couverture Go : périmètre déclaré, porte de qualité à 80 %, tests d'intégration et ce qui reste hors d'atteinte |
| [performance-mobile.md](performance-mobile.md) | Preuves de fluidité 60 FPS : garde de reconstruction en CI et relevé de trames sur appareil |
| [distribution-mobile.md](distribution-mobile.md) | Build, signature et livraison de l'application Android ; pourquoi iOS n'est pas distribué |
| [../CHANGELOG.md](../CHANGELOG.md) | Historique des versions généré automatiquement par release-please |

---

## Index complet des ADR

Les ADR documentent toutes les décisions d'architecture significatives du projet.
Chaque décision est tracée avec son contexte, les **alternatives écartées** et les conséquences.

| # | Fichier | Décision |
|---|---|---|
| 001 | [001-choix-stack-observabilite.md](adr/001-choix-stack-observabilite.md) | Choix de la stack d'observabilité : LGTM |
| 002 | [002-choix-conteneurisation-docker.md](adr/002-choix-conteneurisation-docker.md) | Conteneurisation avec Docker Compose pour l'environnement de développement |
| 003 | [003-choix-cicd-github-actions.md](adr/003-choix-cicd-github-actions.md) | Choix de GitHub Actions pour la CI/CD |
| 004 | [004-config-12-factor-viper.md](adr/004-config-12-factor-viper.md) | Configuration 12-Factor App via Viper |
| 005 | [005-architecture-flutter-clean.md](adr/005-architecture-flutter-clean.md) | Architecture Flutter : Clean Architecture (**Superseded** par l'ADR 036 sur le state management) |
| 006 | [006-authentification-jwt.md](adr/006-authentification-jwt.md) | Authentification JWT : access token + refresh token |
| 007 | [007-sqlc-generation-code-sql.md](adr/007-sqlc-generation-code-sql.md) | Accès base de données : sqlc (SQL → Go typé) |
| 008 | [008-architecture-handler-service-repository.md](adr/008-architecture-handler-service-repository.md) | Architecture en couches : handler / service / repository |
| 009 | [009-authentification-flutter.md](adr/009-authentification-flutter.md) | Authentification côté Flutter : stockage sécurisé, refresh automatique, logout best-effort |
| 010 | [010-reinitialisation-mot-de-passe-backend.md](adr/010-reinitialisation-mot-de-passe-backend.md) | Réinitialisation de mot de passe : sécurisation côté backend |
| 011 | [011-reinitialisation-mot-de-passe-flutter.md](adr/011-reinitialisation-mot-de-passe-flutter.md) | Réinitialisation de mot de passe : deep links et gestion d'état Flutter |
| 012 | [012-openapi-source-de-verite.md](adr/012-openapi-source-de-verite.md) | OpenAPI comme source de vérité du contrat HTTP + client Flutter généré |
| 013 | [013-domaine-streaming.md](adr/013-domaine-streaming.md) | Domaine streaming : `stream_key`, CRUD des flux et soft delete |
| 014 | [014-demande-activation-role-diffuseur.md](adr/014-demande-activation-role-diffuseur.md) | Demande et activation du rôle diffuseur |
| 015 | [015-moteur-hls-segmentation-ffmpeg.md](adr/015-moteur-hls-segmentation-ffmpeg.md) | Moteur HLS : segmentation et manifeste via ffmpeg |
| 016 | [016-scalabilite-test-de-charge-et-limiteur-hls.md](adr/016-scalabilite-test-de-charge-et-limiteur-hls.md) | Scalabilité : test de charge Go in-process et limiteur de capacité HLS |
| 017 | [017-tableau-de-bord-admin-gestion-utilisateurs.md](adr/017-tableau-de-bord-admin-gestion-utilisateurs.md) | Tableau de bord admin : liste, recherche et gestion des utilisateurs |
| 018 | [018-logs-structures-zerolog-collecte-loki-alloy.md](adr/018-logs-structures-zerolog-collecte-loki-alloy.md) | Logs structurés JSON (zerolog) et collecte Loki via Alloy |
| 019 | [019-metriques-prometheus-cardinalite-et-dashboards.md](adr/019-metriques-prometheus-cardinalite-et-dashboards.md) | Métriques Prometheus : middleware dédié, cardinalité bornée, dashboards provisionnés |
| 020 | [020-traces-opentelemetry-otlp-tempo.md](adr/020-traces-opentelemetry-otlp-tempo.md) | Traces OpenTelemetry : OTLP/HTTP vers Tempo, otelhttp et otelpgx |
| 021 | [021-alertes-grafana-provisionnees-email.md](adr/021-alertes-grafana-provisionnees-email.md) | Alertes Grafana provisionnées, notification par email |
| 022 | [022-metriques-metier-streaming-et-panel-live.md](adr/022-metriques-metier-streaming-et-panel-live.md) | Métriques métier du streaming et panel Live |
| 023 | [023-lecteur-audio-hls-mobile.md](adr/023-lecteur-audio-hls-mobile.md) | Lecteur audio HLS mobile (just_audio) |
| 024 | [024-tableau-de-bord-diffuseur-lancer-et-arreter-un-flux.md](adr/024-tableau-de-bord-diffuseur-lancer-et-arreter-un-flux.md) | Tableau de bord diffuseur : lancer et arrêter un flux |
| 025 | [025-statistiques-daudience-en-temps-reel.md](adr/025-statistiques-daudience-en-temps-reel.md) | Statistiques d'audience en temps réel |
| 026 | [026-domaine-playlists.md](adr/026-domaine-playlists.md) | Domaine playlists : CRUD, isolation propriétaire et unicité du nom |
| 027 | [027-capture-microphone-et-push-aac-mobile.md](adr/027-capture-microphone-et-push-aac-mobile.md) | Capture microphone et push AAC depuis l'application mobile |
| 028 | [028-rotation-de-la-cle-de-diffusion.md](adr/028-rotation-de-la-cle-de-diffusion.md) | Rotation de la clé de diffusion |
| 029 | [029-pistes-dune-playlist-ajout-retrait-reordonnancement.md](adr/029-pistes-dune-playlist-ajout-retrait-reordonnancement.md) | Pistes d'une playlist : ajout, retrait et réordonnancement |
| 030 | [030-transcodage-a-la-volee-des-formats-dingest.md](adr/030-transcodage-a-la-volee-des-formats-dingest.md) | Transcodage à la volée des formats d'ingest |
| 031 | [031-lecture-audio-en-arriere-plan.md](adr/031-lecture-audio-en-arriere-plan.md) | Lecture audio en arrière-plan (audio_service) |
| 032 | [032-domaine-track-upload-audio.md](adr/032-domaine-track-upload-audio.md) | Domaine track : upload d'une piste audio |
| 033 | [033-gestion-des-interruptions-audio.md](adr/033-gestion-des-interruptions-audio.md) | Gestion des interruptions audio (appels, notifications, casque) |
| 034 | [034-lecture-dune-playlist-avec-file-dattente.md](adr/034-lecture-dune-playlist-avec-file-dattente.md) | Lecture d'une playlist avec file d'attente (queue) |
| 035 | [035-modes-shuffle-et-repeat.md](adr/035-modes-shuffle-et-repeat.md) | Modes shuffle et repeat de la file d'attente |
| 037 | [037-initialisation-base-de-donnees.md](adr/037-initialisation-base-de-donnees.md) | Initialisation de la base de données : schéma, migrations et seed *(ex-ADR 003)* |
| 038 | [038-gestion-profil-utilisateur.md](adr/038-gestion-profil-utilisateur.md) | Gestion du profil utilisateur (table `profiles` dédiée) *(ex-ADR 012)* |
| 039 | [039-supervision-admin-des-flux-et-journal-daudit.md](adr/039-supervision-admin-des-flux-et-journal-daudit.md) | Supervision admin des flux actifs et journal d'audit *(ex-ADR 018)* |
| 040 | [040-distribution-mobile-signature-et-canal.md](adr/040-distribution-mobile-signature-et-canal.md) | Distribution mobile : signature Android dégradable, pas de canal iOS |
| 041 | [041-metriques-metier-debit-departs-et-resume-admin.md](adr/041-metriques-metier-debit-departs-et-resume-admin.md) | Métriques métier : débit, départs d'auditeurs, interruptions et résumé admin |
| 042 | [042-controle-du-volume-et-temps-decoute.md](adr/042-controle-du-volume-et-temps-decoute.md) | Contrôle du volume dans l'application et temps d'écoute d'un direct |
| 043 | [043-accessibilite-de-l-application-et-adaptation-aux-largeurs.md](adr/043-accessibilite-de-l-application-et-adaptation-aux-largeurs.md) | Accessibilité de l'application mobile et adaptation aux largeurs d'écran |
| 044 | [044-cout-cpu-du-streaming-et-dimensionnement-du-vps.md](adr/044-cout-cpu-du-streaming-et-dimensionnement-du-vps.md) | Coût CPU du streaming, modèle de capacité et dimensionnement du VPS |
| 045 | [045-codes-derreur-du-manifeste-hls.md](adr/045-codes-derreur-du-manifeste-hls.md) | Codes d'erreur du manifeste HLS : distinguer « terminé » de « pas encore prêt » |
| 046 | [046-recommandation-basee-sur-l-historique-d-ecoute.md](adr/046-recommandation-basee-sur-l-historique-d-ecoute.md) | Recommandation de pistes basée sur l'historique d'écoute (capture + algorithme SQL) |
| 047 | [047-connexion-google-oauth.md](adr/047-connexion-google-oauth.md) | Connexion via Google (ID token vérifié côté serveur, création auto du compte, `password_hash` nullable) |
| 048 | [048-relance-d-un-flux-termine.md](adr/048-relance-d-un-flux-termine.md) | Un flux est un canal réutilisable : `start` accepte `idle\|ended` et remet `ended_at` à NULL, sans migration |
| 049 | [049-cycle-de-vie-de-la-diffusion-mobile.md](adr/049-cycle-de-vie-de-la-diffusion-mobile.md) | Quitter l'application n'est pas la fermer : `hidden`/`paused` inertes, service de premier plan micro, `detached` termine |

---

## Convention ADR

- Toute nouvelle décision d'architecture significative → nouvel ADR dans `docs/adr/`,
  avec **le numéro suivant** (prochain : `050-...`). Le numéro est un **identifiant**,
  attribué dans l'ordre d'enregistrement — il ne suit pas nécessairement l'ordre chronologique
  des décisions (cf. 037/038/039, renumérotées après collision).
- Un numéro n'est **jamais réutilisé** : une ADR remplacée passe en statut
  `Superseded by NNN` et reste dans le dépôt — l'historique décisionnel a de la valeur.
- Chaque ADR porte un bloc **Date / Statut / Ticket** et une section
  **« Alternatives écartées »** : sans alternative rejetée, un document décrit une
  implémentation, pas une décision.
- Format : [Lightweight ADR](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions) (Michael Nygard).

---

## Liens utiles

- Projet Linear (tickets) : https://linear.app/streampulse
- Dépôt GitHub : https://github.com/LignacAntony/streampulse
- Guide de contribution : [CONTRIBUTING.md](../CONTRIBUTING.md)
