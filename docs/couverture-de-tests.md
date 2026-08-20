# Couverture de tests

Ce que la suite de tests garantit, sur quel périmètre, et comment la rejouer.

Le sujet exige « un code **testable unitairement à 80 % minimum** ». Ce document
dit ce que ce chiffre recouvre — parce qu'un pourcentage sans périmètre déclaré
ne veut rien dire : on peut le tenir en ajoutant du code trivial, ou le rater à
cause de code que personne ne peut raisonnablement tester.

---

## 1. État

| | Couverture |
|---|---|
| **Périmètre déclaré** | **81,05 %** — 2233 / 2755 statements |
| Total brut, tout inclus | 63,6 % — 2233 / 3512 |

La porte de CI échoue sous **80 %** sur le périmètre déclaré.

## 2. Le périmètre, et pourquoi

Quatre familles sont exclues du calcul. Chacune pour une raison qui tient, et
l'exclusion est appliquée par le script, pas par une convention orale.

| Exclu | Statements | Pourquoi |
|---|---|---|
| `internal/*/db/` | 336 | Code **généré par sqlc**. Le tester reviendrait à tester sqlc ; il est réécrit à chaque `sqlc generate` et n'a pas d'auteur. |
| `cmd/api/` | 155 | **Racine de composition** : construit la configuration, ouvre le pool, monte les routes, écoute. L'exercer demande de démarrer le serveur — un test de bout en bout, pas un test unitaire. Voir § 5. |
| `internal/infrastructure/` | 135 | **Enveloppes minces** sur des pilotes tiers (golang-migrate, pgx). Les tester serait tester les pilotes ; leur comportement réel est vérifié par les tests d'intégration, qui passent par eux. |
| `internal/testsupport/` | 59 | Le **socle de test** lui-même. Sa couverture est un artefact : il n'est exécuté que par d'autres tests. |

Tout le reste est compté : handlers, services, repositories, middlewares,
configuration, observabilité.

## 3. Deux familles de tests

**Tests unitaires** — `go test ./...`. Handlers contre des stubs, services
contre des dépôts en mémoire, fonctions pures. Rapides, sans dépendance.

**Tests d'intégration** — `go test -tags integration ./...`. Les repositories
contre un **vrai PostgreSQL**, migrations appliquées. Ils existent parce qu'une
part des règles du projet ne vit pas dans le code Go mais dans le schéma, et
qu'un dépôt en mémoire les laisse toutes passer :

| Règle | Où elle vit |
|---|---|
| Un seul flux en direct par diffuseur | Index partiel unique (migration `000016`) |
| Nom de playlist unique par utilisateur | `uq_playlists_user_name` |
| Titre de piste unique par utilisateur | `uq_tracks_user_title` |
| Réordonnancement d'une playlist | `UNIQUE (playlist_id, position)` **différée** |
| Suppression de compte en cascade | 11 clés étrangères, 9 `CASCADE` + 2 `SET NULL` |
| Trace d'audit survivant à son auteur | `audit_logs.actor_id ON DELETE SET NULL` |
| Compte désactivé ne renouvelant plus | Jointure sur `is_active` |

Sans base joignable, ces tests se **sautent** — ils n'échouent pas. La même
commande reste donc jouable sur un poste sans PostgreSQL.

## 4. Rejouer

```bash
make coverage        # unitaires seuls, informatif
make coverage-gate   # unitaires + intégration, échoue sous le seuil
```

Pour les tests d'intégration, une base jetable suffit :

```bash
docker run -d --rm --name streampulse-it \
  -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test \
  -p 15432:5432 postgres:16-alpine
cd backend && go test -tags integration ./...
docker stop streampulse-it
```

Ou contre n'importe quelle base via `TEST_DATABASE_URL`.

> ⚠️ Ces tests **écrivent** dans la base ciblée. Ne jamais y pointer une base de
> développement dont le contenu compte.

En CI, un service `postgres:16-alpine` est démarré par le job `Test` et les
tests d'intégration tournent à chaque PR.

## 5. Ce qui reste hors d'atteinte

1. **Le câblage de `cmd/api/main.go` n'est vérifié par aucun test.** Les routes
   sont montées là, avec leurs gardes de rôle ; un test qui déplacerait une
   route sous le mauvais middleware ne serait pas détecté. C'est le trou le plus
   coûteux qui subsiste, et il demande un test de bout en bout montant le mux
   réel — un chantier à part entière.
2. **La couverture ne dit pas la qualité.** Un statement exécuté n'est pas un
   statement vérifié. Le seuil protège contre l'érosion, il ne prouve rien sur
   la pertinence des assertions.
3. **Les tests d'intégration partagent une base sans la vider.** Ils s'isolent
   par un préfixe unique dans les champs recherchables. C'est suffisant ici,
   mais deux exécutions concurrentes sur la même base peuvent se gêner.
4. **La couverture Flutter n'est pas gardée.** Elle est à ~68 % et aucun seuil
   ne s'y applique : le sujet ne l'exige explicitement que pour le Go.
