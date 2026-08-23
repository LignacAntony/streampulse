# ADR 009 — Authentification côté Flutter : stockage sécurisé, refresh automatique, logout best-effort

**Date** : 2026-05-10
**Statut** : Accepté
**Ticket** : [STR-38](https://linear.app/streampulse/issue/STR-38) (US-02-01 — Connexion sécurisée avec JWT)

---

## Contexte

L'API expose le flow JWT décrit dans [ADR 006](006-authentification-jwt.md) :
`POST /api/auth/login`, `/api/auth/refresh`, `/api/auth/logout` (rotation systématique du
refresh token, access token HS256 d'une durée de 15 min).

Le client Flutter doit :

1. Persister `accessToken` + `refreshToken` de façon sécurisée (chiffrement plateforme).
2. Injecter automatiquement le `Bearer` dans toutes les requêtes sortantes.
3. Renouveler silencieusement l'access token sur `401` (sans déconnecter l'utilisateur).
4. Révoquer le refresh token côté serveur lors du logout, **sans bloquer** la déconnexion locale
   en cas d'incident réseau.
5. Ne jamais fuir d'information technique du backend dans l'UI (messages d'erreur).

L'architecture globale (Clean Architecture par feature) est posée dans
[ADR 005](005-architecture-flutter-clean.md), et le state management retenu — `provider` +
`ChangeNotifier` — dans [ADR 036](036-state-management-flutter-provider.md) ; cet ADR couvre
uniquement les décisions spécifiques à l'auth.

---

## Décision

### 1. Stockage : `flutter_secure_storage` avec EncryptedSharedPreferences

Les tokens sont écrits via une classe wrapper `SecureStorage`
(`mobile/lib/core/storage/secure_storage.dart`) qui expose une interface étroite (5 méthodes :
`saveAccessToken`, `saveRefreshToken`, `getAccessToken`, `getRefreshToken`, `clearTokens`).

- **Android** : `EncryptedSharedPreferences` (AES-256, API 23+) via l'option
  `aOptions: AndroidOptions(encryptedSharedPreferences: true)`.
- **iOS** : Keychain (par défaut du package).

Aucun token n'est écrit en clair dans `SharedPreferences` ou un fichier non chiffré. La classe
est injectée via constructeur dans `DioClient` et `AuthRepositoryImpl` (DIP).

### 2. Auto-injection du Bearer + auto-refresh sur 401

`DioClient` (`mobile/lib/core/network/dio_client.dart`) utilise un intercepteur
`onRequest`/`onError` pour :

- **`onRequest`** : lit l'`accessToken` depuis `SecureStorage` et l'ajoute en header
  `Authorization: Bearer <token>`.
- **`onError` sur 401** : déclenche un **refresh sérialisé**, rejoue la requête originale.

Détails du refresh :

- **Sérialisation par `Completer<bool>`** : si plusieurs requêtes échouent simultanément en 401,
  un seul refresh est lancé ; les autres requêtes attendent le résultat du même `Completer` et
  rejouent ensuite avec le nouveau token.
- **Dio dédié `_refreshDio`** : un second `Dio` sans intercepteur pour appeler `/api/auth/refresh`,
  afin d'éviter une récursion (un 401 sur le refresh déclencherait sinon un nouveau refresh).
- **Anti-boucle** :
  - les requêtes ciblant `/api/auth/{login,register,refresh,logout}` ne déclenchent jamais de
    refresh (elles renvoient un 401 légitime),
  - une requête déjà rejouée (`req.extra['_retried'] == true`) qui re-401 → `clearTokens()` et
    propagation de l'erreur.
- **Échec du refresh** → `clearTokens()` ; le prochain accès à une route protégée par
  `app_router.dart` redirigera l'utilisateur vers `/login`.

### 3. Logout : best-effort serveur + purge locale garantie

`AuthRepository.logout()` (`mobile/lib/features/auth/data/repositories/auth_repository_impl.dart`)
exécute :

1. Lecture du `refreshToken` depuis `SecureStorage`.
2. **Si présent** : `POST /api/auth/logout` avec `{refresh_token}` dans un `try/catch` qui
   silencie toute exception.
3. **Toujours** : `secureStorage.clearTokens()`.

Conséquence : la déconnexion locale réussit même si le serveur est injoignable. Le serveur
n'invalidera pas le refresh token côté DB dans ce cas, mais celui-ci expire de toute façon
sous 7 jours (cf. ADR 006).

L'écran qui déclenche la déconnexion (`profile_screen.dart`, `_logout()`) complète l'appel par
la remise à zéro **explicite** des contrôleurs app-level qui portent de l'état lié au compte :
`BroadcasterController.reset()` et `FavoritesController.reset()`. Sans package de state
management à invalidations déclaratives, c'est le prix à payer — et la raison pour laquelle la
plupart des autres contrôleurs sont **locaux à leur écran**, donc reconstruits vierges à la
reconnexion (cf. [ADR 036](036-state-management-flutter-provider.md) §3).

### 4. Hard-coding du message d'erreur sur 401

`auth_remote_data_source.dart` mappe les statuts HTTP vers des exceptions du domaine. Sur **401
uniquement**, le message serveur est **ignoré** au profit d'un libellé fixe :

```dart
case 401:
  return const AuthException('Email ou mot de passe incorrect');
```

Pour les autres statuts (400, 409, 5xx), `serverMessage` est relayé car ces messages sont
contrôlés (codes business : `email already taken`, `password too short`, etc.).
Le 401 peut en revanche, à l'avenir, exposer des détails techniques (`token signature mismatch`,
`bcrypt cost too low`) que l'on ne veut pas afficher dans un toast.

### 5. UI : un seul écran `AuthScreen` avec onglets en place

Login et Inscription partagent le **même écran parent** `AuthScreen` qui détient l'état du tab
actif et bascule entre `LoginView` et `RegisterView` via `AnimatedSwitcher`. Pas de
changement de route. `LoginScreen` et `RegisterScreen` ne sont plus que des wrappers minces
qui délèguent à `AuthScreen(initialTab: ...)` pour préserver les routes `/login` et `/register`.

Après inscription réussie, `RegisterView` reçoit un callback `onRegistered` depuis `AuthScreen`
qui bascule l'onglet sur Connexion sans navigation.

### 6. Gestion d'état : `ChangeNotifier` + `provider`

`LoginController` et `RegisterController` étendent `ChangeNotifier` et n'exposent qu'un flag
`isLoading` : leur méthode `submit()` **renvoie** le résultat (`TokenPair`, `User`) et **laisse
remonter** l'exception. Le flux est donc impératif — l'écran `await` l'appel dans son callback,
puis déclenche toast et navigation — et non réactif via un écouteur d'état.

C'est délibéré : un contrôleur qui ne publie que « une requête est en cours » n'a **aucun état
initial ambigu** à distinguer d'un succès. Le flag est lu par `context.watch` pour désactiver le
bouton et afficher un spinner ; le résultat, lui, ne transite jamais par le notifier. Le piège
d'état initial rencontré côté réinitialisation de mot de passe
([ADR 011](011-reinitialisation-mot-de-passe-flutter.md) §3) ne peut structurellement pas se
produire dans ce schéma.

### 7. Notifications : `toastification`

Tous les feedbacks (succès, erreur, info) passent par les helpers
`showAuthSuccessToast` / `showAuthErrorToast` / `showAuthInfoToast`
(`presentation/widgets/auth_toasts.dart`) qui s'appuient sur le package `toastification` posé
en racine de l'app via `ToastificationWrapper` (`app/app.dart`). Tous les toasts précédents
sont dismissés (`dismissAll`) avant d'en afficher un nouveau, pour éviter l'empilement.

---

## Alternatives considérées

### Stocker les tokens avec `shared_preferences`

- **Avantage** : 0 dépendance native supplémentaire.
- **Rejet** : aucun chiffrement par défaut sur Android. Un appareil rooté ou un backup ADB
  exposerait les tokens en clair.

### Refresh token sans sérialisation (chaque 401 → un refresh)

- **Avantage** : code plus simple.
- **Rejet** : la rotation côté serveur invalide l'ancien refresh dès le premier appel. Si N
  requêtes parallèles échouent en 401, seul le premier refresh réussit ; les N-1 autres
  utiliseront le refresh token périmé et échoueront → l'utilisateur est déconnecté à tort.

### Logout serveur synchrone bloquant

- **Avantage** : confirme la révocation côté serveur avant de purger localement.
- **Rejet** : si le serveur est injoignable, l'utilisateur reste « connecté » localement
  alors qu'il a explicitement demandé à se déconnecter. Inacceptable UX. Le best-effort
  garantit qu'un clic sur « Se déconnecter » purge toujours l'état local immédiatement.

### Décodage du JWT côté client pour vérifier l'expiration avant chaque requête

- **Avantage** : éviterait certains 401 inévitables.
- **Rejet** : le serveur reste la source de vérité (clock skew, révocation manuelle, etc.).
  L'intercepteur 401 + refresh couvre déjà le cas. Décoder le JWT côté client serait
  une optimisation prématurée.

### Reuse du refresh token côté client après expiration partielle

- **Avantage** : moins de logout intempestifs.
- **Rejet** : le serveur fait la rotation. Un refresh token déjà consommé est invalidé →
  la seule réponse correcte côté client est de purger et rediriger vers `/login`.

---

## Conséquences

### Avantages

- **Sécurité plateforme** : tokens chiffrés au repos (Keychain iOS / EncryptedSharedPreferences
  Android).
- **Transparence pour le user** : un access token expiré est renouvelé sans interaction.
- **Robustesse réseau** : le logout fonctionne même hors-ligne ; les requêtes parallèles
  partagent un seul refresh.
- **Pas de fuite UI** : le toast d'erreur 401 ne révèle aucun détail technique.

### Inconvénients

- **Refresh token volé reste valide ≤ 7j** : si l'attaquant l'utilise avant le titulaire
  légitime, c'est lui qui obtient une nouvelle paire ; le titulaire est déconnecté au prochain
  refresh (rotation côté serveur). Acceptable au stade actuel.
- **Logout offline laisse le refresh valide en BDD** jusqu'à expiration. Pas une faille en
  pratique car le titulaire a clearé localement, mais à documenter dans le runbook sécurité.
- **Couplage `DioClient` ↔ `SecureStorage`** : difficile à mocker sans un fake dédié. Le test
  unitaire de l'intercepteur reste à écrire (cf. dette).

### Impact sur les tests

- **Repo** : 5 tests `AuthRepositoryImpl` (register, login succès, login 401, logout 3 chemins).
- **Datasource** : couvert indirectement via le repo (mapping HTTP).
- **DioClient (refresh)** : pas de test unitaire — dette assumée, à reprendre dans une US dédiée
  une fois `mocktail` ajouté.
- **Widgets** : `RegisterScreen` couvert ; `LoginView` et `HomeScreen` à couvrir (dette).

---

## Références

- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture par feature.
- [ADR 036](036-state-management-flutter-provider.md) — `provider` + `ChangeNotifier` (supersede l'ADR 005 sur le state management).
- [ADR 006](006-authentification-jwt.md) — Format JWT + rotation refresh côté backend.
- `mobile/lib/core/network/dio_client.dart` — intercepteur auth + refresh sérialisé.
- `mobile/lib/core/storage/secure_storage.dart` — wrapper `flutter_secure_storage`.
- `mobile/lib/features/auth/data/repositories/auth_repository_impl.dart` — login + logout
  best-effort.
- `mobile/lib/features/auth/presentation/screens/auth_screen.dart` — switch onglets en place.
