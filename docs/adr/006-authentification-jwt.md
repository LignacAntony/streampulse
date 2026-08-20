# ADR 006 — Authentification JWT : access token + refresh token

## Statut

Accepté — 2026-05-05

## Contexte

STR-38 introduit la connexion sécurisée. L'API doit pouvoir :

1. Authentifier un utilisateur (email + mot de passe bcrypt).
2. Délivrer des credentials exploitables par le client mobile (Flutter) pour accéder aux routes protégées.
3. Permettre le renouvellement des credentials sans demander à l'utilisateur de se reconnecter toutes les 15 minutes.
4. Contrôler l'accès par **rôle** (`anonymous < user < broadcaster < admin`).

La décision porte sur le **format des tokens**, la **stratégie de rafraîchissement**, et la **façon d'injecter l'identité** dans les handlers protégés.

## Décision

### Format : JWT HS256

Utiliser des **JSON Web Tokens** signés en HS256 avec `github.com/golang-jwt/jwt/v5`.

- **Access token** : durée de vie 15 minutes. Contient les claims `sub` (UUID utilisateur) et `role`. Signé avec `JWT_SECRET` (env, min 32 chars).
- **Refresh token** : aléatoire 32 octets (`crypto/rand`), encodé en hex (64 chars). Opaque — ne contient aucune information. Stocké **haché** (SHA-256) dans la table `refresh_tokens`.

### Rotation systématique du refresh token

À chaque appel `POST /api/auth/refresh`, l'ancien hash est **supprimé** et un nouveau est **inséré** dans une transaction atomique (`RotateRefreshToken`). Une réutilisation du même token retourne immédiatement `401 Unauthorized`.

- Garantit qu'un token volé ne peut pas être utilisé une fois que le titulaire légitime l'a consommé.
- Pas de colonne `revoked` — un token supprimé est simplement absent de la table.

### Middleware HTTP

```go
// Chaîne simple dans main.go
mux.Handle("/api/route", auth.RequireAuth(cfg.JWTSecret, handler))
mux.Handle("/api/admin", auth.RequireAuth(cfg.JWTSecret, auth.RequireRole("admin", handler)))
```

`RequireAuth` valide la signature et l'expiration du JWT, puis injecte `userID` et `role` dans le `context.Context` via des clés privées (`contextKey int`). Les handlers récupèrent l'identité avec `auth.UserIDFromContext(r.Context())`.

### ISP sur le Handler

Le `Handler` auth déclare trois interfaces étroites au lieu d'une seule large :

```go
type Registrar      interface { Register(...) }
type Authenticator  interface { Login(...) }
type TokenRefresher interface { Refresh(...) }
```

`*Service` les satisfait toutes. Les tests stubbent uniquement l'interface dont ils ont besoin.

## Alternatives considérées

### Sessions serveur (cookie + store Redis/DB)

- **Avantage :** révocation immédiate possible ; pas de JWT expiré en circulation.
- **Rejet :** nécessite un store partagé entre les instances (complexité infra) ; incompatible avec le client mobile stateless Flutter ; surcharge réseau à chaque requête pour valider en base.

### Tokens opaques uniquement (pas de JWT)

- **Avantage :** révocation simple (supprimer de la DB) ; pas de claims exposés au client.
- **Rejet :** chaque requête protégée nécessite un aller-retour DB pour valider le token → latence + charge. Le JWT permet la validation locale en O(1).

### Refresh token sans rotation

- **Avantage :** implémentation plus simple.
- **Rejet :** un refresh token volé est réutilisable indéfiniment jusqu'à expiration (7 jours). La rotation détecte le vol et invalide les deux parties.

### RS256 (clé asymétrique)

- **Avantage :** la clé publique peut être partagée avec d'autres services pour valider les tokens sans exposer le secret.
- **Rejet :** surcharge pour un service monolithique ; RS256 nécessite une gestion de paire de clés (rotation, stockage sécurisé). HS256 avec un secret fort (≥ 32 chars) est suffisant à ce stade.

## Conséquences

### Avantages

- **Stateless** : les routes protégées valident le JWT localement sans DB — latence minimale.
- **Mobile-friendly** : le client Flutter stocke les deux tokens, utilise l'access token pour les requêtes, rafraîchit silencieusement en arrière-plan.
- **Rôles dans le token** : le middleware n'a pas besoin d'une requête DB pour connaître le rôle — il lit le claim directement.
- **Sécurité renforcée** : rotation + hash SHA-256 en base — même une fuite de la table `refresh_tokens` n'expose pas les tokens bruts.

### Inconvénients

- **Révocation d'access token impossible** : un access token valide reste exploitable jusqu'à expiration (15 min). Acceptable pour ce cas d'usage ; une liste de révocation (JTI blacklist) peut être ajoutée si nécessaire.
- **Secret partagé** : si `JWT_SECRET` est compromis, tous les tokens en circulation sont invalidables uniquement en changeant le secret et en forçant une reconnexion globale.

### Impact sur les tests

- Les tests unitaires du service utilisent `fakeRepo` en mémoire — aucune DB requise.
- Les tests du middleware utilisent des tokens générés avec un secret de test (`testSecret` constant dans les `*_test.go`).
- Les tests handler utilisent des stubs d'interface — les tokens ne sont pas générés, seuls les codes HTTP sont vérifiés.

## Références

- ADR 008 : [Architecture handler / service / repository](008-architecture-handler-service-repository.md) — les interfaces ISP s'inscrivent dans ce pattern.
- Linear : [STR-38](https://linear.app/streampulse/issue/STR-38) — ticket de connexion sécurisée.
- `internal/auth/token.go` — `GenerateAccessToken`, `ParseAccessToken`, `GenerateRefreshToken`.
- `internal/auth/middleware.go` — `RequireAuth`, `RequireRole`.
