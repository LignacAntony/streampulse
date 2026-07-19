# ADR 017 — Tableau de bord admin : liste, recherche et gestion des utilisateurs

**Date** : 2026-07-19
**Statut** : Accepté
**Ticket** : [STR-191](https://linear.app/streampulse/issue/STR-191) (sous-issues [STR-193](https://linear.app/streampulse/issue/STR-193), [STR-194](https://linear.app/streampulse/issue/STR-194), [STR-195](https://linear.app/streampulse/issue/STR-195), [STR-196](https://linear.app/streampulse/issue/STR-196))

---

## Contexte

US-08-01 : la plateforme n'offrait jusqu'ici aucun moyen pour un administrateur de lister,
rechercher ou gérer les comptes utilisateurs. La seule voie de modération existante est le flux
de demande d'activation du rôle diffuseur (STR-49, [ADR 014](014-demande-activation-role-diffuseur.md)),
qui ne couvre que la promotion `user → broadcaster` — rien ne permet de désactiver un compte
abusif, de le supprimer, ou simplement de parcourir la base des utilisateurs.

STR-191 introduit ce premier tableau de bord admin, réparti sur quatre sous-tickets : STR-193
(recherche/liste paginée), STR-194 (activation/désactivation + suppression), STR-196 (câblage
des rôles côté routes) et STR-195 (écran Flutter). Une question traverse ces quatre lots : que
faire d'un utilisateur qui diffuse en direct au moment où un admin désactive ou supprime son
compte ?

## Décision

### 1. Trois endpoints, nouveau domaine `internal/admin/`

| Méthode | Route | Rôle requis |
|---|---|---|
| GET | `/api/admin/users` | admin |
| PATCH | `/api/admin/users/{id}` | admin |
| DELETE | `/api/admin/users/{id}` | admin |

- `GET` (STR-193) : recherche (`search`, `ILIKE` sur email/username), filtres `role` /
  `status` (listes blanches), pagination `limit`/`offset` bornée (mêmes valeurs que
  `streaming.List`). Réponse `{"users": [...], "total": n}` — le total pilote la pagination
  côté UI.
- `PATCH {id}` (STR-194) : bascule `is_active` (corps `{"is_active": bool}`, champ pointeur
  requis pour distinguer « absent » de `false`).
- `DELETE {id}` (STR-194) : suppression définitive du compte.

Nouveau domaine `backend/internal/admin/` (handler/service/repository + `queries/admin.sql` →
sqlc), suivant le squelette habituel ([ADR 008](008-architecture-handler-service-repository.md)).
Les 3 routes sont montées dans `main.go` derrière `auth.RequireAuth` + `auth.RequireRole("admin")`
(STR-196) — même chaînage que les routes admin de `broadcaster_requests`.

### 2. `LiveStopper` : interface étroite vers le domaine streaming

Un hard delete ne doit jamais laisser une session HLS orpheline (ffmpeg qui tourne encore,
répertoire de segments non nettoyé, flux SSE jamais clos). Le service admin ne dépend donc pas
directement de `streaming.Service` mais d'une interface minimale qu'il déclare lui-même (ISP,
même logique que `Registrar`/`Authenticator` côté auth) :

```go
// internal/admin/service.go
type LiveStopper interface {
    StopLiveForUser(ctx context.Context, userID string) error
}
```

`streaming.Service` l'implémente via une nouvelle méthode : transition DB des streams
`live → ended` de l'utilisateur, puis arrêt des sessions in-memory (`LiveSessions.Stop`, cf.
[ADR 013](013-domaine-streaming.md) §7). Câblage dans `main.go` :
`admin.NewService(adminRepo, streamingSvc)`, avec assertion de compatibilité
`var _ admin.LiveStopper = (*streaming.Service)(nil)`.

