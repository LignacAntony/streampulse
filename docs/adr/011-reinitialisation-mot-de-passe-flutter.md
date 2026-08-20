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

Les options écartées (Universal Links, copier-coller, QR code) sont détaillées dans
[Alternatives écartées](#alternatives-écartées).

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

### 3. Le résultat de l'action ne transite **pas** par l'état du contrôleur

C'est la décision technique la plus structurante de cette US, et elle vient d'un bug réel.

#### Le problème : un état initial indiscernable d'un succès

Un contrôleur qui publie « l'action a réussi » comme un **état**, et un écran qui **écoute** cet
état pour naviguer, forment un piège : à l'ouverture de l'écran, l'écouteur est branché *avant*
que l'état initial ne soit stabilisé, et il reçoit une première notification qu'il ne sait pas
distinguer d'un succès.

Symptômes observés sur la première implémentation :

- **`ForgotPasswordScreen`** : le toast « email envoyé » s'affichait **à l'ouverture**, puis
  `context.pop()` était appelé dans un état instable.
- **`ResetPasswordScreen`** (ouvert par deep link) : `context.go('/login')` partait dès
  l'ouverture, renvoyant l'utilisateur sur login sans qu'il ait rien soumis.

#### La solution retenue : un contrôleur qui ne publie que `isLoading`

`ForgotPasswordController` et `ResetPasswordController` étendent `ChangeNotifier` et n'exposent
**qu'un seul** état observable — `isLoading` :

```dart
class ForgotPasswordController extends ChangeNotifier {
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Future<void> submit({required String email}) async {
    _isLoading = true;
    notifyListeners();
    try {
      await _repository.requestPasswordReset(email: email);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

Le succès n'est **pas** un état : c'est le retour normal du `Future`. L'échec n'est pas un état
non plus : l'exception remonte. L'écran enchaîne dans son propre callback, là où le geste
utilisateur a eu lieu :

```dart
try {
  await context.read<ForgotPasswordController>().submit(email: ...);
  if (!mounted) return;
  showAuthInfoToast(context, 'Si cet email est enregistré, un lien vous a été envoyé.');
  context.pop();
} catch (error) {
  if (!mounted) return;
  showAuthErrorToast(context, _humanReadable(error));
}
```

**Pourquoi c'est la bonne forme** : le bug n'était pas dans le choix du type d'état, il était
dans le fait de *faire transiter un événement ponctuel* (« ça a marché, navigue ») *par un canal
d'état* (« voici la valeur courante »). Un canal d'état n'a pas de notion de « rien ne s'est
encore passé » qui se distingue toute seule ; il faut la fabriquer. En gardant le résultat dans
le `Future`, la question ne se pose plus : le toast et la navigation ne peuvent partir que depuis
le `await` d'un `onPressed`. Le flag `isLoading`, lui, est un état légitime — il décrit bien
quelque chose de continu.

**Cohérent avec `LoginController` / `RegisterController`**, qui suivent exactement le même
schéma (cf. [ADR 009](009-authentification-flutter.md) §6) : `submit()` **renvoie** le
`TokenPair` ou le `User`, et n'expose que `isLoading`.

> **Note historique (STR-237).** À sa rédaction (2026-05-25), cette section décrivait la même
> décision en vocabulaire **Riverpod**, qui était alors le state management du projet : le bug y
> était formulé comme la transition `AsyncLoading → AsyncData(null)` d'un `AsyncNotifier<void>`,
> interceptée par `ref.listen` au premier microtask, et la correction consistait à passer à
> `AsyncNotifier<bool>` avec `false` comme état initial discriminant.
>
> Riverpod ayant été **interdit** par l'équipe pédagogique, la couche présentation a été migrée
> vers `provider` le 2026-06-04 (`8e912ec`, cf. [ADR 036](036-state-management-flutter-provider.md)) —
> mais cette ADR n'avait jamais été mise à jour. Le texte ci-dessus décrit désormais le code
> réellement livré.
>
> Le raisonnement d'origine, lui, reste valable : il porte sur la distinction entre *état* et
> *événement*, pas sur un framework. Les alternatives ci-dessous ont été réécrites en conséquence.

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

## Alternatives écartées

### Universal Links (iOS) / App Links (Android) plutôt qu'un schéma custom

Plus sûrs — le schéma `streampulse://` peut être revendiqué par n'importe quelle autre app
installée, alors qu'un App Link est vérifié cryptographiquement contre le domaine. Écartés
parce qu'ils **imposent un domaine HTTPS opérationnel** hébergeant `apple-app-site-association`
et `assetlinks.json`, qui n'existe pas encore. Bloquer une feature d'authentification sur une
dépendance infra non livrée n'est pas justifiable ; à reconsidérer quand le domaine de
production sera actif (cf. Inconvénients).

### Copier-coller manuel du token depuis l'email

Zéro configuration native, fonctionne partout. Écarté sur l'UX : demander à l'utilisateur de
sélectionner une chaîne de 64 caractères hexadécimaux dans un email, puis de la coller dans un
champ, sur mobile, garantit un taux d'abandon élevé sur un parcours déjà subi.

### QR code dans l'email

Écarté sur un cas d'usage dirimant : l'email de réinitialisation est le plus souvent ouvert
**sur le téléphone lui-même** — l'utilisateur ne peut pas scanner son propre écran. Coût de
génération côté backend en prime.

### Publier le résultat de l'action comme un **état** du contrôleur

C'est l'implémentation d'origine, et la cause du bug décrit en §3 : un canal d'état ne
distingue pas « rien ne s'est encore passé » d'un succès, donc l'écouteur navigue à
l'ouverture de l'écran. Deux correctifs ont été envisagés puis écartés :

- **Ajouter une valeur initiale discriminante** (un `bool false`, un enum `Idle`/`Success`) et
  garder l'écran à l'écoute. Ça marche, mais chaque nouvel écran doit se souvenir d'écrire la
  garde — un oubli redonne exactement le même bug, sans erreur de compilation.
- **Comparer l'état précédent** dans l'écouteur pour ignorer la première notification. Écarté :
  la sémantique de « première notification » dépend du moment où l'écouteur a été branché, donc
  du cycle de vie du widget — un détail d'implémentation, non garanti par contrat.

Garder le résultat dans le `Future` supprime la classe de bugs au lieu de la contourner.

### `ResetPasswordScreen` accessible aussi depuis la navigation normale

Un écran « j'ai déjà un token » atteignable depuis le menu aurait offert un plan B si le deep
link échoue. Écarté : cela suppose d'exposer un champ « collez votre token ici », ce que la
première alternative rejette déjà, et ajoute une route publique qui ne sert qu'à contourner un
dysfonctionnement — la bonne réponse à un deep link cassé est une page web de fallback, pas un
écran de saisie manuelle.

---

## Conséquences

### Avantages

- **UX fluide** : clic sur le lien email → app ouverte directement sur le bon écran, token pré-rempli.
- **Pas de régression** : les deux contrôleurs suivent le même schéma que `LoginController` (résultat renvoyé, seul `isLoading` publié) — la codebase est homogène.
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

- [ADR 005](005-architecture-flutter-clean.md) — Clean Architecture par feature
- [ADR 036](036-state-management-flutter-provider.md) — `provider` + `ChangeNotifier` (supersede l'ADR 005 sur le state management)
- [ADR 009](009-authentification-flutter.md) — Contrôleurs d'auth, toasts, navigation
- [ADR 010](010-reinitialisation-mot-de-passe-backend.md) — Sécurisation côté backend
- `mobile/lib/features/auth/presentation/screens/forgot_password_screen.dart`
- `mobile/lib/features/auth/presentation/screens/reset_password_screen.dart`
- `mobile/lib/features/auth/presentation/providers/forgot_password_controller.dart`
- `mobile/lib/features/auth/presentation/providers/reset_password_controller.dart`
- `mobile/lib/app/router/app_router.dart`
- `mobile/android/app/src/main/AndroidManifest.xml`
- `mobile/ios/Runner/Info.plist`
- Linear : [STR-58](https://linear.app/streampulse/issue/STR-58)
