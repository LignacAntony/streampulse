# ADR 048 — Relancer un flux terminé : un flux est un canal, pas un enregistrement

**Date** : 2026-09-02
**Statut** : Accepté
**Ticket** : STR-XXX

## Contexte

La transition de démarrage était gardée sur un seul statut :

```sql
WHERE ... AND s.status = 'idle'
```

Un flux `ended` était donc **définitivement mort**. `PATCH /api/streams/{id}/start`
répondait `409 stream is not idle`, sans recours, et aucune transition
`ended → idle` n'existait ailleurs dans la machine à états.

Ce n'était pas une gêne théorique. Un direct se termine de trois façons, et deux
d'entre elles n'impliquent aucune décision du diffuseur :

- il appuie sur « Arrêter la diffusion » ;
- un administrateur interrompt le flux (US-08-02) ;
- **le bail d'ingest expire** — plus personne ne pousse d'audio pendant
  `INGEST_RECONNECT_GRACE_SECONDS` (45 s), et le serveur termine la session.

Dans les deux derniers cas, le diffuseur retrouvait une tuile inerte. Le tableau
de bord en avait d'ailleurs tiré les conséquences, et les affichait franchement :
ni bouton de démarrage, ni URL d'ingest, ni rotation de clé, et le message
« Diffusion terminée. Créez un nouveau flux pour rediffuser. »

Recréer un flux n'est pas anodin : c'est un nouveau titre à ressaisir, et surtout
une **nouvelle clé d'ingest à rediffuser** à tout encodeur externe déjà configuré.

Constaté en conditions réelles : après quelques essais, les trois flux de
démonstration d'un compte étaient tous `ended`, donc tous inutilisables, sans
qu'aucun ait été arrêté volontairement.

## Décision

### La transition accepte `idle` **ou** `ended`

```sql
SET status = 'live', started_at = NOW(), ended_at = NULL, updated_at = NOW()
WHERE ... AND s.status IN ('idle', 'ended')
```

Un flux porte un titre, une description et une clé d'ingest : c'est un **canal
réutilisable**, pas l'enregistrement d'une diffusion passée. Seul un flux déjà
`live` refuse désormais la transition, et le message du 409 devient
`stream is already live` — le seul cas restant.

`ended_at` repart à `NULL` : la colonne décrit la fin du direct **courant**. La
laisser garnie ferait cohabiter `status = 'live'` et une date de fin,
contradiction que ni l'API ni les tuiles ne savent présenter.

### Aucune migration

La règle « un seul live par diffuseur » reste garantie atomiquement par l'index
partiel unique `streams_one_live_per_user` (migration `000016`) : un second live
concurrent lève toujours un `23505`. Élargir la garde de statut ne touche pas à
cet invariant, et le schéma est inchangé.

C'est aussi pourquoi la règle est testée en **intégration** contre un vrai
PostgreSQL : la garde de transition et le reset de `ended_at` vivent dans le SQL,
aucun fake ne les reproduit.

### Côté mobile, un prédicat plutôt qu'un statut en dur

`BroadcastStream.canStart` (`!isLive`) remplace les `isIdle` semés dans l'écran.
La règle vit à un seul endroit, et l'onglet n'a pas à connaître la liste des
statuts. La tuile d'un flux terminé retrouve son bouton (« Relancer la
diffusion »), son URL d'ingest et sa rotation de clé.

## Conséquences

- Un direct coupé par l'expiration du bail se relance d'un tap, avec la même clé.
- `started_at` d'un flux relancé est **écrasé** : la tuile mesure le direct en
  cours, pas un cumul. Un historique des diffusions passées serait une table à
  part, hors périmètre.
- Un flux terminé réexpose son `stream_source_url`, donc son secret, dans le
  tableau de bord de son propriétaire. C'est le même secret qu'avant sa fin, et
  la rotation reste disponible pour qui veut le renouveler avant de rediffuser.
- Le contrat OpenAPI change de sémantique sans changer de forme : le 409 existe
  toujours, sa cause se réduit.

## Alternatives écartées

**Garder `ended` terminal et faire recréer un flux.** C'était l'état existant. Il
transforme une interruption subie — un bail expiré pendant un trajet en métro —
en perte définitive du canal et de sa clé.

**Un endpoint `POST /api/streams/{id}/reset` (`ended → idle`).** Deux appels au
lieu d'un pour relancer, un état intermédiaire de plus dans la machine, et aucune
question à laquelle il répond mieux qu'un `start` élargi.

**Autoriser `start` depuis n'importe quel statut.** Reviendrait à accepter un
`start` sur un flux déjà `live`, que l'index partiel refuserait de toute façon —
mais avec un 500 (violation de contrainte) au lieu d'un 409 lisible.

**Conserver `ended_at` après la relance, comme trace de la diffusion
précédente.** Séduisant, mais il faudrait alors que tous les lecteurs de l'API
sachent qu'une date de fin ne signifie pas que le flux est fini. Une colonne dont
le sens dépend d'une autre colonne est une invitation au bug ; l'historique, s'il
devient nécessaire, mérite sa propre table.
