# ADR 047 — Connexion via Google (« Sign in with Google »)

**Date** : 2026-08-31
**Statut** : Accepté
**Ticket** : STR-XXX (US connexion Google)

## Contexte

L'écran de connexion proposait déjà un bouton Google, mais inerte (« bientôt
disponible »). Il manquait le vrai flux : permettre à un utilisateur de se
connecter avec son compte Google, sans mot de passe StreamPulse.

Contraintes du terrain :

1. **La confiance vient de Google, pas du client.** Le mobile ne peut pas se
   contenter d'envoyer « voici mon email Google » : n'importe qui pourrait le
   forger. Google émet un **ID token** (JWT signé RS256) que seul le backend, en
   le vérifiant contre les clés publiques de Google, peut considérer comme preuve
   d'identité.
2. **Un compte Google n'a pas de mot de passe local.** Le schéma `users` imposait
   `password_hash NOT NULL` : incompatible avec un compte sans mot de passe.
3. **La fonctionnalité doit rester optionnelle.** En développement local, sans
   projet Google Cloud configuré, l'API doit démarrer et fonctionner normalement.

## Décision

### 1. Un endpoint dédié `POST /api/auth/google`

Le mobile obtient l'ID token via le plugin `google_sign_in` (côté appareil), et le
POST à `/api/auth/google`. Le backend le **vérifie** avec la librairie officielle
`google.golang.org/api/idtoken` (`idtoken.Validate`) : signature, expiration et
**audience** (== `GOOGLE_CLIENT_ID`, le Client Web OAuth) sont contrôlées par la
lib ; l'émetteur est re-vérifié par défense en profondeur. En cas de succès, le
service retrouve-ou-crée le compte et émet le **même couple de jetons StreamPulse**
que le login classique (`issueTokenPair`, partagé avec `Login`). L'identité Google
ne sert qu'à l'authentification initiale : ensuite, ce sont les JWT maison.

`GoogleVerifier` est une **interface** (ISP + DIP) : le service en dépend, un fake
la remplace dans les tests sans réseau ni compte Google. Elle est injectée par
setter (`SetGoogleVerifier`), comme le `UserTrackPurger` (ADR 032) — donc **nil par
défaut**, et la route n'est montée dans `main.go` que si `GOOGLE_CLIENT_ID` est
renseigné (sinon 404, la fonctionnalité est proprement absente).

### 2. Première connexion = création automatique du compte

Un email Google inconnu crée un compte (rôle `user`), username dérivé de la partie
locale de l'email (à défaut du nom Google, à défaut « user »), désambiguïsé par un
suffixe hexadécimal aléatoire en cas de collision. Un email **déjà connu** (compte
email/mot de passe existant) est simplement retrouvé : Google devient une seconde
porte d'entrée sur le même compte. La course (compte créé entre-temps) est rattrapée
en relisant l'email après un conflit.

L'email doit être **vérifié** côté Google (`email_verified`), sinon 401 : sans quoi
on pourrait s'approprier l'email d'autrui.

### 3. `password_hash` nullable, sans casser le code existant

Migration `000024` : `ALTER TABLE users ALTER COLUMN password_hash DROP NOT NULL`.
Les comptes Google ont `password_hash` NULL. Pour éviter de propager un type
nullable (`pgtype.Text`) dans tout le code, les requêtes de lecture renvoient
`COALESCE(password_hash, '')::text` : le Go continue de recevoir une `string`. La
**connexion par mot de passe reste sûre** pour un compte sans hash : `bcrypt.Compare`
échoue face à une chaîne vide → jamais de connexion sans identifiant.

> Le numéro **024** suit `000023_create_listening_history` (ADR 046) : un numéro de
> migration est global et n'est jamais réutilisé.

## Côté mobile

- `GoogleAuthService` (`core/auth/`) : abstraction (DIP) du plugin `google_sign_in`,
  renvoie l'ID token. Un fake la remplace en test. L'annulation de la feuille Google
  lève `GoogleSignInCancelled` (l'UI reste silencieuse), un échec `GoogleSignInFailure`.
- `AuthRepository.loginWithGoogle()` orchestre : ID token → `POST /api/auth/google`
  (écrit à la main via le `Dio` sous-jacent, comme les endpoints bonus reco/sonde,
  ADR 045/046) → persistance des jetons dans `SecureStorage`.
- iOS : `google_sign_in_ios` lit `GIDClientID` (Client iOS) et `GIDServerClientID`
  (Client Web = `GOOGLE_CLIENT_ID` backend) depuis `Info.plist`, plus le
  `REVERSED_CLIENT_ID` en schéma d'URL. Android passe le `serverClientId` via
  `--dart-define=GOOGLE_SERVER_CLIENT_ID`.

## Alternatives écartées

- **Vérifier le JWT Google à la main (JWKS + golang-jwt).** Faisable, mais
  réimplémente la rotation des clés et la validation d'audience que la lib officielle
  Google fait déjà, testée. Le gain (une dépendance de moins) ne valait pas le risque
  sur un chemin de sécurité.
- **Flux `serverAuthCode` + échange côté backend.** Utile si le backend doit appeler
  des API Google au nom de l'utilisateur (Drive, Gmail…). Ici on ne veut qu'une
  identité : l'ID token suffit, sans stocker de secret client ni de refresh Google.
- **Stocker le `sub` Google dans une colonne dédiée.** Plus robuste si un jour l'email
  Google d'un compte change. Repoussé : l'email vérifié est une clé d'identité
  suffisante pour l'US, et cela évitait une colonne + un index de plus. À rouvrir si
  le besoin de lier plusieurs fournisseurs à un compte apparaît.
- **Login seulement (pas de création auto).** Écarté au profit du standard « Sign in
  with Google » : première connexion = compte créé, parcours sans friction.
