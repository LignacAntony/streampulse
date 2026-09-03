# User stories — StreamPulse

> 🇬🇧 **English version: [en/user-stories.md](en/user-stories.md)**

> Version : 1.2.0 — dernière révision : 2026-08-19

Export des user stories du projet, jusqu'ici visibles uniquement dans Linear. Un système
externe n'est ni versionné, ni archivable, ni consultable par un jury : ce document les rend
lisibles depuis le dépôt.

Chaque story reprend **son énoncé et ses critères d'acceptation d'origine**, tels qu'ils ont
été rédigés avant l'implémentation — pas une reconstruction après coup. La colonne de
traçabilité relie chacune à la PR qui l'a livrée.

Les scénarios de vérification correspondants vivent dans `docs/cahier-de-recette.md`, livré par
une PR distincte encore ouverte au moment de la rédaction.

---

## Convention

| Élément | Signification |
|---|---|
| **Identifiant** | `US-<épopée>-<rang>`. Le ticket Linear (`STR-NNN`) est l'identifiant technique |
| **Estimation** | En points, telle que posée au cadrage. Non réévaluée depuis |
| **Statut** | État réel dans Linear au 2026-08-19 |

⚠️ **Six épopées fondatrices n'ont pas de numéro d'US.** Elles ont été créées avant l'adoption
de la convention `US-XX-YY`, et portent un titre libre. Les dépendances des stories ultérieures
les désignent pourtant par un numéro (`US-01-02`, `US-02-02`, `US-03-02`…). La correspondance
est donnée plus bas comme **proposition à confirmer par l'équipe** : elle est déduite du sens
des dépendances, pas d'une décision écrite.

Le tableau des dépendances ci-dessous reproduit ce que Linear contient, y compris ces renvois
à des numéros non attribués.

---

## 1. Infrastructure & Setup

### STR-5 — Configuration du repository Git · ✅ Done

En tant que développeur, je veux un repository Git bien structuré avec branches develop/main
afin d'organiser le travail collaboratif et de protéger la branche de production.

### STR-11 — Mise en place de Docker Compose · ✅ Done

En tant que développeur, je veux un environnement Docker Compose fonctionnel afin de démarrer
l'ensemble des services (API, BDD, observabilité) d'une seule commande.

- **Given** : Docker et Docker Compose installés
- **When** : j'exécute `docker-compose up`
- **Then** : les services go-api, postgres, prometheus, grafana, loki et tempo démarrent sans
  erreur et sont interconnectés sur un réseau interne.

### STR-17 — Pipeline CI/CD GitHub Actions · ✅ Done

En tant que tech lead, je veux un pipeline CI/CD automatisé afin que chaque push sur main
déclenche automatiquement build, tests et déploiement sans intervention manuelle.

- **Given** : un commit pushé sur main
- **When** : le pipeline se déclenche
- **Then** : le build Go réussit, les tests unitaires passent, l'image Docker est construite et
  le déploiement sur le VPS s'effectue — le tout en moins de 5 minutes.

### STR-23 — Configuration 12-Factor App · ✅ Done

En tant que développeur, je veux que toute la configuration soit externalisée via variables
d'environnement afin de respecter la méthodologie 12-Factor App et d'éviter tout hardcoding.

- **Given** : un fichier `.env.example` documenté
- **When** : je lance l'application avec des variables d'environnement injectées
- **Then** : l'application démarre correctement — aucune valeur de configuration (JWT secret,
  URL BDD, ports) n'est codée en dur dans le code source.

### STR-28 — Initialisation de la base de données PostgreSQL · ✅ Done

En tant que développeur backend, je veux un schéma PostgreSQL versionné afin de garantir la
reproductibilité des migrations et la cohérence de la base entre les environnements.

- **Given** : un conteneur PostgreSQL vide
- **When** : j'exécute les migrations
- **Then** : toutes les tables (users, streams, tracks, playlists, queue_items) sont créées avec
  les contraintes d'intégrité et les index appropriés.

> ⚠️ Le schéma livré compte **12 tables**, pas cinq : l'énoncé date du cadrage initial. Voir
> [`database.md`](database.md).