**`DeleteUser` appelle `stopper.StopLiveForUser` avant le `DELETE` en base** (jamais après) :
un live ne doit pas survivre à la disparition de son propriétaire, et si l'arrêt du live échoue,
la suppression est annulée (l'erreur est propagée, le repository n'est pas appelé).

### 3. Hard delete vs désactivation (`is_active`)

- **Suppression (`DELETE`)** — définitive. Réutilise la sémantique déjà en place pour
  l'auto-suppression de compte (`DELETE /api/auth/me`, `Handler.DeleteAccount`) et le
  `ON DELETE CASCADE` déjà présent en base. Aucune nouvelle migration.
- **Désactivation (`PATCH is_active=false`)** — réversible, flip d'un booléen déjà présent sur
  `users` et déjà **enforcé côté auth** : `GetUserByEmail` (login) et
  `GetUserByRefreshToken` (refresh) filtrent tous deux `is_active = true`
  (`backend/internal/auth/queries/auth.sql`). Un compte désactivé ne peut donc plus se
  (re)connecter, mais un access token émis avant la désactivation reste valide jusqu'à expiration
  — fenêtre **≤ 15 min**, comparable à la latence de propagation du rôle déjà documentée en
  [ADR 014](014-demande-activation-role-diffuseur.md).
- **La désactivation ne coupe pas un live en cours.** Un diffuseur désactivé pendant sa
  diffusion continue de streamer jusqu'à l'arrêt naturel (ou jusqu'à suppression). L'interruption
  à chaud d'un live pour motif de modération de contenu est un besoin distinct, volontairement
  hors scope ici : suivi par STR-192.

### 4. Garde-fous 409 (self-action et dernier admin actif)

Portés par `internal/admin/service.go`, communs à `SetUserActive` et `DeleteUser` :

- **Self-action** : `targetID == requesterID` → `409 Conflict` (« cannot modify/delete your own
  account »). Un admin ne peut ni se désactiver ni se supprimer lui-même via ces endpoints.
- **Dernier admin actif** : désactiver ou supprimer le dernier compte `role = admin` avec
  `is_active = true` restant → `409 Conflict`, vérifié via un `COUNT(*)` (`AdminCountActiveAdmins`)
  avant d'agir.

9 cas de service testés (`internal/admin/service_test.go`), dont les deux gardes ci-dessus sur
`SetUserActive` et `DeleteUser`, l'ordre stop-avant-delete, et la propagation d'une erreur du
`LiveStopper`.

### 5. Rôle non modifiable par ces endpoints

`PATCH /api/admin/users/{id}` ne touche qu'à `is_active`, jamais à `role` (cf. commentaire de
package `internal/admin/service.go` : « Le rôle n'est pas modifiable ici, hors scope, cf.
STR-51 »). La promotion `user → broadcaster` reste exclusivement le fait du flux de demande
existant (`broadcaster_requests`, [ADR 014](014-demande-activation-role-diffuseur.md)). Réutiliser
ce PATCH pour changer le rôle ouvrirait une surface d'escalade non demandée par US-08-01 (un
admin s'auto-promouvant, ou rétrogradant arbitrairement un autre compte).

### 6. Mobile : feature `admin/` Clean Architecture + forme condensée pour petits domaines

- Nouvelle feature `mobile/lib/features/admin/` (domain/data/presentation), même découpage que
  les features existantes.
- Entrée : tuile `_AdminCard` dans `ProfileScreen`, visible uniquement si `profile.role ==
  'admin'` — l'entité profil exposait déjà `role`, aucune modification backend nécessaire.
- **Décision explicite — forme data condensée pour les petits domaines (≤ 3 endpoints)** :
  `AdminRepositoryImpl` (`mobile/lib/features/admin/data/repositories/admin_repository_impl.dart`)
  parle **directement** à `AdminApi` (package généré `streampulse_api`), sans couche
  `datasource` intermédiaire. Les 4 features historiques (`auth`, `broadcaster`, `profile`,
  `streams`) gardent leur `datasource` : plus d'endpoints et/ou une logique de mapping plus
  riche justifient cette indirection. Pour un domaine strictement CRUD à 3 endpoints, une
  `datasource` n'aurait fait que déléguer 1:1 vers l'API générée (Middle Man).

