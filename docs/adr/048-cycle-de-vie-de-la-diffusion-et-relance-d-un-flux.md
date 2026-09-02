# ADR 048 — Cycle de vie de la diffusion : suspendre plutôt qu'arrêter, et relancer un flux terminé

**Date** : 2026-09-02
**Statut** : Accepté
**Ticket** : STR-XXX

## Contexte

Trois symptômes rapportés sur la diffusion, qui n'en font qu'un une fois déroulés.

**1. Le direct se coupe quand le diffuseur change d'onglet.** `DashboardScreen`
terminait le direct **côté serveur** dès que l'application n'était plus au premier
plan :

```dart
if (state == AppLifecycleState.paused ||
    state == AppLifecycleState.hidden ||     // ← le coupable
    state == AppLifecycleState.detached) {
  unawaited(notifier.stopForBackground());   // → PATCH /api/streams/{id}/stop
}
```

`AppLifecycleState.hidden` n'est pas un passage en arrière-plan. La documentation
Flutter le définit comme « toutes les vues sont masquées » — ce qui, **sur le web**,
inclut un simple changement d'onglet navigateur. Sur iOS et Android il précède
toujours `paused`, donc il n'apportait rien là où il était censé servir, et il
tuait le direct là où il n'aurait rien dû faire.

**2. Au retour, le direct repart du début.** Conséquence mécanique du point 1 :
`stop` détruit la session, `start` en refabrique une. Or chaque session crée un
segmenteur ffmpeg neuf, dans un `os.MkdirTemp` neuf. Mesuré sur la stack locale,
en sondant le manifeste toutes les 5 s pendant un push AAC temps réel :

```
t= 15s  200  MEDIA-SEQUENCE:0  n=1  first=seg_00000
t= 60s  200  MEDIA-SEQUENCE:0  n=6  first=seg_00000
t= 90s  200  MEDIA-SEQUENCE:3  n=6  first=seg_00003
t=150s  200  MEDIA-SEQUENCE:9  n=6  first=seg_00009
```

La numérotation et `EXT-X-MEDIA-SEQUENCE` repartent de zéro à chaque session. Pour
le lecteur de l'auditeur, c'est un manifeste réinitialisé : il recommence au premier
segment. D'où la boucle observée — un bout de son, une attente, le même bout de son.

**3. Un flux terminé était mort pour de bon.** La transition SQL était
`idle → live` seule :

```sql
WHERE ... AND s.status = 'idle'
```

Donc `start` sur un flux `ended` renvoyait `409 stream is not idle`, sans recours.
Le tableau de bord en avait tiré les conséquences : ni bouton, ni URL d'ingest, ni
rotation de clé sur une tuile terminée, et le message « Créez un nouveau flux pour
rediffuser ». Combiné au point 1, un simple changement d'onglet condamnait le flux :
il fallait en recréer un et rediffuser une clé neuve.

Le bail d'ingest existait pourtant déjà pour ce cas exact :
`INGEST_RECONNECT_GRACE_SECONDS` (45 s) termine un direct que plus personne
n'alimente. `stopForBackground` court-circuitait ce garde-fou au lieu de s'y
reposer.

## Décision

### 1. L'arrière-plan **suspend** la capture, il ne termine plus le direct

`hidden` ne déclenche plus rien. `paused` et `detached` relâchent le microphone —
obligatoire sur iOS — mais laissent la session serveur vivante.

C'est le **bail d'ingest du backend qui arbitre** : un aller-retour court reprend
là où il s'était arrêté, une absence de plus de 45 s termine le direct comme avant.

L'invariant de l'[ADR 027](027-capture-microphone-et-push-aac-mobile.md) — « jamais
de live silencieux » — tient toujours, mais il est désormais tenu par le serveur,
qui est le seul à pouvoir l'observer, plutôt que par un arrêt préventif du client.
L'ADR 027 reste en vigueur sur tout le reste (encodage AAC/ADTS, permissions,
reprise réseau) ; seule sa politique d'arrière-plan est révisée ici.

### 2. La reprise réutilise la session existante

`BroadcastSessionController` mémorise l'URL d'ingest du direct en cours et, au
retour au premier plan :

