# ADR 032 — Domaine track : upload d'une piste audio

**Date** : 2026-08-07
**Statut** : Accepté
**Ticket** : [STR-130](https://linear.app/streampulse/issue/STR-130) (US-05-01)

---

## Contexte

US-05-01 : un utilisateur connecté (diffuseur **ou** simple utilisateur) doit pouvoir uploader un
fichier audio (MP3/AAC/OGG, ≤ 50 Mo) dans sa bibliothèque personnelle. Le fichier doit être
stocké hors répertoire servi, son vrai type MIME validé côté serveur, et la piste référencée en
base avec ses métadonnées (titre, durée, taille).

La table `tracks` existe déjà (migration `000003`) avec toutes les colonnes nécessaires —
`file_path`, `mime_type` (CHECK `IN ('audio/mpeg','audio/aac','audio/ogg')`), `file_size`,
`duration_s` (CHECK `> 0`) — et la contrainte `uq_tracks_user_title (user_id, title)` (`000006`).
Jusqu'ici, seule la **lecture** existait : `GET /api/tracks`, hébergé temporairement dans le
domaine `internal/playlist/` (cf. [ADR 029](029-pistes-dune-playlist-ajout-retrait-reordonnancement.md) §7,
qui désignait cette US comme le moment de l'extraction).

Ce document consigne les décisions qui **ne se déduisent pas du code**.

---

## Décision

### 1. Extraction d'un domaine `internal/track/` dédié

`GET /api/tracks` quitte le domaine `playlist` pour un nouveau domaine `track`
(handler/service/repository + bloc sqlc `trackdb`), qui porte aussi `POST /api/tracks`. Le domaine
`playlist` conserve ses seules requêtes internes de propriété de piste (utilisées par `AddTrack`).

Raison : l'upload introduit de la logique propre (validation MIME, stockage fichier) qui n'a rien
à voir avec les playlists ; laisser le tout dans `playlist` aurait gonflé un domaine déjà large.
Le contrat OpenAPI retague ces routes sous `Track`, ce qui déplace `listUserTracks` du `PlaylistApi`
généré vers un nouveau `TrackApi` côté mobile (le `PlaylistRemoteDataSource` reçoit désormais les
deux clients).

### 2. Stockage sur le système de fichiers, hors répertoire servi

Le binaire audio est écrit sur le filesystem sous un répertoire racine configuré (`STORAGE_PATH`),
**jamais** exposé en HTTP ; seuls le chemin et les métadonnées vivent en base. En Docker, ce
répertoire est un **volume nommé** `track_storage` monté sur `/data/tracks` (persistance à travers
les rebuilds). En `go run` local, un chemin relatif au repo (`./data/tracks`).

Raison : c'est le plus simple et cohérent avec l'infra actuelle (pas de MinIO/S3 dans le
`docker-compose`). L'interface `track.Storage` (`Save`/`Remove`) isole ce choix : passer à un
stockage objet plus tard ne toucherait ni le service ni le handler.

Le nom de fichier est dérivé d'un **UUID généré côté serveur + une extension canonique**, jamais
du nom fourni par le client : aucun risque de traversée de répertoire (même discipline que le
segmenteur HLS, ADR 015). `O_EXCL` à la création garantit qu'on n'écrase jamais un fichier existant.

### 3. Validation du **vrai** type MIME par sniff de contenu (sécurité)

Le type déclaré (nom de fichier, en-tête `Content-Type`) n'est **pas** de confiance : le test de
sécurité de l'US est précisément un PDF renommé `.mp3`. Le service lit les ~3 premiers Kio du
contenu et détecte le type réel via `github.com/gabriel-vasile/mimetype` (Go pur, sans dépendance
transitive ; `http.DetectContentType` de la stdlib ne reconnaît fiablement ni AAC ni OGG).

Le type détecté (et ses parents dans la hiérarchie mimetype — un OGG audio a pour parent
`application/ogg`) est **normalisé** vers la valeur canonique exigée par le CHECK de la table
(`audio/mpeg` | `audio/aac` | `audio/ogg`), qui est ensuite stockée. Tout ce qui ne mappe pas
(PDF, image, conteneur non supporté…) est rejeté en **415**. Le lecteur est rembobiné après le
sniff pour que l'écriture reparte du début.

### 4. La durée est fournie par le client (champ optionnel)

`duration_s` est un champ multipart **optionnel** envoyé par le client, pas extrait côté serveur.

Raison : une extraction serveur (ffprobe) imposerait ffmpeg comme dépendance d'exécution de l'API
(il n'est présent aujourd'hui que pour le segmenteur HLS et absent du `go run` local), pour une
métadonnée d'affichage non critique. La taille (`file_size`) et le type (`mime_type`) restent, eux,
déterminés et validés côté serveur — ce sont les données de confiance.

### 5. Bornes et codes d'erreur

- Taille max : constante `MaxUploadBytes = 50 << 20` (l'US fige 50 Mo — pas de variable d'env). Le
  corps est borné par `http.MaxBytesReader` (dépassement → **413**), avec un contrôle secondaire
  sur la taille de la seule partie fichier.
- Titre requis (trim, 1-200) → **400** sinon ; artiste optionnel ; durée `> 0` si présente.
- Titre déjà utilisé par le même utilisateur (`uq_tracks_user_title`) → **409**.
- Si l'INSERT échoue **après** l'écriture disque, le fichier est supprimé (best-effort) pour ne pas
  laisser d'orphelin.

Rôle requis : `RequireAuth` seul — l'US vise « diffuseur **ou** utilisateur », comme l'actuel
`GET /api/tracks`.

### 6. Quota de stockage par compte + mémoire multipart bornée

Sans borne, un utilisateur authentifié peut boucler des uploads de 50 Mo jusqu'à saturer le volume
— donc le disque du VPS, qui héberge aussi `postgres_data` : un disque plein ferait tomber la base,
pas seulement l'upload. Deux garde-fous :

- **Quota cumulé par utilisateur** : constante `MaxUserStorageBytes = 500 << 20` (500 Mo). Vérifié
  **avant** `Storage.Save` via `SumFileSizeByUser` ; dépassement → **403** (`storage_quota_exceeded`).
  Le **403** (et non 507) est délibéré : c'est une condition **côté client** que réessayer ne résout
  pas (il faut libérer de l'espace), et il garde la réponse **hors du bucket 5xx** qui déclenche
  l'alerte critique 5xx>5% (ADR 021). Le contrôle du quota est placé **après** `detectAudio` : un
  fichier non-audio reçoit 415 (le bon diagnostic) même si le compte est au-dessus du quota.
  Best-effort face à la concurrence (deux uploads simultanés peuvent tous deux passer) — une **borne
  de concurrence globale** type `HLS_MAX_CONCURRENT` fera l'objet d'un ticket séparé.
- **Croissance globale non refermée** : le quota par compte ralentit mais ne borne pas `500 Mo × N`
  comptes. La parade — une **alerte sur l'espace disque du volume** (node_exporter est déjà déployé)
  et/ou un **cap de stockage global** — est laissée à un ticket de suivi : hors périmètre US-05-01, et
  une règle d'alerting Grafana provisionnée mérite d'être validée en rendu, pas ajoutée à l'aveugle.
- **Mémoire multipart** : `ParseMultipartForm(1 << 20)` (et non 10 Mio) — au-delà, le corps déborde
  sur un fichier temporaire (nettoyé par `net/http`). 10 Mio × N requêtes concurrentes saturerait le
  heap (OOMKill du pod). 1 Mio garde l'empreinte mémoire basse, le disque temporaire absorbe le reste.

### 7. Nettoyage des fichiers à la suppression d'un compte

La FK `tracks.user_id` est `ON DELETE CASCADE` : supprimer un compte efface les **lignes** `tracks`
mais **jamais** les fichiers sur le volume → sans action, le volume ne fait que croître.

`track.Service.PurgeUserTracks(userID, deleteUser func() error)` **enrobe** le hard-delete pour
garantir NI fichier orphelin NI ligne fantôme, en trois temps :

1. relève les chemins des fichiers du user (`ListFilePathsByUser`) — avant que la cascade ne les
   rende introuvables ;
2. exécute `deleteUser` (le hard-delete, qui déclenche la cascade sur `tracks`) ;
3. **seulement si (2) a réussi**, supprime les fichiers du `Storage` (best-effort : un échec est
   journalisé, pas propagé).

Ce séquençage (et non « supprimer les fichiers puis le compte ») évite qu'un `deleteUser` en échec
laisse la bibliothèque lister des pistes dont le binaire a déjà disparu. Les deux chemins de
suppression fournissent leur propre `deleteUser` :

- `admin.Service.DeleteUser` (suppression par un admin),
- `auth.Service.DeleteAccount` (suppression de son propre compte).

Injection par **setter** `SetTrackPurger` (interface étroite `UserTrackPurger` déclarée dans chaque
domaine consommateur, ISP), câblée dans `main.go` — même motif que `SetAuditRecorder`/`SetMetrics`,
et sans churn sur les constructeurs (donc sur les tests existants). `*track.Service` la satisfait
(vérif `var _` dans `main.go`).

> Il n'y a pas encore de `DELETE /api/tracks/{id}` (suppression d'une piste isolée) : hors périmètre
> de l'US-05-01, à ouvrir dans un ticket dédié — il réutilisera `Storage.Remove`.

---

## Conséquences

- Nouvelle dépendance directe : `github.com/gabriel-vasile/mimetype`.
- Nouvelle variable d'environnement : `STORAGE_PATH` (+ volume Docker `track_storage`).
- Aucune migration : la table `tracks` avait déjà toutes les colonnes et contraintes.
- Côté mobile, l'upload passe par la méthode **générée** `TrackApi.uploadTrack` : en déclarant la
  route en `multipart/form-data` dans la spec, le générateur dart-dio émet un paramètre
  `MultipartFile file` + un `onSendProgress` (`ProgressCallback`) qui pilote la barre de
  progression. Le Bearer reste injecté par l'intercepteur du `DioClient`. Pas de Dio brut.
