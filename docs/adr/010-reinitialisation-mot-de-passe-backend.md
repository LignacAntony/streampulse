# ADR 010 — Réinitialisation de mot de passe : sécurisation côté backend

**Date** : 2026-05-25  
**Statut** : Accepté  
**Ticket** : [STR-54](https://linear.app/streampulse/issue/STR-54) / [STR-55](https://linear.app/streampulse/issue/STR-55) / [STR-56](https://linear.app/streampulse/issue/STR-56) / [STR-57](https://linear.app/streampulse/issue/STR-57)

---

## Contexte

STR-54 demande l'implémentation d'un workflow de réinitialisation de mot de passe. L'utilisateur qui a oublié son mot de passe doit pouvoir en définir un nouveau via un lien envoyé par email, sans être connecté.

Ce workflow introduit de nouvelles contraintes de sécurité absentes des autres endpoints d'auth :

- Le token envoyé par email est une **credential temporaire** : s'il fuite, n'importe qui peut modifier le compte.
- Le serveur ne doit **pas confirmer** qu'un email est enregistré (risque d'énumération de comptes).
- Le token doit être **à usage unique** et **expiré** après un certain délai.
- L'envoi d'email nécessite une infrastructure **adaptable** selon l'environnement (dev vs prod).

---

## Décision

### 1. Token stocké haché, jamais en clair

Le token brut est généré avec `crypto/rand` (32 octets, encodé en hex — la même fonction `GenerateRefreshToken` que pour les refresh tokens). Il n'est transmis qu'une seule fois, dans le corps de l'email.

En base de données, seul le **SHA-256 du token brut** est persisté dans la colonne `token_hash` :

```go
raw, hash, err := GenerateRefreshToken()  // hash = SHA-256(raw)
repo.StorePasswordResetToken(ctx, uwh.ID, hash, expiresAt)
mailer.SendPasswordResetEmail(ctx, uwh.Email, raw)  // raw dans l'email uniquement
```

Ce pattern est **identique au refresh token** (ADR 006). Si la table `password_reset_tokens` est compromise, les hashes sont inexploitables sans le token brut qui n'a été transmis que dans l'email.

**Alternative rejetée — stocker le token en clair ou en base64** : simple à implémenter, mais une fuite de la table permettrait d'usurper tous les comptes dont le token n'a pas encore été utilisé.

**Alternative rejetée — UUID comme token** : `uuid.New().String()` est lisible et prévisible dans sa structure (variant, timestamp). Un token aléatoire de 32 octets offre une entropie de 256 bits, contre ~122 bits pour un UUID v4.

### 2. Anti-énumération : la fonction retourne toujours `nil`

`Service.ForgotPassword` retourne `nil` dans **tous les cas d'échec non critiques** :

```go
func (s *Service) ForgotPassword(ctx context.Context, in ForgotPasswordInput) error {
    email, err := normalizeEmail(in.Email)
    if err != nil {
        return nil  // email invalide → silencieux
    }
    uwh, err := s.repo.GetUserByEmail(ctx, email)
    if err != nil {
        return nil  // email inconnu → silencieux
    }
    // ... génération et envoi
}
```

Le handler répond toujours `200 OK` avec le même message générique, que l'email existe ou non.

**Pourquoi** : si le serveur répondait différemment selon que l'email existe ou non (400 vs 200, délai différent, message différent), un attaquant pourrait automatiser des requêtes pour constituer une liste d'emails enregistrés. Cette technique s'appelle l'**énumération de comptes** et est classée dans l'OWASP Top 10 (A07 — Identification and Authentication Failures).

**Alternative rejetée — retourner une erreur sur email inconnu** : comportement intuitif depuis la perspective développeur, mais dangereux en production. Aucun gain fonctionnel pour l'utilisateur légitime.

### 3. Transaction atomique pour la réinitialisation

`repo.ResetPassword` regroupe trois opérations dans une transaction PostgreSQL :

```
BEGIN
  GetValidPasswordResetToken(tokenHash)    -- vérifie : token existe + non expiré + non utilisé
  UpdateUserPasswordHash(userID, newHash)  -- met à jour le mot de passe
  MarkPasswordResetTokenUsed(tokenHash)    -- remplit used_at = NOW()
COMMIT
```

**Pourquoi la transaction** : sans elle, deux appels simultanés avec le même token pourraient tous deux passer la vérification (`used_at IS NULL`), puis tous deux mettre à jour le mot de passe. L'atomicité garantit que dès que `MarkPasswordResetTokenUsed` est commité, tout appel concurrent échoue à la vérification.

Le token n'est pas **supprimé** mais **marqué utilisé** (`used_at = NOW()`). Cela préserve la traçabilité (audit log naturel : qui a demandé quoi, quand, quand utilisé).

**Alternative rejetée — supprimer le token après usage** : plus simple, mais perd l'historique. Un support technique ne pourrait plus confirmer qu'un reset a bien eu lieu à une date donnée.

**Alternative rejetée — vérification + update sans transaction** : race condition possible en cas d'appels parallèles (attaque de rejeu ou double-clic réseau). La transaction élimine ce risque.

### 4. Un seul token actif par utilisateur

Avant de créer un nouveau token, tous les tokens en attente (`used_at IS NULL`) de cet utilisateur sont supprimés :

```go
_ = s.repo.DeletePendingPasswordResetsByUser(ctx, uwh.ID)
```

