# ADR 029 — Pistes d'une playlist : ajout, retrait et réordonnancement

**Date** : 2026-08-05
**Statut** : Accepté
**Ticket** : [STR-132](https://linear.app/streampulse/issue/STR-132) (US-05-03)

---

## Contexte

US-05-03 : l'utilisateur doit pouvoir **ajouter, retirer et réordonner** (drag-and-drop) les pistes
d'une de ses playlists, la modification étant persistée et l'ordre affiché reflétant l'ordre stocké.

Le domaine `internal/playlist/` existe déjà ([ADR 026](026-domaine-playlists.md)) mais ne sait que
**lire** les pistes (`GET /api/playlists/{id}/tracks`). La table `playlist_tracks(playlist_id,
track_id, position, added_at)` porte déjà une `position INTEGER CHECK (position >= 0)` et une PK
`(playlist_id, track_id)` (migration `000004`), sans contrainte sur l'unicité de la position.

Ce document consigne les décisions qui **ne se déduisent pas du code**.

---

## Décision

### 1. Le réordonnancement est un **remplacement total** de l'ordre (`PUT .../tracks`)

Le client envoie la **liste complète** des `track_ids` dans l'ordre voulu (index 0 = première
piste), pas une opération `{from, to}`. Raisons :

- Le drag-and-drop Flutter (`ReorderableListView`) produit déjà une liste réordonnée : l'envoyer
  telle quelle évite de reconstruire un delta côté client.
- Une suite d'opérations `move` demanderait un verrouillage ou un numéro de version pour rester
  cohérente entre deux clients ; l'ordre complet **est** l'état, il est idempotent et rejouable.
- Le serveur peut vérifier que l'ordre reçu **couvre exactement** la playlist (cf. décision 3),
  contrôle impossible avec un delta.

