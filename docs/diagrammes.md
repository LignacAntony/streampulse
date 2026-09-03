# Diagrammes — StreamPulse

> 🇬🇧 **English version: [en/diagrams.md](en/diagrams.md)**

> Version : 1.2.0 — dernière révision : 2026-08-19

Vues standardisées du système, en notation UML rendue par Mermaid — GitHub les affiche
nativement, sans outil ni image à régénérer.

**Chaque diagramme est suivi d'un équivalent textuel.** Un diagramme reste une image pour un
lecteur d'écran ; la description qui l'accompagne porte la même information sous forme lisible.

Le schéma de données a son propre document : [`database.md`](database.md).

---

## 1. Cas d'utilisation — les quatre rôles

```mermaid
graph LR
    anonyme(("Anonyme"))
    user(("Utilisateur"))
    diffuseur(("Diffuseur"))
    admin(("Administrateur"))

    anonyme --> UC1["Découvrir les flux en direct"]
    anonyme --> UC2["Écouter un flux public"]
    anonyme --> UC3["S'inscrire / se connecter"]

    user --> UC1
    user --> UC2
    user --> UC4["Mettre un flux en favori"]
    user --> UC5["Téléverser une piste"]
    user --> UC6["Gérer ses playlists"]
    user --> UC7["Écouter une playlist"]
    user --> UC8["Gérer son profil"]
    user --> UC9["Demander le rôle diffuseur"]
    user --> UC10["Supprimer son compte"]

    diffuseur --> UC11["Créer un flux"]
    diffuseur --> UC12["Démarrer / arrêter un direct"]
    diffuseur --> UC13["Diffuser depuis le micro"]
    diffuseur --> UC14["Consulter son audience"]
    diffuseur --> UC15["Faire tourner sa clé de diffusion"]

    admin --> UC16["Gérer les comptes"]
    admin --> UC17["Superviser les flux actifs"]
    admin --> UC18["Interrompre un flux"]
    admin --> UC19["Traiter les demandes de rôle"]

    user -.hérite de.-> anonyme
    diffuseur -.hérite de.-> user
    admin -.hérite de.-> diffuseur
```

**Équivalent textuel** — Quatre rôles hiérarchisés : chacun hérite des capacités du précédent,
dans l'ordre anonyme → utilisateur → diffuseur → administrateur. L'anonyme découvre et écoute
les flux publics, et peut s'inscrire. L'utilisateur y ajoute les favoris, la bibliothèque, les
playlists, son profil, la demande de rôle et la suppression de compte. Le diffuseur y ajoute la
création de flux, le démarrage et l'arrêt d'un direct, la diffusion depuis le micro, la
consultation de son audience et la rotation de sa clé. L'administrateur y ajoute la gestion des
comptes, la supervision et l'interruption des flux, et le traitement des demandes de rôle.

La hiérarchie est appliquée par `auth.RequireRole` : un rang supérieur satisfait toujours
l'exigence d'un rang inférieur.

---

## 2. Séquence — authentification et rotation du jeton

```mermaid
sequenceDiagram
    autonumber
    participant M as Application mobile
    participant A as API Go
    participant DB as PostgreSQL

    M->>A: POST /api/auth/login (email, mot de passe)
    A->>DB: SELECT user WHERE email
    DB-->>A: utilisateur + password_hash
    A->>A: bcrypt.CompareHashAndPassword
    A->>A: signer un access token HS256 (15 min, claims sub + role)
    A->>DB: INSERT refresh_tokens (SHA-256 du jeton, 7 jours)
    A-->>M: access token + refresh token
    M->>M: stocker dans le coffre sécurisé de l'OS

    Note over M,A: 15 minutes plus tard

    M->>A: GET /api/playlists (Bearer access token)
    A-->>M: 401 — jeton expiré
    M->>A: POST /api/auth/refresh (refresh token)
    A->>DB: SELECT par hash, vérifier l'expiration
    A->>DB: DELETE l'ancien, INSERT le nouveau
    Note right of A: rotation : un refresh consommé<br/>ne peut plus resservir
    A-->>M: nouvelle paire de jetons
    M->>A: rejouer GET /api/playlists
    A-->>M: 200
```

**Équivalent textuel** — À la connexion, l'API vérifie le mot de passe avec bcrypt, signe un
access token HS256 valable 15 minutes portant l'identifiant et le rôle, et enregistre en base le
**haché SHA-256** d'un refresh token valable 7 jours. Le mobile range les deux dans le coffre
sécurisé de l'OS. Quand l'access token expire, l'API répond 401 ; le client échange alors son
refresh token contre une nouvelle paire. L'ancien refresh est supprimé au passage : un jeton
consommé ne peut plus resservir. Le client rejoue enfin sa requête initiale.

Côté mobile, ce cycle est sérialisé : N requêtes reçues en 401 simultanément ne déclenchent
qu'un seul rafraîchissement.

---

## 3. Séquence — de l'ingest à l'oreille de l'auditeur

