# Contribuer à StreamPulse

Merci de prendre le temps de lire ce guide avant d'ouvrir une PR.

## Sommaire

- [Workflow de branches](#workflow-de-branches)
- [Conventions de commit](#conventions-de-commit)
- [Pull Requests](#pull-requests)
- [Configuration & secrets](#configuration--secrets)
- [Signature des commits](#signature-des-commits)

---

## Workflow de branches

Modèle **Git Flow simplifié** :

```
main      ──●──────────────●─────────●───────►   (production, protégée)
            │              ▲         ▲
            │              │ merge   │ merge
develop ───●┴──●──●──●─────●─────────●───────►   (intégration, protégée)
                │  ▲  ▲    ▲
                │  │  │    │
feature/X ─────●┴──●  │    │                    (parts de develop)
feature/Y ──────────●─┴────●
```

**Règles** :

- `main` ← uniquement des merges depuis `develop` (releases) ou `hotfix/*` (urgences).
- `develop` ← uniquement des merges depuis `feature/*` ou `fix/*`.
- Pas de push direct sur `main` ni `develop` — bloqué par les rulesets GitHub.
- Pas de force-push.

### Nommage des branches

Format : `<type>/<ticket>-<slug-court>`

| Type | Usage | Base | Exemple |
| --- | --- | --- | --- |
| `feature/` | Nouvelle fonctionnalité | `develop` | `feature/str-12-auth-google` |
| `fix/` | Correction de bug | `develop` | `fix/str-30-crash-android` |
| `hotfix/` | Correction urgente prod | `main` | `hotfix/str-99-leak-api` |
| `chore/` | Tâche technique sans impact produit | `develop` | `chore/str-7-bump-deps` |
| `docs/` | Documentation | `develop` | `docs/str-8-readme` |

Le `<ticket>` est l'identifiant Linear en minuscules (ex. `str-12`).

---

## Conventions de commit

Le projet suit la spec [**Conventional Commits 1.0.0**](https://www.conventionalcommits.org/fr/v1.0.0/).

### Format

```
<type>(<scope>): <description>

[corps optionnel — explique le pourquoi]

[footer optionnel — BREAKING CHANGE, refs Linear, etc.]
```

### Types autorisés

| Type | Quand l'utiliser |
| --- | --- |
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction de bug |
| `docs` | Modification de doc uniquement |
| `style` | Formatage, espaces, virgules… (pas de changement de logique) |
| `refactor` | Refacto sans nouvelle feature ni bugfix |
| `perf` | Amélioration de performance |
| `test` | Ajout / modification de tests |
| `build` | Système de build, dépendances (Go modules, pubspec, Docker) |
| `ci` | Configuration CI/CD (GitHub Actions) |
| `chore` | Tâche technique sans impact produit |
| `revert` | Annulation d'un commit précédent |

### Scopes recommandés

`api`, `app`, `auth`, `db`, `infra`, `docker`, `ci`, `docs`, `deps`. Optionnel mais encouragé.

### Description

- Mode impératif : "ajoute" plutôt que "ajouté" / "ajoute" plutôt que "ajoutera".
- Pas de point final.
- ≤ 72 caractères pour la ligne de sujet.
- Minuscule en début de description.

### Breaking changes

Soit avec `!` après le type/scope, soit dans le footer :

```
feat(api)!: passer l'endpoint /v1/streams en POST

BREAKING CHANGE: les clients doivent désormais envoyer un body JSON.
```

### Exemples

```
feat(api): ajouter l'endpoint /streams
fix(app): corriger le crash au lancement sur Android 14
docs(readme): documenter le workflow Git
chore(deps): bump go modules
ci: ajouter le workflow de lint des PR
refactor(auth): extraire la logique JWT dans un package dédié
```

### Référencer un ticket Linear

Linear synchronise automatiquement via le nom de branche (`feature/str-12-...`). Tu peux aussi mentionner explicitement dans le footer :

```
feat(auth): ajouter le login Google

Refs: STR-12
```

---

## Pull Requests

### Avant d'ouvrir

- [ ] La branche est à jour avec `develop` (`git fetch && git rebase origin/develop`).
- [ ] Les commits suivent Conventional Commits.
- [ ] Les tests passent localement.
- [ ] Pas de fichier sensible (`.env`, clés, secrets) committé.
- [ ] Aucune valeur de configuration codée en dur (voir [Configuration & secrets](#configuration--secrets)).

### Titre de PR

Le **titre de la PR** doit lui aussi suivre Conventional Commits (il devient le titre du squash commit). Il est validé automatiquement par le workflow [`.github/workflows/lint-pr-title.yml`](.github/workflows/lint-pr-title.yml).

Bons titres :

- `feat(api): ajouter l'endpoint /streams`
- `fix(app): corriger le crash Android 14`

Mauvais titres (refusés) :

- `Update stuff`
- `WIP`
- `Add login` (manque le type)

### Description

Utiliser le template `.github/pull_request_template.md` (créé automatiquement par GitHub à l'ouverture).

### Review

- 1 approbation minimum requise (enforced par ruleset).
- Pas de force-push après review (sauf rebase sur `develop` à jour).
- Préférer le **squash & merge** pour garder un historique linéaire sur `develop`.

---

## Configuration & secrets

Le projet suit la méthodologie [**12-Factor App**](https://12factor.net/fr/config). Toute la
configuration est externalisée via variables d'environnement — **aucune valeur ne doit être
codée en dur** dans le code.

### Règles

| À faire ✅ | À NE PAS faire ❌ |
|---|---|
| Ajouter une variable au [`backend/internal/config`](./backend/internal/config) | Lire `os.Getenv` directement dans la business logic |
| Documenter la variable dans `.env.example` + `docs/infrastructure.md` | Coller un port (`":8080"`), un host (`"localhost"`) ou une URL en dur |
| Utiliser `cfg.HTTPAddr()`, `cfg.DBDSN()`, `cfg.IsDev()` | Stocker `JWT_SECRET = "abc..."` dans un fichier source |
| Générer les secrets via `openssl rand -hex 32` | Committer `.env` (le `.gitignore` le bloque déjà) |

### Workflows CI qui appliquent ces règles

- [**check-hardcoded.yml**](.github/workflows/check-hardcoded.yml) — grep ciblé sur `backend/`
  hors tests : ports littéraux, DSN Postgres avec credentials, secrets assignés en dur.
- **gitleaks** (même workflow) — scan global du diff pour les patterns de secrets.
- [**security.yml**](.github/workflows/security.yml) — `gosec` détecte également les
  credentials littéraux et les usages risqués.

Si l'un de ces jobs échoue sur ta PR, **lis l'erreur** : elle pointe le fichier et la ligne.
Déplace la valeur dans `.env.example` + le package `config`, puis lis-la via `cfg.XXX()`.

### Ajouter une nouvelle variable d'environnement

1. Ajouter le champ dans la struct `Config` (`backend/internal/config/config.go`) avec le tag `mapstructure`.
2. Ajouter le `BindEnv` correspondant dans `Load()`.
3. Définir un `SetDefault` si pertinent, ou compléter la validation `validate()` si la variable est requise.
4. Documenter dans `.env.example` (avec un commentaire et une valeur d'exemple non-secrète).
5. Mettre à jour la table dans [`docs/infrastructure.md`](./docs/infrastructure.md#variables-denvironnement).
6. Si la variable est consommée par un conteneur Docker, la propager dans `docker-compose.yml`.

Voir l'[ADR 004](./docs/adr/004-config-12-factor-viper.md) pour les détails de l'implémentation.

---

## Signature des commits

Les commits sur `main` doivent être **signés** (GPG ou SSH).

### Setup SSH signing (recommandé)

```bash
# Configurer la clé SSH comme clé de signature
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
git config --global commit.gpgsign true
git config --global tag.gpgsign true
```

Puis ajouter la clé publique sur GitHub : **Settings → SSH and GPG keys → New SSH key → Key type: Signing Key**.

### Vérifier

```bash
git log --show-signature -1
```

Le commit doit afficher `Good "git" signature for ...`.