### US-01-06 (STR-92) — Initialisation du projet Flutter mobile · ✅ Done · 4 pts

En tant que développeur Flutter, je veux un projet mobile structuré avec la Clean Architecture
et toutes les dépendances configurées, afin que l'équipe puisse commencer à développer les
features sans configuration préalable.

- **Given** : le développeur clone le repo et se place dans `mobile/`
- **When** : il exécute `flutter pub get` puis `flutter analyze`
- **Then** : le projet compile et l'analyse ne remonte aucune issue.

---

## 2. Authentification & Gestion des Rôles

### STR-33 — Inscription d'un nouvel utilisateur · ✅ Done

En tant que visiteur, je veux créer un compte avec mon email et un mot de passe afin d'accéder
aux fonctionnalités personnalisées de la plateforme.

- **Given** : un visiteur sur l'écran d'inscription
- **When** : il soumet un email valide, un pseudonyme unique et un mot de passe ≥ 8 caractères
- **Then** : le compte est créé, le mot de passe est haché avec bcrypt (coût ≥ 12), une
  confirmation est affichée et l'utilisateur peut se connecter immédiatement.

### STR-38 — Connexion sécurisée avec JWT · ✅ Done

En tant qu'utilisateur inscrit, je veux me connecter avec mon email et mot de passe afin
d'obtenir un token JWT pour accéder aux ressources protégées.

- **Given** : un utilisateur inscrit
- **When** : il saisit ses identifiants corrects
- **Then** : l'API retourne un access token JWT (exp. 15 min) et un refresh token (exp. 7 jours)
  — le token contient le rôle de l'utilisateur dans ses claims.

### STR-44 — Gestion du profil utilisateur · ✅ Done

En tant qu'utilisateur connecté, je veux consulter et modifier mes informations personnelles
afin de maintenir mon profil à jour.

- **Given** : un utilisateur connecté sur son profil
- **When** : il modifie son pseudo ou son avatar et valide
- **Then** : les modifications sont sauvegardées, l'UI est mise à jour et une confirmation est
  affichée.

### STR-49 — Demande et activation du rôle Diffuseur · ✅ Done

En tant qu'utilisateur standard, je veux demander le rôle Diffuseur depuis mon profil afin de
pouvoir créer et gérer des flux live.

- **Given** : un utilisateur au rôle User standard
- **When** : il soumet une demande de rôle Diffuseur
- **Then** : sa demande est en attente, un admin peut l'approuver depuis le tableau de bord —
  après approbation, l'utilisateur obtient le rôle Diffuseur et peut créer des flux.

### STR-54 — Réinitialisation du mot de passe · ✅ Done

En tant qu'utilisateur ayant oublié son mot de passe, je veux recevoir un lien de
réinitialisation par email afin de récupérer l'accès à mon compte.

- **Given** : un email valide soumis sur l'écran « mot de passe oublié »
- **When** : l'utilisateur clique sur le lien reçu (valide 1 h)
- **Then** : il peut définir un nouveau mot de passe — l'ancien token est invalidé après usage.

### STR-59 — Suppression de compte (conformité RGPD) · ✅ Done

En tant qu'utilisateur connecté, je veux pouvoir supprimer définitivement mon compte et toutes
mes données afin d'exercer mon droit à l'effacement (RGPD art. 17).

- **Given** : un utilisateur authentifié qui confirme la suppression
- **When** : il valide la suppression (double confirmation)
- **Then** : toutes ses données personnelles (email, pseudo, historique, playlists, fichiers
  audio) sont supprimées de la base de données et du stockage.

---

## 3. Moteur de Streaming Live (Backend Go)

### STR-64 — Création et configuration d'un flux live · ✅ Done

En tant que diffuseur, je veux créer un nouveau flux live avec un titre, une description et une
visibilité afin de le préparer avant de commencer la diffusion.

- **Given** : un diffuseur authentifié
- **When** : il crée un flux (titre, description, public/privé)
- **Then** : le flux est persisté en base avec le statut « inactif », un identifiant unique est
  généré et le diffuseur obtient l'URL de stream source.