```mermaid
sequenceDiagram
    autonumber
    participant D as Diffuseur (mobile)
    participant A as API Go
    participant F as ffmpeg
    participant FS as Répertoire de session
    participant L as Auditeur (mobile)

    D->>A: PATCH /api/streams/{id}/start (Bearer JWT)
    A->>A: statut idle → live, créer la session (context annulable)
    A-->>D: 200 + stream_source_url

    D->>A: POST /api/streams/ingest/{stream_key}
    Note right of A: auth par la clé seule,<br/>sans JWT
    A->>F: écrire l'audio sur stdin
    F->>FS: segments .ts (~10 s) + manifeste .m3u8 glissant

    par Le diffuseur continue de pousser
        loop en continu
            D->>A: octets audio
            A->>F: relais vers stdin
        end
    and L'auditeur lit indépendamment
        L->>A: GET /api/streams/{id}/playlist.m3u8
        A->>FS: lire le manifeste
        A-->>L: 200 (ou 409 si pas encore prêt)
        loop toutes les ~10 s
            L->>A: GET /api/streams/{id}/segments/{segment}.ts
            A-->>L: 200 — segment audio
        end
    end

    D->>A: PATCH /api/streams/{id}/stop
    A->>F: fermer stdin, puis tuer le process
    A->>FS: supprimer le répertoire
    A->>A: statut live → ended, annuler le context
    A-->>L: événement SSE « ended »
```

**Équivalent textuel** — Le diffuseur démarre son flux avec son JWT : le statut passe de `idle`
à `live` et une session annulable est créée en mémoire. Il pousse ensuite l'audio sur la route
d'ingest, authentifiée par la seule clé de diffusion — sans JWT, puisqu'un logiciel de
diffusion tiers ne sait pas en présenter un. L'API relaie ces octets vers l'entrée standard d'un
ffmpeg, qui écrit des segments d'environ dix secondes et un manifeste glissant dans le
répertoire de travail de la session.

En parallèle, l'auditeur récupère le manifeste puis les segments, en boucle. Le fan-out d'un
diffuseur vers N auditeurs se fait donc **par fichiers**, pas par un canal mémoire : chaque
lecteur lit indépendamment.

À l'arrêt, l'API ferme l'entrée de ffmpeg pour lui laisser finaliser son dernier segment, tue le
process, supprime le répertoire, annule le context de session et notifie les auditeurs abonnés
par un événement SSE `ended`.

---

## 4. Composants et flux de déploiement

```mermaid
graph TB
    subgraph clients["Clients"]
        mobile["Application Flutter<br/>iOS · Android"]
    end

    subgraph vps["VPS — réseau streampulse-net"]
        caddy["Caddy<br/>TLS Let's Encrypt<br/>seul port public"]

        subgraph app["Application"]
            api["API Go<br/>net/http · 127.0.0.1:8080"]
            pg[("PostgreSQL 16")]
            vol[/"Volume track_storage"/]
        end

        subgraph obs["Observabilité"]
            prom["Prometheus"]
            loki["Loki"]
            tempo["Tempo"]
            alloy["Alloy"]
            grafana["Grafana"]
        end
    end

    mobile -->|HTTPS| caddy
    caddy -->|HTTP interne| api
    api --> pg
    api --> vol
    prom -->|scrape /metrics| api
    alloy -->|logs JSON| loki
    api -.->|stdout| alloy
    api -->|OTLP| tempo
    grafana --> prom
    grafana --> loki
    grafana --> tempo
```

**Équivalent textuel** — L'application Flutter joint le VPS en HTTPS. **Caddy est le seul point
d'entrée public** : il termine le TLS avec un certificat Let's Encrypt renouvelé
automatiquement, et relaie en HTTP sur le réseau interne vers l'API Go, qui n'écoute que sur la
boucle locale.

L'API parle à PostgreSQL et écrit les fichiers audio sur un volume nommé, hors de tout
répertoire servi.

Trois flux d'observabilité en partent : Prometheus vient chercher les métriques sur `/metrics`
en scrape interne, Alloy collecte la sortie standard de l'API et l'expédie à Loki, et l'API
pousse ses traces à Tempo en OTLP. Grafana lit les trois sources et sert les tableaux de bord
comme les alertes.

⚠️ **Cette vue décrit la cible.** Au 2026-08-19, Prometheus et Grafana sont encore publiés sur
toutes les interfaces du VPS, et le blocage de `/metrics` par Caddy n'est pas déployé — les
correctifs sont écrits mais attendent une synchronisation manuelle de l'infrastructure. Voir
STR-240.

---

## 5. États d'un flux

```mermaid
stateDiagram-v2
    [*] --> idle : création du flux
    idle --> live : PATCH /start (propriétaire, aucun autre direct)
    live --> ended : PATCH /stop
    live --> ended : bail d'ingest expiré (aucun audio pendant N s)
    live --> ended : mort du segmenteur
    ended --> [*]

    idle --> archived : DELETE (suppression douce)
    live --> archived : DELETE
    ended --> archived : DELETE
    archived --> [*]
```

**Équivalent textuel** — Un flux naît `idle` à sa création. Il passe `live` sur demande de son
propriétaire, à condition qu'aucun autre de ses flux ne soit déjà en direct — une contrainte
garantie par un index unique partiel en base, pas seulement par le code.

Trois chemins mènent à `ended` : l'arrêt explicite par le diffuseur, l'expiration du bail
d'ingest lorsque plus aucun audio n'arrive, et la mort du segmenteur. `ended` est **terminal** :
un flux terminé ne redémarre pas.

La suppression est douce et orthogonale : elle renseigne `archived_at` depuis n'importe quel
état, sans effacer la ligne.
