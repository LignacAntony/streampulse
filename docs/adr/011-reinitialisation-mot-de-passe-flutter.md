# ADR 011 — Réinitialisation de mot de passe : deep links et gestion d'état Flutter

**Date** : 2026-05-25  
**Statut** : Accepté  
**Ticket** : [STR-58](https://linear.app/streampulse/issue/STR-58)

---

## Contexte

STR-58 demande les écrans Flutter pour le workflow de réinitialisation de mot de passe. Deux sous-problèmes distincts doivent être résolus :

**Problème 1 — Ouverture de l'app depuis l'email.**  
Le lien dans l'email doit ouvrir directement l'écran `ResetPasswordScreen` avec le token en paramètre. L'utilisateur ne doit pas avoir à copier le token manuellement.

**Problème 2 — Gestion d'état des contrôleurs.**  
Les deux contrôleurs (`ForgotPasswordController`, `ResetPasswordController`) doivent déclencher navigation et toast **uniquement** après une action utilisateur, jamais à l'ouverture de l'écran.

---

## Décision

### 1. Deep links avec un schéma URL custom (`streampulse://`)

Un **deep link** est une URL qui ouvre directement une app mobile sur un écran précis. Deux approches coexistent sur iOS et Android :

| Approche | Schéma | Mécanisme | Vérification requise |
|---|---|---|---|
| **Custom URL scheme** | `streampulse://` | Enregistrement dans Manifest / Info.plist | Non |
| **Universal links (iOS) / App Links (Android)** | `https://streampulse.com` | Fichier `.well-known/apple-app-site-association` sur le domaine | Oui |

Nous avons choisi le **schéma custom `streampulse://app`**.

**Configuration Android** (`AndroidManifest.xml`) :
```xml
<intent-filter android:autoVerify="false">
    <action android:name="android.intent.action.VIEW"/>
    <category android:name="android.intent.category.DEFAULT"/>
    <category android:name="android.intent.category.BROWSABLE"/>
    <data android:scheme="streampulse" android:host="app"/>
</intent-filter>
```

**Configuration iOS** (`Info.plist`) :
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array><string>streampulse</string></array>
    </dict>
</array>
```

**Pourquoi le schéma custom plutôt que les Universal Links** :

- Universal Links nécessitent un **domaine HTTPS opérationnel** hébergeant un fichier `apple-app-site-association` (iOS) et `assetlinks.json` (Android). À ce stade du projet, le domaine de production n'est pas encore configuré ; bloquer la feature sur cette dépendance infra n'est pas justifié.
- Universal Links offrent un meilleur fallback (s'ouvre dans le navigateur si l'app n'est pas installée), mais pour un lien de réinitialisation de mot de passe, un fallback vers un site web n'a pas de valeur — l'utilisateur doit avoir l'app.
- Un schéma custom fonctionne **hors connexion** et **sans configuration serveur**. C'est la solution correcte pour les deep links internes à une app mobile sans besoin de fallback web.

**Alternative rejetée — Universal Links / App Links** : plus sécurisée (le schéma `streampulse://` peut être usurpé par une autre app qui enregistre le même schéma), mais impose une infrastructure domaine HTTPS opérationnelle dès maintenant. À reconsidérer quand le domaine production sera actif.

**Alternative rejetée — copier-coller du token dans l'app** : l'utilisateur devrait copier le token depuis l'email et le coller dans un champ de l'app. Expérience utilisateur inacceptable.

**Alternative rejetée — QR code dans l'email** : complexifie la génération du mail côté backend, ne fonctionne pas si l'email est ouvert sur le même téléphone que l'app (l'utilisateur ne peut pas scanner son propre écran).

### 2. Parsing du token dans go_router

Le token est extrait des query parameters de l'URL dans le router :

```dart
GoRoute(
    path: '/reset-password',
    builder: (context, state) {
        final token = state.uri.queryParameters['token'] ?? '';
        return ResetPasswordScreen(token: token);
    },
),
```