### STR-70 — Moteur HLS : segmentation et génération du manifeste · ✅ Done

En tant que backend, je veux segmenter le flux audio entrant en fichiers `.ts` de ~10 secondes
et générer un manifeste `.m3u8` mis à jour en continu afin de permettre la lecture HLS par les
clients.

- **Given** : un diffuseur envoie un flux audio AAC via HTTP multipart
- **When** : le backend reçoit le flux
- **Then** : des segments `.ts` sont générés toutes les 10 secondes, le manifeste `.m3u8` est mis
  à jour avec les nouveaux segments, et un auditeur peut récupérer le manifeste et démarrer la
  lecture.

### STR-77 — Démarrage et arrêt du flux (diffuseur) · ✅ Done

En tant que **diffuseur**, je veux **démarrer** puis **arrêter** mon flux en direct afin de
passer un flux préparé (`idle`) en diffusion (`live`), puis le terminer proprement (`ended`) en
prévenant les auditeurs.

- **Given** : un diffuseur authentifié, propriétaire d'un flux `idle`, sans autre flux déjà en direct
- **When** : il démarre le flux (`PATCH /api/streams/{id}/start`)
- **Then** : le statut passe à `live`, `started_at` est renseigné, une session de diffusion est
  enregistrée en mémoire (goroutine annulable), et le flux devient visible dans la liste des directs.

- **Given** : un diffuseur propriétaire d'un flux `live`
- **When** : il arrête le flux (`PATCH /api/streams/{id}/stop`)
- **Then** : le statut passe à `ended`, `ended_at` est renseigné, la goroutine de session est
  libérée (aucune fuite), et les auditeurs abonnés reçoivent un événement `ended` en temps réel (SSE).

Critères complémentaires :

- **Un seul flux `live` à la fois par diffuseur** : un `start` est refusé (409) si le diffuseur
  a déjà un flux en direct, ou si le flux est déjà `live` — un flux `idle` ou `ended` se lance
  (ADR 048).
- **Owner-only** : seul le propriétaire (rôle `broadcaster`) peut `start`/`stop` (404 sinon) ;
  `stop` sur un flux non-`live` → 409 ; `ended` se relance (`ended → live`, ADR 048).
- **Notification temps réel** : `GET /api/streams/{id}/events` expose un flux SSE.
- **Concurrence propre** : chaque session est annulée via `context.Context` au `stop` et à
  l'arrêt du serveur ; absence de fuite de goroutines vérifiée par test.

### STR-87 — Scalabilité : gestion de N auditeurs simultanés · ✅ Done

En tant que système, je veux supporter au moins 50 auditeurs simultanés sur un même flux afin
de prouver la scalabilité du moteur de streaming Go.

- **Given** : un flux HLS actif
- **When** : 50 clients HTTP simulent la récupération du manifeste et des segments
- **Then** : la latence p95 reste < 300 ms, la consommation mémoire est < 2 Mo/connexion et
  aucune goroutine leak n'est détectée via pprof.

---

## 4. Expérience Auditeur Mobile (Flutter)

### US-04-01 (STR-107) — Découverte et liste des flux actifs · ✅ Done · 2 pts

En tant qu'auditeur (ou anonyme), je veux voir la liste des flux en direct afin de rejoindre
facilement une émission qui m'intéresse.

- **Given** : des flux publics actifs existent
- **When** : j'ouvre l'écran d'accueil
- **Then** : la liste des flux actifs s'affiche avec titre, nombre d'auditeurs et durée de
  diffusion — elle se rafraîchit automatiquement toutes les 10 secondes.

*Dépendances : US-03-01, US-02-02*

### US-04-02 (STR-108) — Lecteur audio HLS (play/pause/volume) · ✅ Done · 4 pts

En tant qu'auditeur, je veux écouter un flux live HLS avec des contrôles de lecture afin de
profiter d'une expérience audio fluide.

- **Given** : un flux actif rejoint
- **When** : le lecteur s'ouvre
- **Then** : la lecture démarre automatiquement en < 3 secondes, les contrôles play/pause et le
  réglage de volume sont fonctionnels, le titre du flux est affiché et le taux de rebuffering
  est < 2 %.

