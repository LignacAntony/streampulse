# ADR 039 — Supervision admin des flux actifs et journal d'audit

> **Renumérotée (STR-237)** : cette ADR portait le numéro **018**, déjà attribué à
> [ADR 018 — Logs structurés JSON (zerolog)](018-logs-structures-zerolog-collecte-loki-alloy.md).

**Date** : 2026-07-21
**Statut** : Accepté
**Ticket** : [STR-192](https://linear.app/streampulse/issue/STR-192) (sous-issues [STR-197](https://linear.app/streampulse/issue/STR-197), [STR-198](https://linear.app/streampulse/issue/STR-198), [STR-199](https://linear.app/streampulse/issue/STR-199))

---

## Contexte

US-08-02 : le tableau de bord admin ([ADR 017](017-tableau-de-bord-admin-gestion-utilisateurs.md),
STR-191) couvre la gestion des **comptes** (recherche, activation/désactivation, suppression) mais
excluait explicitement la modération d'un **live en cours** — l'ADR 017 le renvoyait nommément à
STR-192 :

> Interruption à chaud d'un live en cours (modération de contenu, indépendamment du statut du
> compte) reste hors scope : suivi par STR-192.

STR-192 comble ce trou : un administrateur doit pouvoir voir tous les flux actuellement en direct
(publics et privés — la modération de contenu ne s'arrête pas à la frontière de visibilité) et
interrompre immédiatement l'un d'eux, sans attendre que le diffuseur l'arrête lui-même ni passer
par la suspension de son compte. Contrairement à `LiveStopper` (ADR 017 §2, qui coupe *tous* les
lives d'un utilisateur au moment d'un hard delete), il s'agit ici de cibler **un flux précis**,
choisi dans une liste de modération, indépendamment de toute action sur le compte.

## Décision

### 1. Deux nouveaux endpoints, réutilisant le domaine `internal/admin/`

| Méthode | Route | Rôle requis |
|---|---|---|
| GET | `/api/admin/streams` | admin |
| POST | `/api/admin/streams/{id}/stop` | admin |

Pas de nouveau domaine : ces routes rejoignent `internal/admin/` (handler/service/repository déjà
en place depuis STR-191), avec leurs propres méthodes (`ListLiveStreams`, `StopStream`) et leur
propre requête sqlc (`queries/admin.sql`).

### 2. `POST .../stop`, pas le `DELETE` du libellé initial

Le libellé de STR-197 évoquait un `DELETE`. Écart assumé et documenté : **`POST
/api/admin/streams/{id}/stop`** a été retenu à la place, pour deux raisons.

- **Sémantique** : l'action est une **transition d'état** (`live → ended`, exactement le même
  statut qu'un arrêt volontaire via `PATCH .../stop` côté diffuseur, [ADR 013](013-domaine-streaming.md)),
  pas une suppression de ressource. Le flux, son historique et ses métadonnées survivent intacts.
- **Collision de nom** : `DELETE /api/streams/{id}` existe déjà et signifie *tout autre chose* — le
  soft delete du diffuseur propriétaire (`archived_at`, [ADR 013](013-domaine-streaming.md)/[ADR 015](015-moteur-hls-segmentation-ffmpeg.md)).
  Réutiliser le même verbe sur une route différente pour une opération différente (transition vs
  archivage) aurait été trompeur pour quiconque lit la spec OpenAPI.

### 3. Stop simple, sans verrou anti-redémarrage

`ForceStopStream` (`streaming.Service`, `backend/internal/streaming/service.go`) fait exactement ce
que fait un arrêt volontaire, sans contrôle de propriétaire : transition `live → ended` en base
(`ForceStopLiveStream`, `WHERE status = 'live' AND archived_at IS NULL`, sans filtre `user_id`),
puis `sessions.Stop(id)` — ffmpeg tué, répertoire de segments nettoyé, événement SSE `"ended"`
publié à tous les auditeurs abonnés (`GET /api/streams/{id}/events`). 404 si le flux est absent ou
archivé, 409 s'il existe mais n'est pas en direct (mêmes codes que `PATCH .../stop` côté diffuseur).

**Volontairement absent : un verrou empêchant le diffuseur de relancer un nouveau live juste
après.** Un modérateur qui interrompt un flux n'empêche pas techniquement son propriétaire de
`POST /api/streams` + `PATCH .../start` à nouveau la seconde suivante. C'est un choix de **portée**,
pas un oubli : bannir un compte ou verrouiller sa capacité à rediffuser est une décision de
modération distincte, plus lourde de conséquences (elle doit sans doute être visible du diffuseur,
motivée, peut-être temporaire) — suivie par **STR-209**, hors scope ici. STR-192 ne traite que
« couper le direct maintenant », pas « empêcher qu'il reprenne ».

### 4. Journal d'audit générique (`audit_logs`, migration `000017`)

```sql
CREATE TABLE IF NOT EXISTS audit_logs (
    id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id    UUID        REFERENCES users(id) ON DELETE SET NULL,
    action      TEXT        NOT NULL,
    target_type TEXT        NOT NULL,
    target_id   UUID        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

- **Forme générique** (`action`/`target_type`/`target_id` en texte libre, pas de colonnes dédiées
  à `stream`) : une seule action y est écrite aujourd'hui (`stream.stopped`), mais la table couvre
  sans nouvelle migration toute future action admin qu'on voudrait tracer (désactivation de compte,
  approbation de demande diffuseur, etc.) — cf. commentaire de la migration.
- **`actor_id` en `ON DELETE SET NULL`, pas `CASCADE`** : si l'admin qui a interrompu un flux est
  lui-même supprimé plus tard (hard delete, ADR 017), la ligne d'audit doit **survivre** — c'est la
  trace de l'action, pas une propriété de l'admin. `CASCADE` l'aurait effacée avec son auteur, ce
  qui aurait vidé le journal exactement quand il devient le plus utile à relire (un admin supprimé
  pour abus de ses propres droits, par exemple).
- Un seul index, sur `created_at DESC` (`idx_audit_logs_created_at`) : la seule lecture anticipée
  aujourd'hui est chronologique (pas d'écran de consultation dans ce ticket — la table existe pour
  tracer, pas encore pour être explorée depuis l'app).

### 5. Audit best-effort, après le stop, jamais avant

```go
// internal/admin/service.go
func (s *Service) StopStream(ctx context.Context, streamID, actorID string) error {
    if err := s.moderator.ForceStopStream(ctx, streamID); err != nil {
        return err
    }
    if err := s.repo.InsertAuditLog(ctx, actorID, "stream.stopped", "stream", streamID); err != nil {
        log.Printf("admin: audit stream.stopped %s par %s non journalisé: %v", streamID, actorID, err)
    }
    return nil
}
```

L'interruption du flux est l'action critique du point de vue produit (protéger les auditeurs ou la
plateforme d'un contenu problématique, *maintenant*) ; l'écriture de l'audit est une conséquence
secondaire. Si `InsertAuditLog` échoue (panne DB transitoire, par exemple), la requête HTTP renvoie
quand même `204` — l'admin ne doit jamais recevoir une erreur pour un stop qui a réellement eu
lieu — et l'échec est loggé côté serveur (`log.Printf`) pour investigation. Aucune transaction ne
lie les deux écritures (cf. Alternatives écartées).

### 6. Liste de modération : tous les live, sans compteur d'auditeurs

`GET /api/admin/streams` (`ListLiveStreams` → `AdminListLiveStreams`) renvoie **tous** les flux
`status = 'live'` non archivés, **publics et privés**, avec l'identité du diffuseur (jointure
`users` → `username`) — contrairement à `GET /api/streams` (découverte invité), aucun filtre de
visibilité ni de propriétaire ne s'applique : un modérateur doit voir un live privé tout autant
qu'un public. Secrets (`stream_key`, `stream_source_url`) absents de `AdminStream` : un modérateur
n'a jamais besoin de pousser de l'audio sur le flux de quelqu'un d'autre.

**`COUNT(*)` séparé** (`AdminCountLiveStreams`), pas `COUNT(*) OVER()` porté par les lignes de
`AdminListLiveStreams` — leçon directement reprise de la revue de l'ADR 017 (fix #2, PR #264) :
un `OVER()` sur une page vide (offset au-delà du nombre de lives) aurait renvoyé `total=0` au lieu
du vrai total.

**Pas de compteur d'auditeurs en temps réel** sur cette liste. Le produit permettrait à un
modérateur d'évaluer l'urgence (« 200 auditeurs sur ce flux » pèserait plus qu'« 3 »), mais aucune
mesure de ce type n'existe aujourd'hui dans le moteur HLS ([ADR 015](015-moteur-hls-segmentation-ffmpeg.md)) :
les segments sont servis sans session auditeur trackée. Suivi par **STR-184**, hors scope ici.

### 7. `StreamModerator`, interface ISP — même schéma que `LiveStopper`

```go
// internal/admin/service.go
type StreamModerator interface {
    ForceStopStream(ctx context.Context, streamID string) error
}
```

Implémentée par `streaming.Service`, injectée dans `admin.NewService(adminRepo, streamingSvc,
streamingSvc)` aux côtés de `LiveStopper` (ADR 017 §2) — même logique ISP : le service admin ne
dépend que de la méthode exacte dont il a besoin, pas de `streaming.Service` dans son ensemble.
Assertion de compatibilité côté `main.go` : `var _ admin.StreamModerator =
(*streaming.Service)(nil)`.

### 8. Mobile : deuxième tuile sur `_AdminCard`, pas un nouvel accès

`_AdminCard` (`ProfileScreen`, introduite par l'ADR 017) passe d'une tuile à deux : « Gestion des
utilisateurs » (existante) et « Supervision des flux » (nouvelle, `AdminStreamsScreen`). Pas de
nouveau point d'entrée dans l'app — même porte d'accès réservée aux admins, même garde
(`profile.role == 'admin'`). Côté données, `AdminStreamsScreen` reprend telles quelles les leçons
de la revue STR-191/PR #264 : `COUNT` séparé déjà couvert côté backend (§6), la mutation `stop`
renvoie un booléen (pas de toast de succès trompeur sur un no-op — flux déjà retiré de la liste par
un autre admin entre-temps), un toast d'erreur dédié sur l'échec de `loadMore`, et une icône
d'erreur qui distingue panne réseau (`wifi_off_outlined`) d'erreur serveur (`error_outline`).

## Alternatives écartées

### `DELETE /api/admin/streams/{id}` (libellé initial de STR-197)

Alignerait le nom de méthode sur le verbe HTTP le plus intuitivement associé à « faire cesser
quelque chose ». **Écarté** (cf. §2) : collision sémantique avec le `DELETE /api/streams/{id}`
existant (soft delete du diffuseur), qui aurait rendu la spec OpenAPI ambiguë sur ce que `DELETE`
signifie selon la route. `POST .../stop` documente sans ambiguïté une transition d'état, symétrique
au `PATCH .../stop` du diffuseur.

### Verrou de modération (empêcher un redémarrage après stop)

Empêcherait un diffuseur sanctionné de relancer immédiatement le même contenu. **Écarté** (cf.
§3) : nécessite de décider *où* vit ce verrou (compte ? flux ? durée ?), qui recoupe directement le
futur mécanisme de bannissement (STR-209) — l'anticiper ici risquerait de construire la mauvaise
forme avant que STR-209 ne précise les besoins réels (durée, notification au diffuseur, recours).
STR-192 reste volontairement limité à l'interruption immédiate.

### Table dédiée `stream_interruptions`

Colonnes typées (`stream_id`, `moderator_id`, `stopped_at`, …) plutôt qu'un schéma générique.
**Écarté** : une seule action est journalisée aujourd'hui ; une table dédiée à cette unique action
aurait dû être renommée ou dupliquée dès la première action admin non liée aux flux à journaliser
(désactivation de compte, par exemple). La forme générique `audit_logs` (§4) coûte à peine plus cher
à écrire et couvre déjà ce cas futur.

### Transaction unique stop + audit (cross-domaine)

Garantirait qu'un audit est *toujours* écrit si le stop réussit. **Écarté** : `ForceStopStream`
(domaine streaming) et `InsertAuditLog` (domaine admin) ne partagent aujourd'hui aucune connexion ni
`pgx.Tx` commune — les fiabiliser dans une seule transaction cross-domaine casserait la séparation
`internal/streaming` / `internal/admin` (ISP, §7) pour un bénéfice marginal : l'audit est une
trace secondaire (§5), pas une contrainte d'intégrité métier. Le best-effort loggé est jugé
suffisant à l'échelle actuelle ; réévaluable si un audit manquant devient un problème opérationnel
concret.

### Compteur d'auditeurs en temps réel sur la liste de modération

Donnerait à l'admin un signal de priorité entre plusieurs lives à modérer. **Écarté** (cf. §6) :
aucune infrastructure de comptage d'auditeurs n'existe dans le moteur HLS actuel ; l'ajouter
uniquement pour cet écran aurait anticipé un besoin plus large (STR-184) sans le cadrage qu'il
mérite (comptage exact ? approximatif ? par segment servi ?).

## Conséquences

- **Nouvelle table + index** (`audit_logs`, migration `000017`) : aucune donnée existante affectée,
  pas de backfill nécessaire (aucune action passée à tracer rétroactivement).
- **Le diffuseur voit son flux passer à `ended`** exactement comme s'il l'avait arrêté lui-même
  (événement SSE `"ended"` sur `GET /api/streams/{id}/events`) et **peut techniquement relancer un
  direct** juste après (§3) — assumé jusqu'à STR-209.
- **L'audit n'est pas garanti** si l'insertion échoue : une panne DB transitoire au mauvais moment
  laisse un stop réel sans trace, visible uniquement dans les logs serveur (`log.Printf`), pas en
  base. Acceptable à ce stade (§5) ; à surveiller si l'audit devient un besoin de conformité fort.
- **La trace d'audit est conservée après suppression de son auteur** (`actor_id` `SET NULL`) : une
  ligne `audit_logs` peut donc pointer vers un admin qui n'existe plus — à garder en tête pour tout
  futur écran de consultation du journal (afficher un placeholder du type « admin supprimé »).
- **Nouveaux codes d'erreur client** sur `POST /api/admin/streams/{id}/stop` : `404` (flux absent
  ou déjà archivé) et `409` (flux existant mais pas en direct — déjà arrêté, notamment par un autre
  admin en parallèle). L'écran mobile les distingue déjà (`ConflictException` dédiée, §8).
- **Pas de compteur d'auditeurs** sur cette liste ni ailleurs dans l'app : reste entièrement à
  construire si STR-184 est repris.