`go_router` reçoit l'URL du deep link via le plugin `uni_links` (intégré dans Flutter). Si le token est absent ou vide, `ResetPasswordScreen` affiche une vue `_InvalidTokenView` au lieu du formulaire — évite un crash ou une requête API avec un token vide.

### 3. `AsyncNotifier<bool>` plutôt que `AsyncNotifier<void>`

C'est la décision technique la plus structurante de cette US.

#### Le bug avec `AsyncNotifier<void>`

Les contrôleurs de la première implémentation héritaient de `AsyncNotifier<void>` :

```dart
class ForgotPasswordController extends AsyncNotifier<void> {
    @override
    Future<void> build() async {}  // ← problème ici
}
```

`build()` est **asynchrone**. Riverpod démarre le provider en état `AsyncLoading`, puis dès que `build()` se termine (au microtask suivant), l'état passe à `AsyncData(null)`.

Or, `ref.listen` est enregistré **pendant la phase de build du widget**, c'est-à-dire **avant** que ce microtask soit traité. La transition `AsyncLoading → AsyncData(null)` est donc interceptée par le listener immédiatement à l'ouverture de l'écran — avant tout geste utilisateur.

Résultat observé :
- **`ForgotPasswordScreen`** : le toast "email envoyé" s'affichait à l'ouverture, puis `context.pop()` était appelé dans un état instable.
- **`ResetPasswordScreen`** (ouvert via deep link) : `context.go('/login')` était appelé dès l'ouverture, renvoyant l'utilisateur sur login sans qu'il ait soumis le formulaire.

#### La correction avec `AsyncNotifier<bool>`

```dart
class ForgotPasswordController extends AsyncNotifier<bool> {
    @override
    Future<bool> build() async => false;  // état initial stable et discriminant
}
```

L'état initial est `AsyncData(false)`. La transition `AsyncLoading → AsyncData(false)` est bien interceptée par le listener, mais le callback peut maintenant **distinguer l'état initial** :

```dart
void _onStateChanged(AsyncValue<bool>? previous, AsyncValue<bool> next) {
    next.when(
        data: (sent) {
            if (!sent) return;  // false = état initial → ignorer
            if (!context.mounted) return;
            showAuthInfoToast(context, '...');
            context.pop();
        },
        ...
    );
}
```

**Pourquoi `bool` et pas `int` ou un enum** : le cycle de vie de ces contrôleurs est binaire — soit aucune action n'a encore été effectuée (`false`), soit l'action a réussi (`true`). Un bool est le type le plus simple et le plus expressif pour ce cas. Un enum (`Idle`, `Success`) serait surdimensionné.

**Pourquoi ne pas comparer `previous`** : on pourrait écrire `if (previous?.value == next.value) return;` mais cela est fragile — la comparaison de `AsyncValue` avec `==` peut être piégée par les cas d'égalité structurelle. La garde `if (!value) return;` est explicite, testable, et ne dépend pas du `previous`.

**Ce pattern est cohérent avec `LoginController`** qui utilise `AsyncNotifier<TokenPair?>` avec `if (tokens == null) return;` comme garde sur l'état initial.

**Alternative rejetée — `AsyncNotifier<void>` avec comparaison de `previous`** : `if (previous == null) return;` semble fonctionner mais `previous` est `null` uniquement lors du **premier** fire du listener (transition depuis l'état initial qui n'existait pas encore). Ce comportement dépend d'un détail d'implémentation de Riverpod et n'est pas documenté comme garanti.

**Alternative rejetée — `KeepAliveLink` / `ref.keepAlive()`** : maintenir le provider en vie éviterait la réinitialisation du `build()` à chaque ouverture de l'écran, mais ce serait une optimisation prématurée qui masque le vrai problème plutôt que de le corriger.

**Alternative rejetée — `StateNotifier<bool>` classique** : `AsyncNotifier` est le pattern recommandé par Riverpod 2.x pour les opérations asynchrones. `StateNotifier` ne gère pas nativement les états `loading`/`error` — il faudrait les gérer manuellement.

### 4. Deux écrans dédiés (`ForgotPasswordScreen`, `ResetPasswordScreen`)