*Dépendances : US-03-02, US-04-01*

> ⚠️ Le **réglage de volume in-app n'est pas livré** : le volume est délégué aux boutons
> matériels. Ce critère du sujet reste ouvert, suivi dans STR-244.

### US-04-03 (STR-109) — Lecture audio en arrière-plan · ✅ Done · 3 pts

En tant qu'auditeur, je veux que la lecture continue quand je quitte l'application afin de
pouvoir utiliser mon téléphone librement pendant l'écoute.

- **Given** : un flux en cours d'écoute
- **When** : l'utilisateur appuie sur le bouton Home
- **Then** : la lecture continue sans interruption et les contrôles apparaissent dans la barre
  de notification et sur l'écran de verrouillage (iOS et Android).

*Dépendances : US-04-02*

### US-04-04 (STR-110) — Gestion des interruptions · ✅ Done · 2 pts

En tant qu'auditeur, je veux que la lecture se mette en pause lors d'un appel entrant et
reprenne automatiquement ensuite afin de ne pas manquer de contenu.

- **Given** : un flux en lecture en arrière-plan
- **When** : un appel téléphonique entrant est reçu
- **Then** : la lecture se met en pause automatiquement — et quand l'appel se termine, la
  lecture reprend depuis le point courant du flux live.

*Dépendances : US-04-03*

### US-04-05 (STR-111) — Ajout d'un flux aux favoris · ✅ Done · 1 pt

En tant qu'utilisateur connecté, je veux ajouter un flux à mes favoris afin de le retrouver
facilement lors de sa prochaine diffusion.

- **Given** : un utilisateur connecté sur la page d'un flux
- **When** : il appuie sur l'icône favoris
- **Then** : le flux est ajouté à sa liste de favoris, l'icône change d'état — et le flux
  apparaît dans son onglet Favoris.

*Dépendances : US-04-01, US-02-02*

---

## 5. Bibliothèque Audio à la Demande

### US-05-01 (STR-130) — Upload d'une piste audio · ✅ Done · 3 pts

En tant que diffuseur ou utilisateur, je veux uploader un fichier audio (MP3/AAC/OGG) afin de
l'ajouter à ma bibliothèque personnelle.

- **Given** : un utilisateur connecté
- **When** : il sélectionne un fichier audio ≤ 50 Mo au format MP3/AAC/OGG
- **Then** : le fichier est uploadé, son MIME type est validé côté serveur, il est stocké hors
  répertoire web et référencé en base avec ses métadonnées (titre, durée, taille).

*Dépendances : US-02-02, US-01-05*

### US-05-02 (STR-131) — Création et gestion de playlists · ✅ Done · 2 pts

En tant qu'utilisateur connecté, je veux créer, renommer et supprimer mes playlists afin
d'organiser ma bibliothèque musicale personnelle.

- **Given** : un utilisateur connecté
- **When** : il crée une playlist avec un nom
- **Then** : la playlist est créée vide et apparaît dans sa liste — il peut la renommer ou la
  supprimer à tout moment, avec confirmation avant suppression.

*Dépendances : US-02-02, US-01-05*

### US-05-03 (STR-132) — Ajout et réorganisation de pistes · ✅ Done · 3 pts

En tant qu'utilisateur, je veux ajouter, supprimer et réorganiser les pistes d'une playlist afin
de construire une file d'écoute personnalisée.

- **Given** : une playlist existante
- **When** : l'utilisateur ajoute une piste ou change son ordre par drag-and-drop
- **Then** : la modification est persistée, la playlist affiche le nouvel ordre et la file
  d'attente (queue) est mise à jour.

*Dépendances : US-05-01, US-05-02*

### US-05-04 (STR-133) — Lecture d'une playlist avec file d'attente · ✅ Done · 3 pts

En tant qu'utilisateur, je veux lire ma playlist avec passage automatique à la piste suivante
afin de profiter d'une écoute continue sans intervention.