**Pourquoi** : si un utilisateur fait plusieurs demandes consécutives (spam, erreur de frappe sur l'email), plusieurs tokens valides coexistent en base. L'ancien lien dans une ancienne version de l'email reste fonctionnel. En forçant l'unicité, seul le lien le plus récent fonctionne — comportement attendu par les utilisateurs.

L'erreur éventuelle de `DeletePendingPasswordResetsByUser` est **silenciée** (`_ = ...`) car l'échec de cette purge ne doit pas bloquer la création du nouveau token ni l'envoi de l'email.

**Alternative rejetée — conserver tous les tokens** : accumulation indéfinie de tokens valides, potentiel d'abus si un ancien email est intercepté.

### 5. Expiration à 1 heure

```go
const PasswordResetTokenDuration = time.Hour
```

**Pourquoi 1 heure** : fenêtre suffisante pour qu'un utilisateur reçoive l'email, l'ouvre et réinitialise son mot de passe dans des conditions normales (y compris sur mobile avec une connexion lente). Une fenêtre plus courte (15 min) augmente le taux d'échec ; une fenêtre plus longue (24h) laisse le token exposé plus longtemps si l'email est intercepté ou si le compte email est compromis.

**Alternative rejetée — expiration à 24h** : standard de beaucoup d'applications, mais laisse le token exploitable toute une journée. 1h est un compromis meilleur compte tenu que l'email arrive quasi-instantanément.

**Alternative rejetée — pas d'expiration** : un token valide indéfiniment est une credential permanente — inacceptable.

### 6. Deux implémentations Mailer (SMTPMailer / LogMailer)

Le package `internal/email` expose une interface `Mailer` et deux implémentations. Le choix est fait au démarrage selon la présence de `SMTP_HOST` :

```go
func NewFromConfig(cfg *config.Config) Mailer {
    if cfg.SMTPHost == "" {
        return &LogMailer{}   // dev : affiche le token dans stdout
    }
    return &SMTPMailer{ ... } // prod : envoi réel via net/smtp
}
```

**Pourquoi ce pattern** : les développeurs peuvent travailler sans configurer un relay SMTP. `LogMailer` imprime le token brut dans les logs Docker (`docker compose logs -f api`), suffisant pour le développement local.

En production, il suffit de renseigner `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` pour basculer automatiquement sur `SMTPMailer` sans modifier le code.

**Pourquoi l'interface est re-déclarée dans `email/`** : `email.Mailer` est identique à `auth.Mailer` mais déclarée séparément pour éviter l'import circulaire (`email` → `auth` → `email`). Go utilise la satisfaction structurelle des interfaces (duck typing) — `*SMTPMailer` satisfait `auth.Mailer` sans qu'il soit nécessaire de l'importer.

**Alternative rejetée — une seule implémentation avec `if cfg.SMTPHost == ""`** : mélange la logique de dispatch avec la logique d'envoi, moins testable, moins extensible (si on veut ajouter un troisième mailer type SendGrid plus tard).

**Alternative rejetée — Mailhog** : Mailhog (image `mailhog/mailhog`) a été initialement évalué. Son image Docker Hub n'est plus maintenue et entraîne des timeouts TLS sur certains réseaux d'entreprise. Mailpit (`axllent/mailpit`) est l'alternative active recommandée par la communauté Go, avec une UI plus moderne et des fonctionnalités supplémentaires (search, pagination, aperçu HTML).

### 7. Authentification SMTP optionnelle

```go
var auth smtp.Auth
if m.username != "" {
    auth = smtp.PlainAuth("", m.username, m.password, m.host)
}
smtp.SendMail(addr, auth, m.from, []string{to}, msg)
```

`smtp.PlainAuth` échoue si le serveur ne supporte pas AUTH (c'est le cas de Mailpit en développement). En rendant l'authentification conditionnelle sur la présence de `SMTP_USERNAME`, le même code fonctionne avec Mailpit (sans auth) et avec un relay production (avec auth).

---

## Conséquences

### Avantages

- **Sécurité** : token haché en base, anti-énumération, usage unique transactionnel, expiration courte — chaque décision réduit la surface d'attaque de façon indépendante.
- **Portabilité** : `LogMailer` / `SMTPMailer` permettent de travailler sans infrastructure email en dev.
- **Traçabilité** : `used_at` conserve un audit trail naturel des resets effectués.
- **Cohérence** : le pattern token haché est identique aux refresh tokens (ADR 006) — pas de nouveau pattern à apprendre.

### Inconvénients

- **Pas de révocation proactive** : si un utilisateur refait une demande, l'ancien token est supprimé, mais les emails déjà envoyés avec l'ancien token pointeront vers un lien invalide — l'utilisateur peut être confus.
- **Pas de rate limiting** : rien n'empêche d'envoyer des milliers de demandes par minute pour un email valide. Un rate limiter par IP ou par email devra être ajouté dans une US dédiée.

### Impact sur les tests

- `service_test.go` couvre : happy path, email inconnu (nil), email invalide (nil), remplacement du token existant, token expiré, token utilisé, mot de passe trop court.
- `handler_test.go` couvre : corps malformé (400), service error (500), happy path (200).
- `fakeMailer` capture `lastTo` et `lastToken` pour vérifier que l'email est envoyé avec les bonnes valeurs.

---

## Références

- [ADR 006](006-authentification-jwt.md) — pattern refresh token haché (même approche)
- [ADR 008](008-architecture-handler-service-repository.md) — layering handler / service / repository
- `backend/internal/auth/service.go` — `ForgotPassword`, `ResetPassword`
- `backend/internal/auth/repository.go` — `ResetPassword` (transaction)
- `backend/internal/email/mailer.go` — `SMTPMailer`, `LogMailer`, `NewFromConfig`
- `backend/migrations/000008_create_password_reset_tokens.up.sql`
- OWASP Top 10 A07 — Identification and Authentication Failures
