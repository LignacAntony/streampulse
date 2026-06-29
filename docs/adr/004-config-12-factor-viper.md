# ADR 004 — Configuration 12-Factor App via Viper

- **Date :** 2026-04-27
- **Statut :** Accepté
- **Ticket Linear :** STR-23 (parent), STR-25

---

## Contexte

L'API StreamPulse doit être déployable sur plusieurs environnements (développement local,
CI, production VPS). La méthodologie [12-Factor App](https://12factor.net/fr/config)
exige que **toute la configuration soit externalisée** via variables d'environnement —
aucune valeur sensible (secrets JWT, identifiants base de données) ni dépendante de
l'environnement (URLs, ports) ne doit être codée en dur dans le code source.

Trois besoins distincts :

1. **Lire** des variables depuis l'environnement avec validation au démarrage.
2. **Charger** un fichier `.env` à la racine en développement local sans pénaliser la prod.
3. **Empêcher** le hardcoding accidentel à l'avenir (CI check).

---

## Décision

Adopter **Viper** comme bibliothèque de chargement de configuration, encapsulée dans le
package interne `backend/internal/config`. Les principes :

- **Defaults** explicites pour les variables non-sensibles (`GO_ENV`, `API_PORT`, `DB_HOST`, `DB_PORT`).
- **Required** strict pour les variables sensibles (`JWT_SECRET`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`).
- **Fail-fast** au démarrage : si une variable requise manque ou si `JWT_SECRET` < 32 caractères,
  `config.Load()` retourne une erreur et l'API refuse de démarrer.
- **`.env` optionnel** : Viper tente de lire un `.env` à la racine du repo (utile en dev local).
  Absent en production — pas d'erreur.
- **Priorité** : variables d'environnement réelles > `.env` > defaults.
- **Helpers** typés : `cfg.HTTPAddr()`, `cfg.DBDSN()`, `cfg.IsDev()`, `cfg.IsProd()`.

Un workflow GitHub Actions `check-hardcoded.yml` complète la décision en bloquant tout
push qui contiendrait un port littéral, une DSN avec credentials inline, ou un secret
assigné en dur dans le code Go.

---

## Alternatives considérées

### `os.Getenv` brut

- **Avantage :** zéro dépendance, simplicité maximale.
- **Rejet :** pas de validation centralisée, pas de defaults, parsing manuel à chaque appel
  (`port, _ := strconv.Atoi(os.Getenv("API_PORT"))` répété partout). Encourage les fuites de
  `os.Getenv` dans toute la codebase.

### `envconfig` (Kelsey Hightower)

- **Avantage :** API minimaliste, parsing par tags struct, très répandu.
- **Rejet :** pas de support natif pour fichiers de config (`.env`, `yaml`). Limite si on veut
  un jour ajouter un fichier de config local pour des paramètres non-sensibles.

### Viper

- **Avantage :** support natif `.env` + env vars + valeurs par défaut + binding struct via
  `mapstructure`. Standard de fait dans l'écosystème Go (utilisé par Cobra, Hugo, etcd…).
- **Coût :** ~15 dépendances indirectes ajoutées à `go.sum`. Acceptable pour le bénéfice fonctionnel.

---

## Conséquences

### Avantages

- **12-factor strict** : aucune valeur sensible ou environnement-dépendante dans le code.
- **Fail-fast** : un déploiement avec config incomplète meurt immédiatement plutôt que de
  servir des requêtes avec un secret JWT vide.
- **DX dev local** : `cp .env.example .env`, éditer, `go run` — pas de variable à exporter
  manuellement.
- **Testabilité** : le package `config` est couvert par des tests unitaires (succès, defaults,
  variables manquantes, secret trop court, calcul DSN).
- **Évolutivité** : ajouter une nouvelle variable = ajouter un champ `mapstructure` + un
  `BindEnv` + documenter dans `.env.example` et le README.

### Inconvénients

- **15 dépendances indirectes** ajoutées (`afero`, `cast`, `pflag`, `gotenv`, …). Limité par
  la nature interne de `config` qui n'expose pas Viper publiquement — substituable plus tard.
- **Risque de drift** : `.env.example`, `docs/infrastructure.md` et la struct `Config`
  doivent rester synchronisés. Mitigé par la check-list PR et la table de variables centralisée
  dans `docs/infrastructure.md`.

### Garde-fous

- Le workflow `check-hardcoded` rejette toute PR qui réintroduit du hardcoding en Go.
- `gitleaks` scanne en plus le diff pour détecter les fuites de credentials.
- `.env` est dans `.gitignore` (pattern `.env*` avec exception `!.env.example`).