- **Given** : une playlist avec 3+ pistes
- **When** : l'utilisateur lance la lecture
- **Then** : les pistes s'enchaînent automatiquement, la file d'attente est visible,
  l'utilisateur peut sauter à n'importe quelle piste — la lecture continue en arrière-plan.

*Dépendances : US-05-03, US-04-03*

### US-05-05 (STR-134) — Modes Shuffle et Repeat · ✅ Done · 1 pt

En tant qu'utilisateur, je veux activer le mode lecture aléatoire (shuffle) ou la répétition
(repeat track / repeat playlist) afin de varier mon expérience d'écoute.

- **Given** : une playlist en cours de lecture
- **When** : l'utilisateur active le shuffle
- **Then** : l'ordre de lecture devient aléatoire — et avec repeat-one, la piste courante se
  répète indéfiniment.

*Dépendances : US-05-04*

---

## 6. Tableau de Bord Diffuseur

### US-06-01 (STR-153) — Lancer et arrêter un flux depuis le dashboard · ✅ Done · 4 pts

En tant que diffuseur, je veux lancer et arrêter mon flux depuis une interface simplifiée afin
de contrôler ma diffusion sans complexité technique.

- **Given** : un diffuseur sur son tableau de bord
- **When** : il appuie sur « Démarrer la diffusion »
- **Then** : l'application commence à envoyer le flux audio au backend, le statut du flux passe
  à « En direct » et le compteur d'auditeurs s'affiche en temps réel.

*Dépendances : US-03-03, US-02-04*

### US-06-02 (STR-154) — Statistiques de diffusion en temps réel · ✅ Done · 2 pts

En tant que diffuseur, je veux voir les statistiques de mon flux en temps réel (auditeurs
connectés, durée, déconnexions) afin d'évaluer l'audience de ma diffusion.

- **Given** : un flux actif
- **When** : je consulte mon tableau de bord diffuseur
- **Then** : le nombre d'auditeurs connectés est affiché et mis à jour toutes les 5 secondes,
  ainsi que la durée totale de diffusion.

*Dépendances : US-06-01, US-03-02*

> ⚠️ Le comptage d'auditeurs est une **estimation** : HLS est sans connexion persistante. Voir
> [ADR 025](adr/025-statistiques-daudience-en-temps-reel.md).

---

## 7. Observabilité & Supervision

### US-07-01 (STR-163) — Logs structurés JSON · ✅ Done · 2 pts

En tant que SRE, je veux que tous les logs du backend Go soient émis au format JSON structuré
afin de permettre leur indexation automatique dans Loki et leur analyse par des outils tiers.

- **Given** : l'application Go en cours d'exécution
- **When** : une requête HTTP est traitée ou une erreur survient
- **Then** : un log JSON est émis avec les champs timestamp, level, message, trace_id, service,
  environment — aucun `fmt.Println()` n'existe en production.

*Dépendances : US-01-02*

### US-07-02 (STR-164) — Instrumentation OpenTelemetry · ✅ Done · 4 pts

En tant que développeur, je veux instrumenter le backend Go avec OpenTelemetry afin de pouvoir
tracer le cheminement d'une requête de l'app mobile jusqu'à la base de données.

- **Given** : le SDK OTEL Go configuré
- **When** : une requête arrive sur l'API
- **Then** : un span est créé pour chaque handler HTTP, les spans de requêtes SQL sont
  enregistrés, le trace_id est propagé dans les headers — et la trace complète
  (mobile → API → DB) est visible dans Tempo/Grafana.

*Dépendances : US-07-01, US-01-02*

> ⚠️ **Critère partiellement atteint.** La trace commence au serveur : aucun `traceparent` n'est
> émis par le client Flutter. Le volet `API → DB` est livré, le volet `mobile →` ne l'est pas.
> Voir [ADR 020](adr/020-traces-opentelemetry-otlp-tempo.md) et STR-244.

### US-07-03 (STR-165) — Métriques Prometheus + panels API & Infra · ✅ Done · 3 pts

En tant que SRE, je veux exposer des métriques HTTP et infrastructure via Prometheus afin de les
visualiser dans les panels Grafana API Backend et Infrastructure.

