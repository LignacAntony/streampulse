# STR-203 — Recommandation de pistes : guide de défense (oral RNCP)

Ce document explique **le code de la fonctionnalité de recommandation** (US-09-04),
pour pouvoir répondre aux questions du jury. Il va volontairement dans le détail et
définit le vocabulaire (Go, Flutter, SQL) au fur et à mesure.

- Décision d'architecture formelle : [ADR 046](adr/046-recommandation-basee-sur-l-historique-d-ecoute.md)
- Contrat HTTP : `backend/internal/openapi/openapi.yaml` (tag `Recommendation`)

---

## 1. En une phrase

> Quand l'utilisateur écoute une piste, on **enregistre** l'événement ; l'écran
> « Pour toi » lui propose ensuite des pistes qu'il peut lire (**les siennes et les
> pistes publiques des autres**), classées selon ce qu'il écoute le plus (affinité
> par artiste), en mettant en avant celles qu'il n'a pas encore écoutées.

C'est à la fois de la **redécouverte** (ses propres pistes) et de la **découverte**
(les pistes rendues **publiques** par d'autres, STR-248). Une piste **privée** d'un
tiers n'est jamais recommandée (voir §7).

---

## 2. Le flux de bout en bout

```
┌─────────────┐   joue une piste   ┌────────────────────────────┐
│  App mobile │ ─────────────────► │ GET /api/tracks/{id}/stream │  (authentifié)
│ (Flutter)   │                    └────────────┬───────────────┘
└─────────────┘                                 │ succès → on connaît le user + la piste
      ▲                                          ▼
      │                          ┌──────────────────────────────┐
      │                          │ INSERT dans listening_history │  (best-effort)
      │                          └──────────────────────────────┘
      │ ouvre « Pour toi »
      │                          ┌──────────────────────────────┐
      └───── GET /api/recommendations/tracks ──►│ requête SQL de classement │──► liste
                                 └──────────────────────────────┘   + « raison » par piste
```

Deux moments distincts :
1. **La capture** : à chaque lecture, une ligne est ajoutée dans la table
   `listening_history`. C'est le « carburant » de l'algo.
2. **La recommandation** : à l'ouverture de l'écran, une requête SQL lit cet
   historique et rend une liste classée.

---

## 3. Backend (Go)

Le backend suit une **architecture en couches** (Clean Architecture). Chaque
domaine métier est un dossier `internal/<domaine>/` avec trois fichiers :

| Fichier | Rôle | Analogie |
|---|---|---|
| `handler.go` | Traduit HTTP ↔ métier (lit la requête, écrit la réponse JSON) | « le réceptionniste » |
| `service.go` | La logique métier, sans savoir que c'est du HTTP ni du SQL | « le cerveau » |
| `repository.go` | Parle à la base de données (PostgreSQL) | « le magasinier » |

Notre domaine : `backend/internal/recommendation/`.

> **Pourquoi séparer en 3 ?** C'est le **S** de SOLID (Single Responsibility) :
> une raison de changer par fichier. Si demain on change la base de données, seul
> `repository.go` bouge ; le `service.go` (l'algo) ne bouge pas.

### 3.1 Le modèle de données : la table `listening_history`

Fichier : `backend/migrations/000023_create_listening_history.up.sql`

```sql
CREATE TABLE IF NOT EXISTS listening_history (
    id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID        NOT NULL REFERENCES users(id)  ON DELETE CASCADE,
    track_id   UUID        NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
    played_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

- **Une ligne = une écoute** (pas un compteur `nombre_ecoutes`). On garde
  l'horodatage (`played_at`) pour pouvoir plus tard pondérer par la récence, sans
  refaire de migration.
- `REFERENCES ... ON DELETE CASCADE` : si un utilisateur (ou une piste) est
  supprimé, ses lignes d'historique disparaissent automatiquement. Pas de « ligne
  fantôme » qui pointe vers un truc qui n'existe plus.
- **Vocabulaire « migration »** : un fichier SQL versionné qui fait évoluer le
  schéma de la base. Ils s'appliquent dans l'ordre au démarrage de l'API. Le numéro
  (ici `000023`) doit être **unique et jamais réutilisé** (voir §6, piège n°1).

### 3.2 La capture d'écoute (le hook)

On enregistre l'écoute **là où on sert le fichier audio** :
`backend/internal/track/handler.go`, fonction `StreamTrack`.

```go
// L'ouverture a réussi → la piste existe et appartient au demandeur : on peut
// enregistrer l'écoute pour la recommandation (best-effort).
h.recordPlay(r, r.PathValue("id"), userID)
```

Trois subtilités défendables :

1. **« best-effort »** = si l'enregistrement échoue, on **journalise** l'erreur mais
   on ne la fait pas remonter. La lecture de la musique ne doit jamais planter à
   cause d'une statistique. (`recordPlay` avale l'erreur.)

2. **On ne compte qu'une lecture « depuis le début ».** Le lecteur audio demande le
   fichier en plusieurs morceaux (requêtes HTTP `Range`, ex. « donne-moi à partir de
   la seconde 30 » quand on avance dans la piste). Si on comptait chaque morceau, une
   seule écoute vaudrait 10 « écoutes ». On ne compte donc que la requête **sans
   en-tête `Range`** ou qui commence à `bytes=0-` (le tout début).

   ```go
   if rng := r.Header.Get("Range"); rng != "" && !strings.HasPrefix(rng, "bytes=0-") {
       return // c'est un « avance/reprise », pas un nouveau démarrage → on ne compte pas
   }
   ```

3. **Le domaine `track` ne connaît pas le domaine `recommendation`.** Il déclare
   juste une petite interface de ce dont il a besoin :

   ```go
   // Dans track/handler.go
   type PlayRecorder interface {
       RecordPlay(ctx context.Context, userID, trackID string) error
   }
   ```

   > C'est le **I** (Interface Segregation) et le **D** (Dependency Inversion) de
   > SOLID : `track` dépend d'une **abstraction** (`PlayRecorder`), pas du code concret
   > de `recommendation`. C'est le service de reco qui est « branché » dedans au
   > démarrage, dans `cmd/api/main.go` :
   > ```go
   > trackHandler.SetPlayRecorder(recommendationSvc)
   > ```
   > Résultat : si on enlève la reco, `track` continue de compiler et de fonctionner.

### 3.3 L'algorithme : une seule requête SQL

C'est le cœur, et c'est **dans le SQL**, pas dans le Go. Fichier :
`backend/internal/recommendation/queries/recommendation.sql`.

```sql
WITH artist_affinity AS (            -- (1) combien j'ai écouté chaque artiste
    SELECT t.artist AS artist, COUNT(*) AS plays
    FROM listening_history lh
    JOIN tracks t ON t.id = lh.track_id
    WHERE lh.user_id = $user_id AND t.artist IS NOT NULL
    GROUP BY t.artist
),
last_play AS (                       -- (2) quand j'ai écouté chaque piste pour la dernière fois
    SELECT track_id, MAX(played_at) AS last_played_at
    FROM listening_history
    WHERE user_id = $user_id
    GROUP BY track_id
)
SELECT c.id, c.title, c.artist, c.duration_s,
       COALESCE(aa.plays, 0) AS artist_plays,      -- affinité de l'artiste de cette piste
       (lp.track_id IS NULL)  AS never_played,      -- jamais écoutée ?
       (c.user_id <> $user_id) AS from_others       -- piste publique d'un tiers ?
FROM tracks c
LEFT JOIN artist_affinity aa ON aa.artist = c.artist
LEFT JOIN last_play       lp ON lp.track_id = c.id
WHERE c.user_id = $user_id OR c.is_public = true    -- les miennes OU les publiques
ORDER BY
    (lp.track_id IS NULL) DESC,        -- 1. les jamais-écoutées d'abord
    COALESCE(aa.plays, 0) DESC,        -- 2. puis les artistes que j'écoute le plus
    lp.last_played_at ASC NULLS FIRST, -- 3. puis les moins récemment écoutées
    c.created_at DESC                  -- 4. puis les plus récentes
LIMIT $lim;
```

Explication en français :

- **CTE** (`WITH ... AS`) = une « sous-requête nommée », une table temporaire pour
  rendre la requête lisible. Ici deux :
  - `artist_affinity` : pour chaque artiste, **combien de fois je l'ai écouté**.
  - `last_play` : pour chaque piste, **la dernière fois que je l'ai écoutée**.
- `LEFT JOIN` : on part des pistes candidates (`tracks c`) et on y accroche, quand
  ça existe, l'affinité de l'artiste et la dernière écoute. « LEFT » = on garde la
  piste même si elle n'a jamais été écoutée (dans ce cas les colonnes valent `NULL`).
- Le `ORDER BY` est **l'algorithme** : il empile 4 critères de tri, du plus fort au
  plus faible. Une piste jamais écoutée d'un artiste très écouté remonte en tête.
- **`WHERE c.user_id = $user_id OR c.is_public = true`** définit le vivier : **mes**
  pistes (toute visibilité) **plus** les pistes **publiques** des autres (STR-248).
  C'est aussi la sécurité : une piste **privée** d'un tiers n'entre jamais (elle
  serait de toute façon en 404 à la lecture). `from_others` (`c.user_id <> $user_id`)
  sert juste à afficher « Découverte publique » plutôt que « Nouveauté de votre
  bibliothèque ».
- **Le cold-start (aucun historique) est géré sans code spécial** : si je n'ai rien
  écouté, toutes les affinités valent 0 et toutes les pistes sont « jamais
  écoutées », donc le tri retombe sur « les plus récemment ajoutées » (mêlant ma
  biblio et le catalogue public). La liste n'est **jamais vide** dès qu'une piste
  est lisible.

> **Pourquoi l'algo est dans le SQL et pas dans le Go ?** Parce que trier et
> agréger, c'est exactement ce que PostgreSQL fait le mieux et le plus vite (il ne
> ramène que 20 lignes déjà triées, au lieu de charger toute la biblio en mémoire Go
> pour la trier à la main). Le Go se contente d'habiller le résultat.

### 3.4 Le service : la « raison » lisible

`backend/internal/recommendation/service.go` transforme les signaux bruts
(`artist_plays`, `never_played`) en une phrase affichable :

```go
func reasonFor(t ScoredTrack) string {
    if t.ArtistPlays > 0 && t.Artist != nil && *t.Artist != "" {
        return "Parce que vous écoutez souvent " + *t.Artist
    }
    if t.NeverPlayed {
        return "Nouveauté de votre bibliothèque"
    }
    return "À réécouter"
}
```

> Séparation nette : **le SQL décide de l'ordre**, **le service décide du texte**.
> C'est testable indépendamment (voir §5).

### 3.5 sqlc : d'où vient le dossier `db/` ?

Dans `backend/internal/recommendation/db/`, les fichiers `.go` sont **générés
automatiquement** par un outil (`sqlc`) à partir de la requête SQL. On écrit du SQL,
`sqlc` en fait des fonctions Go typées. **On n'édite jamais ce dossier à la main.**
Commande : `cd backend && sqlc generate`.

> À l'oral : « le SQL est la source de vérité, le Go typé est généré → pas de risque
> de faute de frappe entre la requête et le code appelant. »

### 3.6 La route HTTP

Dans `cmd/api/main.go` :

```go
mux.Handle("GET /api/recommendations/tracks", auth.RequireAuth(cfg.JWTSecret,
    http.HandlerFunc(recommendationHandler.Recommend)))
```

`auth.RequireAuth(...)` = il faut un **jeton JWT valide** (être connecté). Le handler
récupère l'identité depuis le jeton, jamais depuis un paramètre d'URL (sécurité).

---

## 4. Mobile (Flutter)

Même philosophie en couches, dans `mobile/lib/features/recommendations/` :

```
recommendations/
├── domain/          ← le « quoi », sans dépendance technique
│   ├── entities/recommended_track.dart        (une piste reco + sa raison)
│   └── repositories/recommendation_repository.dart  (le contrat : "fetch()")
├── data/            ← le « comment » : appeler l'API
│   ├── datasources/recommendation_remote_data_source.dart
│   └── repositories/recommendation_repository_impl.dart
└── presentation/    ← l'écran / l'état
    └── providers/recommendations_controller.dart
```

### 4.1 Récupérer les données (couche data)

`recommendation_remote_data_source.dart` fait l'appel HTTP et transforme le JSON en
objets Dart. **Choix assumé** : on appelle l'API via `Dio` (la librairie HTTP)
**directement**, au lieu du « client généré » utilisé ailleurs.

> **Pourquoi ?** Le projet génère normalement tout un paquet client depuis
> l'OpenAPI. Le régénérer pour **un seul** endpoint bonus créerait un énorme diff de
> code généré pour rien. Même choix (et même justification) que la « sonde de
> manifeste » (ADR 045). La route est **quand même** décrite dans `openapi.yaml`, le
> contrat reste documenté.

### 4.2 L'état de l'écran (le controller)

`recommendations_controller.dart` est un **`ChangeNotifier`** : un objet qui garde
l'état (liste, chargement, erreur) et **prévient l'écran** quand ça change
(`notifyListeners()`), via le package `provider`. C'est le pattern de gestion d'état
standard du projet.

> Vocabulaire : `provider` + `ChangeNotifier` = l'équivalent Flutter d'un « store »
> réactif. L'écran « écoute » le controller et se redessine tout seul.

### 4.3 L'écran « Pour toi »

Ce n'est pas un écran séparé : c'est une **section en tête de l'onglet
Bibliothèque** (`playlists_screen.dart`). Chaque ligne montre le titre + la raison,
et un appui **lance la lecture** de toute la liste recommandée :

```dart
onPlay: () => context.read<PlaylistQueueController>().play(
      tracks: recommendations.items.map((r) => r.track).toList(),
      sourceName: 'Pour toi',
      startIndex: i,
    ),
```

> On **réutilise** le lecteur/la file d'attente déjà existants (`PlaylistQueueController`,
> US-05-04). On n'a pas réinventé la lecture : la reco « pousse » juste une liste de
> pistes dans le lecteur commun. C'est le **O** de SOLID (Open/Closed) : on étend
> sans modifier l'existant.

**Détail à connaître** : la section « Pour toi » n'apparaît que si la bibliothèque
n'est pas vide (les recos étant tes propres pistes, s'il n'y a pas de piste il n'y a
rien à recommander).

---

## 5. Les tests (et pourquoi ils sont crédibles)

| Test | Fichier | Ce qu'il prouve |
|---|---|---|
| Service (Go) | `recommendation/service_test.go` | La « raison » est bien dérivée (affinité, nouveauté, réécoute), la liste vide ne plante pas |
| Handler (Go) | `recommendation/handler_test.go` | L'endpoint renvoie 200 + JSON, 401 sans jeton, 500 en cas d'erreur |
| **Intégration SQL** (Go) | `recommendation/repository_integration_test.go` | La **vraie requête** tourne contre un **vrai PostgreSQL** : le classement, le `NULLS FIRST` et le cast booléen ne se valident qu'avec un vrai moteur |
| Data source (Flutter) | `recommendations/data/.../*_test.dart` | Le JSON est bien décodé, l'erreur réseau devient une exception typée |
| Controller (Flutter) | `recommendations/presentation/*_test.dart` | Les états chargement/erreur/succès |
| Widget (Flutter) | `playlists_screen_test.dart` | La section « Pour toi » s'affiche avec les raisons, et un appui lance la bonne file |

> Point fort à l'oral : **le test d'intégration**. « Je ne me contente pas de tester
> avec de faux objets ; l'algorithme de tri vit dans le SQL, donc je le teste contre
> un vrai PostgreSQL, sinon je ne prouve rien. »

---

## 6. Décisions & compromis (ce que le jury adore)

Le jury RNCP note la **capacité de recul** : savoir dire *pourquoi* et *quelles
limites*. Voici les points à assumer.

1. **Numéro de migration `000023` (et pas `000020`).** La branche `develop` avait
   déjà `000020_create_chat`, `000021_create_chat_global_bans` (feature chat) et
   `000022_tracks_is_public` (visibilité des pistes, STR-248). Un numéro de migration
   est **global et jamais réutilisé** : réutiliser un numéro pris provoquerait une
   collision et une base incohérente au merge. J'ai donc sauté à `000023`.

2. **La reco couvre mes pistes + les pistes publiques des autres** (voir §7). Tant que
   les pistes étaient privées, elle se limitait à ma bibliothèque ; depuis STR-248
   (public/privé + lecture cross-user), le vivier inclut le catalogue public. Une
   piste **privée** d'un tiers reste exclue (elle serait en 404 à la lecture).

3. **Le préchargement gonfle l'historique (limite connue).** Le lecteur natif
   (`just_audio`) **précharge toute la file** : démarrer une file de 5 pistes envoie 5
   requêtes de lecture, donc enregistre 5 « écoutes », pas 1. Côté serveur, un
   préchargement est indistinguable d'une vraie écoute. Acceptable pour une reco
   « simple » (mettre en file traduit un intérêt), documenté dans l'ADR ; la version
   fidèle capturerait côté client au moment où une piste devient *courante* (ticket
   séparé).

4. **Capture « best-effort ».** Une panne de la statistique ne doit jamais casser la
   lecture de musique. La lecture prime sur l'historique.

5. **Algorithme dans le SQL, pas dans le Go.** Performance + lisibilité + un seul
   aller-retour base de données.

---

## 7. La question qui va tomber : « et la musique des autres ? »

**Réponse courte :** oui, on recommande aussi la musique des autres, **à condition
qu'elle soit publique**. Depuis STR-248, une piste porte un drapeau `is_public`, et
l'endpoint de lecture `GET /api/tracks/{id}/stream` autorise la lecture d'une piste
**si elle est à moi OU publique** (requête `GetTrackFileForStream`). La reco reprend
exactement ce périmètre : son vivier = mes pistes (toute visibilité) **+** les pistes
publiques de tout le monde. Une piste **privée** d'un tiers reste hors reco (elle
renverrait 404 à la lecture).

**Concrètement dans la requête** : le filtre est `WHERE c.user_id = $moi OR
c.is_public = true`. Le drapeau `from_others` (`c.user_id <> $moi`) sert seulement à
choisir la phrase affichée : « Découverte publique » pour une piste publique d'un
tiers, « Nouveauté de votre bibliothèque » pour une des miennes.

**Ce que ça donne** : de la **redécouverte** (mes propres titres) *et* de la
**découverte** (les artistes que j'écoute, retrouvés dans le catalogue public
d'autres utilisateurs). L'algorithme de classement (affinité par artiste) n'a pas
changé, seul le vivier s'est élargi.

> Historique : au premier jet (avant le rebase sur STR-248), les pistes étaient
> toutes privées, donc la reco se limitait à ma bibliothèque. C'est le rebase sur la
> feature public/privé qui a permis d'ouvrir le vivier — un bon exemple à l'oral de
> feature qui débloque une autre.

---

## 8. Glossaire express

| Terme | Définition simple |
|---|---|
| **Migration** | Fichier SQL versionné qui fait évoluer le schéma de la base, appliqué au démarrage |
| **CTE** (`WITH`) | Sous-requête nommée, une table temporaire pour rendre le SQL lisible |
| **LEFT JOIN** | Garde toutes les lignes de gauche même sans correspondance à droite (valeurs `NULL`) |
| **sqlc** | Outil qui génère du code Go typé à partir de requêtes SQL (dossier `db/`, jamais édité à la main) |
| **JWT** | Jeton d'authentification signé ; prouve qui est connecté sans stocker de session serveur |
| **best-effort** | On essaie, mais un échec est toléré (journalisé) et ne casse pas le reste |
| **ISP / DIP** (SOLID) | Dépendre de petites **interfaces** abstraites, pas de code concret → modules découplés |
| **ChangeNotifier / provider** | Gestion d'état réactive côté Flutter : l'état prévient l'UI qui se redessine |
| **Dio** | La librairie HTTP côté Flutter (équivalent d'axios/fetch) |
| **cold-start** | Cas « pas encore de données » (ici : aucun historique) qu'il faut gérer proprement |

---

## 9. Fichiers clés (pour naviguer vite)

- Migration : `backend/migrations/000023_create_listening_history.up.sql`
- Requête SQL (l'algo) : `backend/internal/recommendation/queries/recommendation.sql`
- Service (la raison) : `backend/internal/recommendation/service.go`
- Capture d'écoute : `backend/internal/track/handler.go` (`StreamTrack`, `recordPlay`)
- Câblage : `backend/cmd/api/main.go` (`SetPlayRecorder`, route)
- Écran mobile : `mobile/lib/features/playlists/presentation/screens/playlists_screen.dart` (section « Pour toi »)
- Data mobile : `mobile/lib/features/recommendations/data/datasources/recommendation_remote_data_source.dart`
- Décision : `docs/adr/046-recommandation-basee-sur-l-historique-d-ecoute.md`
