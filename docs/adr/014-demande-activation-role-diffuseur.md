# ADR 014 — Demande et activation du rôle diffuseur

## Statut

Accepté — 2026-06-20

## Contexte

STR-49 introduit le parcours permettant à un utilisateur standard (`role = user`) de
**demander** le rôle **diffuseur** (`broadcaster`), et à un **administrateur** de **valider** ou
**refuser** cette demande. La hiérarchie de rôles existe déjà
(`anonymous < user < broadcaster < admin`, cf. [ADR 006](006-authentification-jwt.md)) mais aucun
mécanisme ne permettait jusqu'ici de changer le rôle d'un compte après l'inscription.

Deux besoins se croisent :

1. Un utilisateur veut diffuser ses propres streams → il doit pouvoir **soumettre une demande**
   et **suivre son statut** depuis l'app mobile.
2. La plateforme veut garder le contrôle sur qui diffuse → la promotion passe par une
   **validation humaine** (un admin), pas par une activation automatique.

## Décision

**Créer une table `broadcaster_requests` dédiée et un domaine `internal/broadcaster/`** calqué sur
`internal/profiles/` (handler / service / repository + sqlc), conformément à
l'[ADR 008](008-architecture-handler-service-repository.md).

```sql
CREATE TABLE broadcaster_requests (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status      TEXT NOT NULL DEFAULT 'pending'
                CHECK (status IN ('pending','approved','rejected')),
    message     TEXT NOT NULL DEFAULT '',   -- motivation saisie par l'utilisateur
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    review_note TEXT NOT NULL DEFAULT '',   -- note / raison du refus côté admin
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Une seule demande « pending » par utilisateur à la fois (index partiel unique).
CREATE UNIQUE INDEX broadcaster_requests_one_pending
    ON broadcaster_requests (user_id) WHERE status = 'pending';
```

### Endpoints

| Méthode | Route | Rôle requis | Rôle |
|---|---|---|---|
| POST | `/api/broadcaster-requests` | `user` (JWT) | Soumet une demande `{message}` |
| GET | `/api/broadcaster-requests/me` | `user` (JWT) | Statut de sa dernière demande |
| GET | `/api/admin/broadcaster-requests` | `admin` | Liste les demandes (filtre `?status=`) |
| POST | `/api/admin/broadcaster-requests/{id}/approve` | `admin` | Valide + promeut l'utilisateur |
| POST | `/api/admin/broadcaster-requests/{id}/reject` | `admin` | Refuse + `review_note` |

Points clés de la décision :

- **Table dédiée plutôt qu'une colonne sur `users`.** L'historique des demandes
  (qui a demandé quoi, quand, accepté/refusé par qui) est une donnée à part entière, distincte de
  l'identité du compte. `users` reste focalisée sur l'authentification.
- **Une seule demande active à la fois.** Un index unique partiel
  (`WHERE status = 'pending'`) garantit qu'un utilisateur ne peut pas empiler plusieurs demandes
  en attente ; la violation `23505` est mappée en `409 Conflict`. L'historique des demandes
  traitées reste conservé.
- **Validation humaine via `RequireRole("admin")`.** Première utilisation réelle du middleware de
  restriction de rôle existant. Les routes admin sont chaînées `RequireAuth → RequireRole(admin)`.
- **Promotion atomique.** L'approbation se fait dans une **transaction** (`pgx`) : verrouillage de
  la ligne (`SELECT … FOR UPDATE`), vérification du statut `pending`, mise à jour de la demande,
  puis `UPDATE users.role = 'broadcaster'`. Soit tout réussit, soit rien.
- **Propagation du rôle via le refresh JWT.** Le rôle est porté par l'access token (HS256, 15 min).
  Après approbation, l'utilisateur **devient diffuseur au prochain refresh** : `POST /api/auth/refresh`
  relit `users.role` en base et émet un access token à jour. Aucune révocation immédiate des tokens
  en cours n'est faite (fenêtre ≤ 15 min acceptée) ; l'UI mobile invite à se reconnecter si le rôle
  n'apparaît pas encore.
- **Sécurité.** L'identité (demandeur ou admin validant) provient **exclusivement** du JWT
  (`auth.UserIDFromContext`), jamais du body ni de l'URL. Le décodage JSON reste strict
  (`DisallowUnknownFields`). La note de traitement admin est optionnelle (corps de requête absent
  accepté).

### Mobile

L'app mobile couvre **uniquement le parcours utilisateur** (feature `features/broadcaster/`,
Clean Architecture) : un écran « Devenir diffuseur » accessible depuis le profil, qui soumet la
demande et affiche son statut (en attente / acceptée / refusée). La **validation admin n'est pas
dans l'app mobile** : elle se fera via un back-office **web responsive** (sujet ultérieur), les
endpoints admin étant déjà exposés côté API.

## Alternatives considérées

### Activation automatique (auto-promotion à la demande)

- **Avantage :** aucun travail de modération, parcours instantané.
- **Rejet :** la plateforme perd tout contrôle sur qui diffuse ; ouvre la porte aux abus. Le besoin
  explicite est « demande **et** activation » par un tiers de confiance.

### Colonne `broadcaster_requested_at` sur `users`

- **Avantage :** pas de table ni de jointure supplémentaire.
- **Rejet :** ne modélise qu'une seule demande, sans historique, sans note de refus, sans traçabilité
  de l'admin validant. Mélange à nouveau identité de compte et données de workflow.

### Révocation immédiate des tokens à la promotion

- **Avantage :** le rôle diffuseur serait effectif sur-le-champ.
- **Rejet :** complexité disproportionnée (purge des refresh tokens, forcer un re-login). La fenêtre
  de 15 min du token d'accès est un compromis acceptable, cohérent avec le modèle JWT existant.

## Conséquences

### Avantages

- **Traçabilité complète** du workflow (demande, décision, auteur de la décision, note).
- **Réutilisation** du middleware `RequireRole` et du squelette handler/service/repository ; aucune
  dépendance tierce ajoutée.
- **Atomicité** garantie de la promotion (transaction + verrou de ligne).
- **Testabilité** : tests service (fake repo) et handler (stubs + `RequireAuth`/`RequireRole` réels)
  sans Docker ; test du contrôleur mobile avec fake repository.

### Inconvénients

- **Latence de propagation du rôle** (≤ 15 min, jusqu'au prochain refresh). Documenté et atténué par
  l'invite à se reconnecter côté mobile.
- **Validation admin hors app mobile** pour l'instant : nécessite Swagger ou le futur back-office web.

### Suivi

- Back-office **web responsive** pour la validation admin (sujet dédié).
- Notification (push / email) de l'utilisateur à la décision — la colonne `review_note` est déjà en
  place pour alimenter le message.

## Références

- ADR 006 : [Authentification JWT](006-authentification-jwt.md) — rôles, `RequireRole`, refresh.
- ADR 008 : [Architecture handler / service / repository](008-architecture-handler-service-repository.md) — squelette suivi par `internal/broadcaster/`.
- ADR 038 : [Gestion du profil utilisateur](038-gestion-profil-utilisateur.md) — domaine modèle (`internal/profiles/`).
- ADR 012 : [OpenAPI source de vérité](012-openapi-source-de-verite.md) — spec + client Dart/Dio généré.
- Linear : [STR-49](https://linear.app/streampulse/issue/STR-49) — demande et activation du rôle diffuseur.