- **Given** : l'application Go démarrée
- **When** : Prometheus scrape `/metrics` toutes les 15 secondes
- **Then** : les métriques `http_requests_total`, `http_request_duration_seconds` (p50/p95/p99),
  `go_goroutines` et `go_memstats_heap_alloc_bytes` sont collectées et visibles dans Grafana.

*Dépendances : US-07-01, US-01-02*

### US-07-04 (STR-166) — Dashboard Grafana Panel Live Streaming · ✅ Done · 3 pts

En tant que SRE, je veux un dashboard dédié au streaming live afin de visualiser en temps réel
le nombre de flux actifs, les auditeurs connectés, la latence HLS et le taux de rebuffering.

- **Given** : au moins un flux actif et des auditeurs connectés
- **When** : je consulte le Panel 1 dans Grafana
- **Then** : les gauges affichent le nombre de flux actifs, d'auditeurs connectés par flux, la
  latence HLS p95 et le taux d'erreurs sur les segments `.ts` — avec des données réelles, pas
  des fixtures.

*Dépendances : US-07-03, US-03-02*

### US-07-05 (STR-167) — Panel Logs & Erreurs + Alertes · ✅ Done · 3 pts

En tant que SRE, je veux visualiser les logs en temps réel dans Grafana et configurer des
alertes sur les seuils critiques afin d'être notifié proactivement des incidents.

- **Given** : les logs JSON indexés dans Loki et les traces dans Tempo
- **When** : je consulte le Panel 4
- **Then** : les logs filtrables par niveau (info/warn/error) et par trace_id sont visibles — et
  une alerte se déclenche si le taux d'erreurs HTTP 5xx dépasse 5 % sur 5 minutes.

*Dépendances : US-07-01, US-07-02, US-07-03*

---

## 8. Tableau de Bord Administrateur

### US-08-01 (STR-191) — Liste, recherche et gestion des utilisateurs · ✅ Done · 3 pts

En tant qu'administrateur, je veux consulter et gérer la liste complète des utilisateurs afin
d'assurer la supervision de la communauté.

- **Given** : un administrateur connecté sur `/admin`
- **When** : il recherche un utilisateur par nom ou filtre par rôle
- **Then** : la liste filtrée s'affiche — il peut activer, désactiver ou supprimer un compte
  avec confirmation.

*Dépendances : US-02-02, US-02-04*

### US-08-02 (STR-192) — Supervision et interruption des flux actifs · ✅ Done · 2 pts

En tant qu'administrateur, je veux voir tous les flux actifs et pouvoir en interrompre un si
nécessaire afin de modérer la plateforme.

- **Given** : un administrateur sur le tableau de bord
- **When** : il sélectionne un flux actif et clique sur « Interrompre »
- **Then** : le flux est arrêté immédiatement, les auditeurs reçoivent une notification de fin
  et un log d'audit est enregistré.

*Dépendances : US-03-03, US-08-01*

---

## 9. Fonctionnalités bonus

Le sujet note ces fonctionnalités sur 5 points, en supplément des 15 du socle.

### US-09-01 (STR-200) — Chat en direct entre auditeurs (WebSocket) · ⬜ Backlog · 5 pts

En tant qu'auditeur d'un flux, je veux envoyer et recevoir des messages en temps réel afin
d'interagir avec la communauté pendant la diffusion.

- **Given** : plusieurs auditeurs connectés au même flux
- **When** : l'un envoie un message texte
- **Then** : tous les auditeurs reçoivent le message en < 500 ms via WebSocket — le diffuseur
  peut supprimer un message ou bannir un utilisateur du chat.

*Dépendances : US-03-02, US-02-02*

### US-09-02 (STR-201) — Mode hors ligne (cache playlists) · 🔵 In Review · 5 pts

En tant qu'utilisateur, je veux rendre une playlist disponible hors connexion afin d'écouter mes
pistes sans accès internet.