1. resynchronise l'état serveur (`refresh()`) — c'est la seule façon de savoir si
   le bail a tenu ;
2. relance le **push** sur la même URL si le flux est toujours `live`.

Aucun second `start` : le segmenteur, son répertoire et sa numérotation sont
conservés, et `-hls_flags append_list` fait le reste. L'auditeur ne voit qu'un trou
dans l'arrivée des segments, pas un manifeste réinitialisé.

L'issue est explicite (`BroadcastResumeOutcome`) : `resumed`, `sessionLost` (le bail
a expiré), `microphoneUnavailable` (permission révoquée pendant l'absence),
`nothingToResume`. L'écran ne commente que ce qui apprend quelque chose — une
reprise réussie se voit déjà sur la tuile.

### 3. Un flux terminé est relançable

```sql
SET status = 'live', started_at = NOW(), ended_at = NULL, updated_at = NOW()
WHERE ... AND s.status IN ('idle', 'ended')
```

Un flux porte un titre, une description et une clé d'ingest : c'est un **canal
réutilisable**, pas un enregistrement à usage unique. Seul un flux déjà `live`
refuse désormais la transition — le message du 409 devient
`stream is already live`.

`ended_at` repart à `NULL` : la colonne décrit la fin du direct *courant*. La
laisser garnie ferait cohabiter `status = 'live'` et une date de fin, contradiction
que ni l'API ni les tuiles ne savent présenter.

La règle « un seul live par diffuseur » reste garantie atomiquement par l'index
partiel unique `streams_one_live_per_user` (migration `000016`) : rien à changer,
et aucune migration n'est nécessaire.

Côté mobile, `BroadcastStream.canStart` (`!isLive`) remplace les `isIdle` semés dans
l'écran, et la tuile d'un flux terminé retrouve son bouton (« Relancer la
diffusion »), son URL d'ingest et sa rotation de clé.

## Conséquences

- Un direct survit à un changement d'onglet web et à un aller-retour mobile de
  moins de 45 s, **sans coupure pour l'auditeur** au-delà du trou d'alimentation.
- Un flux peut rester `live` jusqu'à 45 s sans que personne ne pousse d'audio. Ce
  n'était déjà pas nouveau (c'est la définition même du bail), mais c'est désormais
  un état atteint volontairement, pas seulement par accident réseau.
- Les auditeurs d'un direct suspendu voient leur lecture se figer puis reprendre.
  Le lecteur mobile gère déjà ce cas (reconnexion bornée, STR-118) et le serveur
  répond `manifest_not_ready`, pas `stream_not_live` ([ADR 045](045-codes-derreur-du-manifeste-hls.md)).
- `started_at` d'un flux relancé est écrasé : la tuile mesure le direct **en
  cours**, pas l'historique cumulé. Un historique des diffusions passées serait une
  table à part, hors périmètre.
- Un flux terminé réexpose son `stream_source_url`, donc son secret, dans le
  tableau de bord du propriétaire. C'est le même secret qu'avant sa fin, et la
  rotation reste disponible pour qui veut le renouveler avant de rediffuser.

## Alternatives écartées

**Garder `stopForBackground` et se contenter de retirer `hidden`.** Corrige le web,
laisse le mobile intact : un appel entrant de trente secondes tue toujours le
direct et renvoie les auditeurs au premier segment. Le symptôme le plus visible
disparaissait, la cause restait.

**Faire reprendre la numérotation des segments au serveur après un `start`.**
Techniquement possible (réutiliser le répertoire, passer `-start_number`), mais on
paierait la complexité d'un segmenteur à état pour rattraper une session que le
client n'aurait jamais dû détruire. Corriger le client était plus court et plus
sûr.

**Un endpoint `POST /api/streams/{id}/reset` (`ended → idle`).** Deux appels au
lieu d'un pour relancer, un état intermédiaire de plus dans la machine, et aucune
question à laquelle il répond mieux qu'un `start` élargi.

**Autoriser `start` depuis n'importe quel statut.** Reviendrait à accepter un
`start` sur un flux déjà `live`, que l'index partiel refuserait de toute façon —
mais avec un 500 (violation de contrainte) au lieu d'un 409 lisible.