Les deux étapes du workflow sont sur des écrans séparés avec des routes distinctes :

```
/forgot-password  →  ForgotPasswordScreen
/reset-password   →  ResetPasswordScreen (accessible uniquement via deep link)
```

**Pourquoi deux écrans et non un seul avec état interne** : les deux étapes ont des points d'entrée différents. `ForgotPasswordScreen` est atteint depuis le bouton "Mot de passe oublié ?" sur l'écran de login. `ResetPasswordScreen` est atteint exclusivement via deep link depuis l'email — il ne peut pas être dans le flow de navigation normal de l'app.

**Pourquoi `context.push('/forgot-password')` et non `context.go`** : `push` empile l'écran sur la navigation, ce qui permet à `context.pop()` de revenir sur login après l'envoi de l'email. `go` remplacerait la stack et priverait l'utilisateur du retour arrière.

**Pourquoi les deux routes sont dans `_publicRoutes`** : ces routes doivent être accessibles sans être connecté. L'utilisateur qui réinitialise son mot de passe n'a, par définition, pas de token valide.

### 5. Validation identique à l'inscription

`ResetPasswordValidators` délègue à `RegisterValidators` :

```dart
class ResetPasswordValidators {
    static String? password(String? raw) => RegisterValidators.password(raw);
    static String? confirmPassword(String? raw, String original) =>
        RegisterValidators.confirmPassword(raw, original);
}
```

**Pourquoi déléguer** : les règles métier (8–72 caractères) doivent être identiques à l'inscription. Si demain la contrainte change (ex. : 10 caractères minimum), modifier `RegisterValidators` suffira. Dupliquer la logique créerait une divergence silencieuse entre les deux formulaires.

La limite à **72 caractères** n'est pas arbitraire : bcrypt tronque silencieusement les entrées dépassant 72 bytes. Un mot de passe de 73 caractères serait accepté côté UI mais haché de façon identique à un mot de passe de 72 caractères, ce qui casserait la vérification.

---

## Conséquences

### Avantages

- **UX fluide** : clic sur le lien email → app ouverte directement sur le bon écran, token pré-rempli.
- **Pas de régression** : le pattern `AsyncNotifier<bool>` est cohérent avec `LoginController` — la codebase est homogène.
- **Règles de validation centralisées** : une seule source de vérité pour les contraintes de mot de passe.

### Inconvénients

- **Schéma custom interceptable** : n'importe quelle app Android/iOS peut théoriquement enregistrer `streampulse://`. En pratique, l'utilisateur voit une dialog qui lui demande quelle app ouvrir — il choisit StreamPulse. À migrer vers Universal Links quand le domaine production sera disponible.
- **`ResetPasswordScreen` inaccessible manuellement** : pas de lien depuis le menu — uniquement via deep link. Si l'utilisateur n'a pas l'app et clique sur le lien depuis un navigateur desktop, rien ne se passe. À adresser avec une page web de fallback en production.

### Impact sur les tests

- `auth_repository_impl_test.dart` : stubs des nouvelles méthodes.
- `register_screen_test.dart` : `_FakeAuthRepository` implémente les stubs pour compiler.
- Tests widget des deux nouveaux écrans : à écrire (dette assumée).

---

## Références

- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture + Riverpod
- [ADR 009](009-authentification-flutter.md) — Pattern `AsyncNotifier`, toasts, navigation
- [ADR 010](010-reinitialisation-mot-de-passe-backend.md) — Sécurisation côté backend
- `mobile/lib/features/auth/presentation/screens/forgot_password_screen.dart`
- `mobile/lib/features/auth/presentation/screens/reset_password_screen.dart`
- `mobile/lib/features/auth/presentation/providers/forgot_password_controller.dart`
- `mobile/lib/features/auth/presentation/providers/reset_password_controller.dart`
- `mobile/lib/app/router/app_router.dart`
- `mobile/android/app/src/main/AndroidManifest.xml`
- `mobile/ios/Runner/Info.plist`
- Linear : [STR-58](https://linear.app/streampulse/issue/STR-58)