Le prix assumé : une playlist de 1000 pistes envoie 1000 UUID (~37 Ko). Plafond explicite
`MaxTracksPerPlaylist = 1000`, appliqué **des deux côtés** : le service rejette un ordre plus long
(400), et l'ajout refuse d'insérer au-delà (409). Ne plafonner que le réordonnancement rendrait
une playlist de plus de 1000 pistes **impossible à réordonner** — chaque PUT porte la liste
complète et serait rejeté (revue de la PR #280).

### 2. Contrainte d'unicité `(playlist_id, position)` **DEFERRABLE INITIALLY DEFERRED**

Migration `000019`. Sans contrainte, rien n'empêchait deux pistes de partager une position et
l'ordre affiché devenait non déterministe. Mais une contrainte **immédiate** rendrait tout
réordonnancement impossible en un seul `UPDATE` : les états intermédiaires contiennent forcément
des doublons (déplacer la piste 3 en position 0 avant d'avoir décalé les autres). `DEFERRABLE
INITIALLY DEFERRED` fait vérifier la contrainte au **COMMIT** : les états intermédiaires de la
transaction sont libres, l'état final est garanti unique.

Conséquence pratique : les mutations de pistes passent **toutes** par `inTx` (repository), et une
violation remonte au `tx.Commit`, pas à l'`UPDATE` — c'est là qu'elle est traduite en 409.

**Deux pièges rencontrés en QA, à connaître avant de toucher à `playlist_tracks` :**

1. Une contrainte différée **ne peut pas servir d'arbitre à `ON CONFLICT`** (SQLSTATE 55000).
   Un `ON CONFLICT DO NOTHING` **sans colonnes** oblige Postgres à considérer toutes les
   contraintes uniques de la table comme arbitres possibles : il échoue donc dès que l'une d'elles
   est différée. Tout `INSERT … ON CONFLICT` sur `playlist_tracks` doit **nommer explicitement**
   `(playlist_id, track_id)`. Le seeder a été corrigé en ce sens.
2. Le seed ne repeuple la playlist de démo **que si elle est vide**. Ré-insérer les positions
   0..2 à chaque démarrage écraserait l'ordre choisi par l'utilisateur, et — une piste ayant pu
   être retirée entre-temps — réattribuerait une position déjà prise : violation au COMMIT et API
   en crash loop au boot. La contrainte a fait son travail en révélant un seed qui réécrivait des
   données utilisateur.

### 3. L'ordre fourni doit couvrir **exactement** la playlist → sinon **409**

Le repository compte les pistes de la playlist, compare à la taille de la liste reçue, exécute
l'`UPDATE` et vérifie que le nombre de lignes touchées vaut ce même total. Un identifiant étranger
à la playlist n'en touche aucune, une liste partielle en laisse de côté : les deux cas renvoient
**409 Conflict** (« l'ordre fourni ne correspond plus à la playlist »), qui décrit exactement la
situation réelle — le client a réordonné une vue périmée (piste ajoutée ou retirée ailleurs). Les
doublons dans la liste sont, eux, une **erreur de forme** détectée par le service → 400.

### 4. Retrait → **recompactage des positions** dans la même transaction

Retirer la piste en position 1 sur 3 laisserait `0, 2`. Les positions sont recompactées en `0..n-1`
(`ROW_NUMBER() OVER (ORDER BY position)`) **dans la transaction du DELETE**. Sans cela, le
réordonnancement suivant partirait d'index troués et l'invariant « position = index d'affichage »
serait faux. Le `WHERE pt.position <> ranked.rn - 1` évite de réécrire les lignes déjà à leur place.

### 5. L'ajout se fait **en fin de playlist**, réservé aux pistes du demandeur

`POST .../tracks` insère avec `position = COALESCE(MAX(position) + 1, 0)`. L'INSERT sélectionne sa
source dans `tracks` filtrée sur `user_id` : une piste inconnue **ou appartenant à un tiers** ne
produit aucune ligne → **404**, jamais 403 (même règle de non-divulgation que l'ADR 026 §1). Une
piste déjà présente viole la PK `(playlist_id, track_id)` → `23505` → **409** ; on ne fait pas de
`SELECT` préalable (course entre deux requêtes concurrentes), même logique que l'ADR 026 §3.

**Course sur la position, rejouée plutôt que remontée.** Deux ajouts simultanés sur la même
playlist lisent le même `MAX(position)` et visent la même position ; le perdant échoue au COMMIT
sur la contrainte différée. Lui renvoyer un 409 serait inutile — il n'a rien à corriger — donc
l'insertion est **rejouée une fois** (`addTrackAttempts`), le second essai relisant un maximum à
jour. Le repository distingue les deux familles de conflit par l'endroit où elles surviennent :
la PK est immédiate (elle lève à l'INSERT → « déjà dans la playlist »), la contrainte de position
est différée (elle lève au COMMIT → sentinelle `errPositionTaken`, rejouée par l'ajout, traduite
en « l'ordre ne correspond plus » par le réordonnancement).

### 6. Ajout et réordonnancement **renvoient la liste des pistes**, pas 204

`POST` (201) et `PUT` (200) renvoient l'ordre persisté. Le client applique un rendu optimiste
pendant le drag ; la réponse lui donne la **vérité serveur** sans second aller-retour, ce qui rend
la resynchronisation après conflit immédiate. Le `DELETE` reste en 204 (l'écran retire la ligne
localement, et l'ordre relatif du reste est inchangé).

### 7. `GET /api/tracks` (bibliothèque du demandeur) vit **dans le domaine playlist**

Le sélecteur « ajouter une piste » a besoin de la liste des pistes de l'utilisateur. US-05-01
(upload d'une piste, [STR-130](https://linear.app/streampulse/issue/STR-130)) **n'est pas encore
livrée** : il n'existe donc ni domaine `internal/track/`, ni moyen de créer une piste hors du
seeder. Plutôt que de créer un domaine anémique d'une seule requête, cette lecture est portée par
le domaine playlist, dont elle est aujourd'hui l'unique consommateur.

**Dette explicite** : quand US-05-01 arrivera avec l'upload, `GET /api/tracks` devra **déménager**
vers le domaine `track` (avec `POST /api/tracks`), sa réponse restant inchangée pour le client.

### 8. Côté Flutter : ordre optimiste + **rollback** sur échec

`PlaylistDetailController.reorder` applique le nouvel ordre en mémoire **avant** l'appel réseau
(le doigt de l'utilisateur a déjà déplacé la ligne, une latence rendrait le geste saccadé), puis
remplace la liste par la réponse serveur. En cas d'erreur, l'ordre **précédent est restauré** et un
toast l'annonce : ne pas revenir en arrière laisserait l'écran afficher un ordre qui n'existe pas
en base. Même schéma pour le retrait.

### 9. Confirmation avant de retirer une piste

Le retrait passe par un dialogue de confirmation, comme la suppression d'une playlist
([ADR 026](026-domaine-playlists.md)). Le libellé dit ce qui se passe réellement — « la piste reste
dans ta bibliothèque, mais sa place dans la playlist est perdue » — et non « action définitive » :
la piste n'est pas détruite, mais la ré-ajouter la remet **en fin de liste**, sa position n'est pas
récupérable. Sur une playlist longue réordonnée à la main, un tap accidentel coûte donc cher, et
les deux boutons « retirer » et « poignée de drag » sont voisins sur la ligne.

Une action « annuler » dans le toast aurait été moins intrusive mais demande deux appels pour
restaurer la position (`POST` puis `PUT` de l'ordre) ; le dialogue a été retenu pour la cohérence
avec le reste de l'écran Bibliothèque.

### 10. La file d'attente (queue) reste **hors périmètre**

Le critère d'acceptation mentionne la mise à jour de la queue. La lecture d'une playlist avec file
d'attente est [STR-133](https://linear.app/streampulse/issue/STR-133) (US-05-04), **bloquée par**
celle-ci : aucun lecteur ne consomme encore l’ordre d’une playlist. L'invariant livré ici — les
positions sont contiguës et `GET .../tracks` les renvoie triées — est exactement le contrat sur
lequel US-05-04 construira la queue.

---

## Conséquences

- **Positif** : ordre garanti unique et contigu au niveau **base** (pas seulement applicatif) ;
  réordonnancement atomique en une transaction ; contrat OpenAPI complet + client Dart régénéré ;
  isolation propriétaire testée (404 sur playlist et sur piste d'un tiers).
- **Dette assumée** : `GET /api/tracks` à déménager vers le domaine `track` à l'arrivée d'US-05-01
  (décision 7) ; pas de pagination sur cette liste (même raisonnement que l'ADR 026 §5) ; le corps
  du `PUT` grossit avec la playlist (décision 1).
- **Non traité** : queue de lecture (US-05-04), ajout d'une piste à plusieurs playlists en une
  requête, insertion à une position choisie (l'ajout est toujours en fin, un drag suffit ensuite).