- **Given** : une playlist avec des pistes
- **When** : l'utilisateur active le mode offline pour cette playlist
- **Then** : les fichiers audio sont téléchargés et mis en cache localement — la playlist est
  accessible et lisible sans réseau, avec indication visuelle de l'état hors ligne.

*Dépendances : US-05-04*

### US-09-03 (STR-202) — Déploiement Kubernetes · ⬜ Backlog · 5 pts

En tant que DevOps, je veux déployer StreamPulse sur un cluster Kubernetes avec gestion des
ressources afin de démontrer une infrastructure cloud-native production-grade.

- **Given** : un cluster K8s disponible (Minikube ou cloud)
- **When** : j'applique les manifests kubectl
- **Then** : l'API Go, PostgreSQL et la stack OTEL sont déployés avec des limits/requests de
  ressources configurés, un HorizontalPodAutoscaler est actif et l'application répond sur son
  endpoint.

*Dépendances : US-01-03*

### US-09-04 (STR-203) — Algorithme de recommandation simple · ⬜ Backlog · 4 pts

En tant qu'utilisateur, je veux voir des flux et playlists recommandés sur ma page d'accueil
afin de découvrir du contenu correspondant à mes goûts.

- **Given** : un utilisateur avec un historique d'écoute
- **When** : il ouvre la page d'accueil
- **Then** : une section « Recommandé pour vous » affiche 5 flux ou playlists basés sur ses
  catégories les plus écoutées (collaborative filtering simplifié ou content-based).

*Dépendances : US-04-02, US-05-04*

### US-09-05 (STR-204) — Transcodage à la volée (FFmpeg) · ✅ Done · 4 pts

En tant que système, je veux transcoder les formats audio non-AAC à la volée avec FFmpeg afin
d'accepter n'importe quel format entrant (MP3, OGG, WAV) pour la diffusion HLS.

- **Given** : un diffuseur qui envoie un flux MP3
- **When** : le backend reçoit le flux
- **Then** : FFmpeg transcode le flux en AAC à la volée, le résultat est segmenté en HLS et les
  auditeurs reçoivent un flux AAC propre — la latence supplémentaire due au transcodage est
  < 2 secondes.

*Dépendances : US-03-02*

> ⚠️ Ce transcodage porte sur l'**ingest** (normaliser le format entrant), pas sur l'adaptation
> du débit à la bande passante de l'auditeur. Le sujet, lui, demande le second. Voir
> [ADR 030](adr/030-transcodage-a-la-volee-des-formats-dingest.md).

---

## Correspondance des épopées sans numéro

⚠️ **Proposition, à confirmer par l'équipe.** Ces correspondances sont déduites du sens des
dépendances déclarées dans Linear ; aucune décision écrite ne les fixe.

| Numéro cité en dépendance | Épopée probable | Ticket |
|---|---|---|
| US-01-02 | Mise en place de Docker Compose | STR-11 |
| US-01-03 | Pipeline CI/CD GitHub Actions | STR-17 |
| US-01-05 | Initialisation de la base PostgreSQL | STR-28 |
| US-01-06 | Initialisation du projet Flutter | STR-92 ✅ *(confirmé par le titre)* |
| US-02-02 | Connexion sécurisée avec JWT | STR-38 |
| US-02-04 | Demande et activation du rôle Diffuseur | STR-49 |
| US-03-01 | Création et configuration d'un flux live | STR-64 |
| US-03-02 | Moteur HLS : segmentation et manifeste | STR-70 |
| US-03-03 | Démarrage et arrêt du flux | STR-77 |

Les numéros `US-01-01` et `US-01-04` ne sont cités par aucune dépendance ; ils correspondent
vraisemblablement à STR-5 (repository Git) et STR-23 (12-Factor), sans qu'on puisse le
départager.

---

## Ce que ce document ne couvre pas

- Les **sous-tâches** de chaque story (une centaine de tickets `STR-NNN` sans énoncé
  utilisateur) : elles décrivent des étapes d'implémentation, pas des attentes utilisateur.
- Les **tickets de correction** ouverts après l'audit de conformité (STR-232 à STR-245) : ils
  vivent dans un projet Linear distinct et ne sont pas des user stories.
