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
| **Périmètre déclaré** | **81,60 %** — 2355 / 2886 statements |
| Total brut, tout inclus | 65,76 % — 2355 / 3581 |

La porte de CI échoue sous **80 %** sur le périmètre déclaré.

> **Relevé du 2026-08-23**, sortie de la porte de couverture du job `Test`
> ([run 32630923293](https://github.com/LignacAntony/streampulse/actions/runs/32630923293)).
> Ces valeurs bougent à **chaque merge** : le README ne les recopie donc pas et
> renvoie ici. Les rafraîchir se fait avec `make coverage-gate` (§ 4), et la
> mesure de référence est celle de la CI, qui exécute aussi les tests
> d'intégration.

Le même numérateur — 2355 — apparaît dans les deux lignes. Ce n'est pas une
coquille : les paquets exclus n'ont **aucune** instruction couverte, ce qui est
attendu puisque rien ne les exerce (cf. § 2).

## 2. Le périmètre, et pourquoi

Quatre familles sont exclues du calcul. Chacune pour une raison qui tient, et
l'exclusion est appliquée par le script, pas par une convention orale.

| Exclu | Statements | Pourquoi |
|---|---|---|
| `internal/*/db/` | 340 | Code **généré par sqlc**. Le tester reviendrait à tester sqlc ; il est réécrit à chaque `sqlc generate` et n'a pas d'auteur. |
| `cmd/api/` | 162 | **Racine de composition** : construit la configuration, ouvre le pool, monte les routes, écoute. L'exercer demande de démarrer le serveur — un test de bout en bout, pas un test unitaire. Voir § 5. |
| `internal/infrastructure/` | 134 | **Enveloppes minces** sur des pilotes tiers (golang-migrate, pgx). Les tester serait tester les pilotes. ⚠️ Ces paquets ne sont **exercés par aucun test** à ce jour — voir la note ci-dessous. |
| `internal/testsupport/` | 59 | Le **socle de test** lui-même. Sa couverture est un artefact : il n'est exécuté que par d'autres tests. |

Tout le reste est compté : handlers, services, repositories, middlewares,
configuration, observabilité.

> ⚠️ **`internal/infrastructure` n'est pas « couvert autrement ».** Ce document
> a longtemps écrit que son comportement réel était « vérifié par les tests
> d'intégration, qui passent par eux ». C'est faux, et c'était la source de la
> même affirmation dans le README (revue PR #315).
>
> Les tests d'intégration ne traversent pas ces paquets : `internal/testsupport/pgtest`
> **réimplémente** migrations et pool directement avec `golang-migrate` et
> `pgxpool`, sans rien importer de `internal/infrastructure`. Il fait le même
> travail avec les mêmes bibliothèques, dans son propre code.
>
> ```
> $ grep -nE "streampulse/internal/(infrastructure|migrator|seeder)" \
>     backend/internal/testsupport/pgtest/pgtest.go
> (aucun résultat)
> ```
>
> La preuve tient aussi dans le profil de couverture : les paquets exclus ont
> zéro instruction couverte (§ 1). S'ils étaient exercés, le total brut aurait
> un numérateur plus grand que celui du périmètre.
>
> L'exclusion reste justifiée — ce sont des enveloppes de pilotes tiers — mais
> elle l'est parce qu'elles ne valent pas un test unitaire, **pas** parce
> qu'elles seraient testées ailleurs. La nuance compte : la première formulation
> décrit un choix, la seconde masquait un trou.

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

Pour les tests d'intégration, une base jetable suffit. La cible est **toujours
explicite** — `TEST_DATABASE_URL` n'a pas de valeur par défaut :

```bash
docker run -d --rm --name streampulse-it \
  -e POSTGRES_USER=test -e POSTGRES_PASSWORD=test -e POSTGRES_DB=test \
  -p 15432:5432 postgres:16-alpine

cd backend
export TEST_DATABASE_URL="postgres://test:test@localhost:15432/test?sslmode=disable"
go test -tags integration ./...

docker stop streampulse-it
```

> ⚠️ Ces tests **écrivent** dans la base ciblée. Ne jamais y pointer une base de
> développement dont le contenu compte.
>
> C'est la raison pour laquelle il n'y a pas de valeur par défaut : un défaut
> pointant sur un port courant finit toujours par s'appliquer à une base qu'on
> ne visait pas. Sans la variable, les tests d'intégration se sautent.

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
