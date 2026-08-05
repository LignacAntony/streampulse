# ADR 028 — Rotation de la clé de diffusion

**Date** : 2026-08-05
**Statut** : Accepté
**Ticket** : [STR-228](https://linear.app/streampulse/issue/STR-228)

---

## Contexte

`stream_key` authentifie l'ingest à elle seule : `POST /api/streams/ingest/{stream_key}` ne
demande aucun JWT (cf. [ADR 015](015-moteur-hls-segmentation-ffmpeg.md)). Quiconque la détient
diffuse à la place du propriétaire.

Elle était générée une fois à la création du flux et ne pouvait plus changer. En cas de fuite —
capture d'écran, presse-papier Android lisible par d'autres applications, partage d'écran pendant
une démo — le seul recours était de supprimer le flux et d'en recréer un, ce qui lui faisait
perdre son identifiant, ses favoris et son historique. La limite était documentée dans
l'[ADR 024](024-tableau-de-bord-diffuseur-lancer-et-arreter-un-flux.md) § 6.

## Décision

### 1. `POST /api/streams/{id}/key/rotate`, et non `/{id}/rotate-key`

Le chemin porte un segment de plus que le nom qui vient naturellement, pour une raison
structurelle : `POST /api/streams/{id}/rotate-key` et `POST /api/streams/ingest/{stream_key}`
comptent quatre segments chacun, et `/api/streams/ingest/rotate-key` matche les deux sans qu'aucun
ne soit plus spécifique. Le `ServeMux` de Go refuse alors d'enregistrer les patterns — le serveur
panique au démarrage.

C'est le même écueil qui avait imposé `PUT` aux favoris (ADR 013). Départager par la longueur du
chemin plutôt que par la méthode HTTP présente deux avantages : `POST` reste le verbe correct
(chaque appel frappe une clé neuve, rien d'idempotent), et le contournement ne se recasse pas si
une autre méthode est un jour montée sur `ingest/`.

### 2. Refus pendant le direct, garanti en SQL

Une rotation est rejetée en 409 si le flux est en direct. Ce n'est pas qu'une commodité : au
démarrage d'un direct, `LiveSessions` indexe la session par la clé (`byKey`). Changer la clé en
base sans toucher au registre laisserait l'ancienne router l'ingest et la nouvelle renvoyer 404.

La garde vit dans la clause `WHERE` de la requête (`status <> 'live'`) et pas seulement dans le
service : c'est la base qui arbitre, y compris face à un `start` concurrent. Zéro ligne affectée
est ensuite traduit en 404 ou 409 par `classifyTransitionFailure`, comme les autres transitions —
un flux appartenant à un tiers renvoie 404 pour ne pas divulguer son existence.

### 3. La réponse porte la nouvelle clé

Le corps est un `StreamResponse` complet avec `stream_key` et `stream_source_url`, comme
`start`/`stop`. La clé neuve n'existe nulle part ailleurs : ne pas la rendre obligerait le client
à enchaîner un `GET` juste après l'avoir demandée.

### 4. L'audit traverse une interface, pas un import entre domaines

`audit_logs` appartient au domaine `admin`, seul à posséder les requêtes sqlc de la table. Le
domaine `streaming` déclare une interface étroite `AuditRecorder` (principe I) et `main.go` — le
seul point de composition du projet — lui injecte le repository admin. Aucun SQL dupliqué, aucun
import croisé entre domaines, et le code admin déjà livré n'est pas touché.

L'écriture est **best-effort**, comme côté modération : une rotation est irréversible une fois
faite, l'ancienne clé n'existe plus. Échouer la requête parce que le journal est indisponible ne
la rendrait pas et laisserait l'appelant croire que rien n'a bougé, alors que son encodeur est
déjà cassé. L'échec part dans les logs (`zerolog`), la requête réussit.

Seul l'identifiant public du flux est journalisé — jamais la clé ni l'URL d'ingest (même règle que
`httpjson.LoggablePath`, [ADR 018](018-supervision-admin-des-flux-et-journal-daudit.md)).

### 5. Côté mobile : entrée de menu, confirmation, et une règle visible avant le tap

L'action vit dans le menu contextuel de la tuile, à côté de « Supprimer ». La confirmation dit
l'essentiel : l'ancienne clé cesse immédiatement de fonctionner, et un encodeur externe déjà
configuré doit recevoir la nouvelle URL avant le prochain direct.

L'entrée est **visible mais inerte** sur un flux en direct, avec la raison en clair
(« arrêtez la diffusion ») : la règle se découvre dans le menu plutôt que par un 409 après coup —
même parti pris que le bouton « Démarrer » neutralisé quand un autre flux est déjà live. Elle
disparaît en revanche sur un flux terminé, dont la clé n'est de toute façon plus utilisable et
dont l'URL d'ingest n'est même pas affichée.

`rotateKey` ne déclenche pas de resynchronisation SSE ni de relevé d'audience, contrairement aux
autres mutations : la rotation ne change pas le statut du flux, seule la tuile est réécrite.

## Alternatives écartées

- **Renommer la route en `PUT /{id}/rotate-key`** pour esquiver le conflit par la méthode, comme
  les favoris : `PUT` annonce une idempotence que l'endpoint n'a pas, et le conflit reviendrait à
  la première méthode ajoutée sur `ingest/`.
- **Autoriser la rotation en direct** en réindexant `LiveSessions` à la volée : il faudrait
  basculer l'index sous verrou pendant qu'un push est attaché, et l'ingest en cours casserait
  quand même — le diffuseur devrait relancer son encodeur, donc arrêter son direct.
- **Extraire un package `internal/audit` partagé** : plus propre à terme, mais touche du code
  admin déjà livré et testé pour un besoin que l'interface étroite couvre déjà.
- **Retenter la génération sur collision** de `uq_streams_stream_key` : deux clés de 32 octets
  tirées d'un CSPRNG ne se rencontrent pas, et `CreateStream` ne traite pas ce cas non plus.

## Conséquences

- Une clé fuitée se remplace sans perdre le flux, ses favoris ni son historique.
- Le diffuseur doit reconfigurer son encodeur externe après chaque rotation — d'où l'avertissement
  explicite dans la confirmation.
- Une rotation impose d'arrêter le direct en cours ; c'est le prix du refus documenté en § 2.
- `audit_logs` n'enregistre plus seulement des actions d'administration : `stream.key_rotated`
  porte comme acteur le propriétaire du flux.