## Alternatives écartées

### Soft delete (nouvelle colonne `deleted_at`)

Cohérent avec le pattern déjà utilisé pour l'archivage des streams (`archived_at`,
[ADR 013](013-domaine-streaming.md)). **Écarté** : `is_active` couvre déjà « compte
suspendu/inactif » ; ajouter `deleted_at` créerait un **3ᵉ état redondant** (actif / inactif /
soft-deleted) pour une distinction que le produit ne demande pas. Le hard delete + cascade
existant suffit et reste plus simple à raisonner.

### Rôle modifiable via ce PATCH

Éviterait de repasser par le flux `broadcaster_requests` pour rétrograder un compte. **Écarté** :
surface d'escalade de privilèges non requise par US-08-01 ; le flux de demande/validation
existant (STR-49) couvre déjà le seul changement de rôle utile en pratique
(`user → broadcaster`), avec traçabilité de la décision. Réévaluable si un besoin de
rétrogradation apparaît clairement.

### Désactivation coupant le live en cours

Cohérent avec l'intuition « désactiver un compte doit couper immédiatement son accès ».
**Écarté** : duplique une partie de STR-192 (interruption à chaud d'un live pour modération de
contenu) et mélange deux préoccupations distinctes — sanctionner un **compte** (accès) versus
modérer un **contenu diffusé** (le live lui-même). Scindé volontairement : cette tâche ne
traite que l'accès au compte, pas le contenu en cours de diffusion.

### Datasource dédiée pour le domaine admin

Cohérence stricte avec les 4 features mobiles existantes. **Écarté** : à 3 endpoints strictement
CRUD sans logique de cache ni de combinaison de sources, la couche `datasource` ne ferait que
déléguer 1:1 vers l'API générée — complexité ajoutée sans bénéfice mesurable. Le repository impl
reste testable isolément (stub Dio) sans cette indirection.

## Conséquences

- **Nouveaux 409** côté clients : self-action et dernier-admin-actif sur `PATCH`/`DELETE`. Les
  messages d'erreur techniques restent en anglais et sont relayés tels quels dans l'UI mobile
  (convention déjà en place pour les erreurs non-401, cf. `DioClient`).
- **Garde « dernier admin » non transactionnelle** : `CountActiveAdmins` puis l'action ne sont
  pas dans la même transaction SQL. Deux requêtes concurrentes ciblant deux admins **différents**
  peuvent en théorie passer toutes les deux le contrôle et laisser 0 admin actif — fenêtre
  minuscule, récupérable manuellement en base, assumée à l'échelle actuelle du projet. Documenté
  par un commentaire dans `internal/admin/service.go` référençant cet ADR ; à réévaluer si le
  nombre d'admins actifs croît significativement.
- **Hard delete irréversible avec cascade** (streams, tracks, playlists, refresh/password-reset
  tokens, profil, …) : aucune récupération possible après confirmation. Le dialog mobile de
  suppression le rappelle explicitement (« Cette action est irréversible : le compte, ses
  streams et ses playlists seront supprimés en cascade. »).
- **UI admin, une première dans l'app mobile** : `AdminUsersScreen` est le premier écran réservé
  aux admins — jusqu'ici, même la validation des demandes de rôle diffuseur (STR-49) n'était
  exposée que via Swagger/OpenAPI, pas dans l'app. Pose un premier repère de structure pour
  d'éventuels futurs écrans admin.
- **Interruption à chaud d'un live** en cours (modération de contenu, indépendamment du statut
  du compte) reste hors scope : suivi par STR-192.
- Aucune migration DB : `users.is_active` et les `ON DELETE CASCADE` existants suffisent.
