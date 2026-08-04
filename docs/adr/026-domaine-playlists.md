# ADR 026 — Domaine playlists : CRUD, isolation propriétaire et unicité du nom

**Date** : 2026-08-04
**Statut** : Accepté
**Ticket** : [STR-131](https://linear.app/streampulse/issue/STR-131) (US-05-02)

---

## Contexte

US-05-02 : un utilisateur connecté doit pouvoir **créer, renommer et supprimer** ses playlists
pour organiser sa bibliothèque, avec confirmation avant suppression. L'US demande aussi la
surface REST CRUD `/api/playlists` et l'endpoint `GET /api/playlists/{id}/tracks`.

Les tables `playlists` et `playlist_tracks` **existent déjà** (migration `000004`) :
`playlists(id, user_id, name, description, is_public, created_at, updated_at)` et
`playlist_tracks(playlist_id, track_id, position, added_at)`. La migration `000006` a posé
`UNIQUE (user_id, name)` (`uq_playlists_user_name`). Un seeder alimente déjà une playlist de démo
(« My Favorites » + 3 pistes) pour `user1`.

Aucun domaine Go, route, ni endpoint OpenAPI n'exploitait ces tables jusqu'ici. Cette US crée le
**paquet `internal/playlist/`** complet (handler / service / repository / queries sqlc), calqué
sur `internal/streaming` ([ADR 013](013-domaine-streaming.md)), plus la feature Flutter
`features/playlists/`. C'est un nouveau domaine fonctionnel complet → il mérite son ADR au même
titre que 013 (streaming), 014 (diffuseur), 017/018 (admin), 023 (lecteur mobile).

Ce document consigne les décisions qui **ne se déduisent pas du code**.

---

## Décision

### 1. Isolation propriétaire → **404** (jamais 403) sur la playlist d'un tiers

`GetPlaylist` et `ListTracks` renvoient `apperror.NotFound` si la playlist n'appartient pas au
demandeur (comparaison `user_id`) ; `Update`/`Delete` filtrent directement sur `(id, user_id)` en
SQL (0 ligne affectée → 404). On ne renvoie **pas** 403 : un 403 divulguerait l'existence de la
ressource. Choix **cohérent** avec les flux privés d'un tiers (ADR 013 §1). La liste d'un
utilisateur ne contient que ses propres playlists.

### 2. `PUT` = **remplacement total** de la ressource

`PUT /api/playlists/{id}` remplace nom **et** description. Omettre `description` dans le corps la
met à `NULL` (`sqlc.narg`). Sémantique REST légitime pour un PUT, et le flux mobile est sûr (la
bottom sheet de renommage **pré-remplit** la description existante). **Piège documenté** pour tout
autre client : renommer sans renvoyer `description` l'efface silencieusement — mentionné dans la
description OpenAPI de l'opération. Un `PATCH` partiel pourra être ajouté si un besoin apparaît.

### 3. Unicité du nom **déléguée à la contrainte SQL** (23505 → 409)

On ne fait **pas** de `SELECT` préalable « ce nom existe-t-il ? » (sujet aux courses entre deux
requêtes concurrentes). On laisse l'INSERT/UPDATE lever la violation de `uq_playlists_user_name`
(SQLSTATE `23505`), que le repository mappe en `apperror.Conflict` → **409**. Atomique, sans
fenêtre de course. S'applique à la création **et** au renommage.

### 4. `track_count` via `LEFT JOIN` + `GROUP BY` (pas de N+1)

`GET /api/playlists` renvoie le nombre de pistes par playlist. Il est calculé en **une seule
requête** (`LEFT JOIN playlist_tracks … GROUP BY p.id`, `LEFT` pour compter 0 sur une playlist
vide) plutôt qu'une requête de comptage par ligne (N+1).

### 5. Pas de pagination sur `GET /api/playlists`

Choix **assumé à ce stade** : une bibliothèque personnelle reste de taille modeste et le tri
(`created_at DESC`) suffit. À réévaluer si le volume par utilisateur le justifie — la pagination
`limit/offset` du domaine streaming servira de modèle.

### 6. `is_public` exposé en lecture, non éditable ici

La colonne existe (défaut `false`, le seed « My Favorites » est `true`). Elle est **renvoyée** dans
`PlaylistResponse` (cohérence avec le schéma/seed) mais **non modifiable** via cette API : le
partage de playlist n'est pas dans le périmètre de l'US.

### 7. Pas de migration

Les tables `000004` + la contrainte `000006` suffisent. Aucune nouvelle migration ; nouvelle
entrée `sqlc.yaml` pour générer `internal/playlist/db`.

### 8. Côté Flutter : `ChangeNotifierProvider` **local à l'écran**

`PlaylistsController` est instancié dans le `build` de `PlaylistsScreen` (pattern déjà utilisé
pour `AdminStreamsScreen`), pas dans le `MultiProvider` global. C'est **précisément** ce qui évite
la fuite d'état entre comptes rencontrée sur les favoris ([#266](https://github.com/LignacAntony/streampulse/pull/266))
: à la déconnexion/reconnexion, l'écran est reconstruit et le contrôleur repart vierge. Vérifié en
QA (compte A crée une playlist → reconnexion compte B → B ne voit que les siennes).

### 9. Accès invité

L'onglet Bibliothèque reste accessible à un invité (découverte publique), mais **toutes** les
routes sont derrière `RequireAuth` (401 sans token) et l'UI masque le bouton « + » tant qu'aucun
token n'est présent : seul un utilisateur connecté peut posséder une playlist.

---

## Conséquences

- **Positif** : domaine isolé et testé (service + handler côté Go ; datasource + controller +
  widget côté Flutter), contrat OpenAPI complet + client Dart régénéré, sécurité d'isolation
  vérifiée (404 entre comptes, pas de fuite d'état mobile).
- **Dette assumée** : pas de pagination (décision 5) ; PUT total = piège client documenté
  (décision 2) ; le partage (`is_public`) et la gestion des pistes (ajout/retrait/réordonnancement)
  restent hors périmètre.
- **Hors périmètre livré en front non branché** (PR dédiée à venir) : dans la bottom sheet de
  création, le sélecteur de couverture et le toggle « Disponible hors ligne » sont présents mais
  neutralisés visuellement (« Bientôt disponible »), sans logique backend.
