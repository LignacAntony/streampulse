# Cahier de recette — StreamPulse

**Version** : 1.0 · **Rédigé le** : 2026-08-19 · **Ticket** : [STR-236](https://linear.app/streampulse/issue/STR-236)
**Base de référence** : branche `develop`, commit `ceb79c3`
**Périmètre** : API Go (`backend/`) et application mobile Flutter (`mobile/`)

Ce document définit les scénarios de recette de StreamPulse : pour chacun, ses préconditions,
ses étapes, le résultat attendu, **l'état réel de sa vérification** et l'exigence utilisateur
qu'il couvre. Il est la référence des tests fonctionnels du projet ; les suites automatisées lui
servent de preuve, pas d'alibi.

Il complète, sans les remplacer :

- les **ADR** (`docs/adr/`) — décisions d'architecture et critères d'acceptation détaillés ;
- la **spec OpenAPI** (`backend/internal/openapi/openapi.yaml`) — contrat HTTP, source de vérité ;
- les **suites de tests**, citées par fichier **et** nom de fonction en regard de chaque scénario.

---

## 1. Convention de lecture — à lire avant le reste

Un scénario marqué « Vérifié » l'a réellement été. Un scénario marqué « À exécuter » ne l'a pas
été et ne prétend rien. **Aucun résultat n'est reporté ici sans preuve rejouable.**

| Statut | Ce qu'il signifie exactement | Colonnes « obtenu » / « date » |
|---|---|---|
| ✅ **Vérifié** | Un test automatisé verrouille le scénario, il est cité par fichier **et** nom de fonction, et il a été **exécuté au vert** le 2026-08-19 par `go test ./...` / `flutter test`. Rejoué à chaque CI (`.github/workflows/ci.yml`). | renseignées |
| 🟡 **Automatisé, non rejoué** | Un test existe et est cité, mais il est **hors de la suite par défaut** — build tag (`integration`, `loadtest`) ou branche non fusionnée dans `develop`. Il n'a **pas** été relancé le 2026-08-19. | date = dernier run connu, ou vide |
| ⬜ **À exécuter** | **Aucun test automatisé** ne couvre le scénario : passage manuel requis. | **vides, par construction** |

### Ce que « Vérifié » ne dit pas

- Les tests Go de `handler`/`service` s'exécutent contre des stubs et des `fakeRepo` **en
  mémoire**. Ils verrouillent le comportement HTTP et la logique métier, **pas le SQL réel**.
  Seuls les tests taggés `integration` touchent un vrai PostgreSQL — ils sont en 🟡 (cf. §2).
- Les tests Flutter s'exécutent sur le runtime de test, **pas sur un appareil**. Tout ce qui
  dépend du matériel ou de l'OS — microphone, lecture en arrière-plan, notification système,
  deep link, permissions — est en ⬜ et ne peut pas être fermé autrement qu'à la main.
- Un test unitaire vert ne prouve pas le **câblage** de `backend/cmd/api/main.go`. Un test peut
  *reproduire* un montage (REC-AUD-02 appelle le handler sans `RequireAuth`, exactement comme
  `main.go:250`), il ne lit pas `main.go` pour autant : déplacer la route sous `RequireAuth` sans
  toucher au test ne serait pas détecté. Les scénarios concernés le disent dans leur colonne
  « résultat obtenu ».

### Répartition

| Section | ✅ Vérifié | 🟡 Non rejoué | ⬜ À exécuter | Total |
|---|---|---|---|---|
| §3 Compte et session | 17 | 0 | 3 | 20 |
| §4 Auditeur | 15 | 0 | 2 | 17 |
| §5 Bibliothèque et playlists | 22 | 0 | 2 | 24 |
| §6 Diffuseur | 20 | 0 | 3 | 23 |
| §7 Administrateur | 11 | 1 | 1 | 13 |
| §8 Sécurité transverse | 16 | 3 | 2 | 21 |
| §9 Performance et charge | 0 | 5 | 1 | 6 |
| **Total** | **101** | **9** | **14** | **124** |

---

## 2. Campagne de référence

| Suite | Commande | Résultat | Date |
|---|---|---|---|
| Backend Go | `cd backend && go test ./... -count=1` | **420 fonctions `Test*`, 528 cas sous-tests inclus — 100 % au vert** | 2026-08-19 |
| Mobile Flutter | `cd mobile && flutter test` | **415 tests — 100 % au vert** | 2026-08-19 |
| Repository admin (intégration) | `cd backend && go test -tags integration ./internal/admin/... -run TestRepository` | **non rejoué** — exige un PostgreSQL ; le daemon Docker n'était pas disponible sur le poste de recette | — |
| Charge HLS | `make loadtest` (exige ffmpeg) | cf. §9 — dernier run connu **2026-08-18** | 2026-08-18 |

Poste de recette : macOS 25.5 (Apple Silicon), Go ≥ 1.22, Flutter ≥ 3.22, ffmpeg 8.1.2.

### Jeu de données

`docker compose up -d` amorce le seeder (`backend/internal/infrastructure/seeder/users.go`).
Comptes disponibles pour les passages manuels, mot de passe **`Password123!`** :

| Compte | Rôle |
|---|---|
| `admin@streampulse.dev` | `admin` |
| `broadcaster@streampulse.dev` | `broadcaster` |
| `user1@streampulse.dev` · `user2@streampulse.dev` | `user` |

Deux comptes `user` distincts sont **nécessaires** : tous les scénarios d'isolation (§8) exigent
un tiers. Les emails de développement sont consultables dans Mailpit (http://localhost:8025).

---

## 3. Compte et session — `REC-CPT`

Rôles concernés : **tous**. Routes : `/api/auth/*`, `/api/users/me`.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-CPT-01 | Email libre | `POST /api/auth/register` avec email, pseudo et mot de passe valides | 201, compte créé, paire de jetons renvoyée | Conforme — `backend/internal/auth/handler_test.go` `TestHandler_Register_Created` ; `auth/service_test.go` `TestRegister_HappyPath` | ✅ | 2026-08-19 | ADR 006 · STR-38 |
| REC-CPT-02 | Email déjà enregistré | `POST /api/auth/register` avec le même email | 409, aucun doublon créé | Conforme — `TestHandler_Register_Conflict` ; `TestRegister_DuplicateEmail` | ✅ | 2026-08-19 | ADR 006 |
| REC-CPT-03 | — | `POST /api/auth/register` avec un corps invalide ou des champs hors bornes | 400, erreur exploitable ; méthode non autorisée → 405 | Conforme — `TestHandler_Register_InvalidJSON` ; `TestHandler_Register_MethodNotAllowed` ; `TestRegister_InvalidInput` | ✅ | 2026-08-19 | ADR 006 |
| REC-CPT-04 | Compte actif existant | `POST /api/auth/login` avec les bons identifiants | 200 + access token (HS256, 15 min, claims `sub`/`role`) et refresh token | Conforme — `TestHandler_Login_OK` ; `TestLogin_HappyPath` | ✅ | 2026-08-19 | US-02-01 |
| REC-CPT-05 | Compte actif existant | `POST /api/auth/login` avec un mauvais mot de passe | 401 et message **générique** — aucune indication sur l'existence du compte | Conforme — `TestHandler_Login_Unauthorized` ; `TestLogin_InvalidCredentials` | ✅ | 2026-08-19 | US-02-01 · ADR 009 |
| REC-CPT-06 | Refresh token valide | `POST /api/auth/refresh` | 200, **nouvelle** paire ; l'ancien refresh est révoqué (rotation) | Conforme — `TestHandler_Refresh_OK` ; `TestRefresh_HappyPath` ; `TestHandler_Refresh_MissingToken` | ✅ | 2026-08-19 | US-02-01 · ADR 006 |
| REC-CPT-07 | Refresh token déjà consommé | Rejouer `POST /api/auth/refresh` avec ce même jeton | Refus — un refresh token n'est utilisable qu'une fois | Conforme — `auth/service_test.go` `TestRefresh_TokenReuse_Rejected` | ✅ | 2026-08-19 | ADR 006 |
| REC-CPT-08 | Session ouverte | `POST /api/auth/logout`, puis rejouer avec un jeton inconnu | 204 ; le second appel est **idempotent** | Conforme — `TestHandler_Logout_OK` ; `TestLogout_HappyPath` ; `TestLogout_UnknownToken_IsIdempotent` | ✅ | 2026-08-19 | ADR 006 · ADR 009 |
| REC-CPT-09 | Compte existant | `POST /api/auth/forgot-password` avec un email connu | 200 ; jeton stocké **haché**, email envoyé | Conforme — `TestHandler_ForgotPassword_OK` ; `TestForgotPassword_KnownEmail_StoresToken` ; `TestForgotPassword_ReplacesExistingToken` | ✅ | 2026-08-19 | ADR 010 · STR-54 |
| REC-CPT-10 | — | `POST /api/auth/forgot-password` avec un email **inconnu**, puis malformé | **Même réponse** que pour un email connu — pas d'énumération de comptes | Conforme — `TestForgotPassword_UnknownEmail_ReturnsNil` ; `TestForgotPassword_InvalidEmail_ReturnsNil` | ✅ | 2026-08-19 | ADR 010 |
| REC-CPT-11 | Jeton de réinitialisation valide | `POST /api/auth/reset-password` | Mot de passe changé **et toutes les sessions révoquées** | Conforme — `TestResetPassword_HappyPath` ; `TestResetPassword_RevokesAllRefreshTokens` | ✅ | 2026-08-19 | ADR 010 |
| REC-CPT-12 | Jeton invalide, expiré, déjà utilisé | `POST /api/auth/reset-password` pour les trois cas | Refus dans les trois cas ; jeton à usage unique | Conforme — `TestResetPassword_InvalidToken_Errors` ; `TestResetPassword_ExpiredToken_Errors` ; `TestResetPassword_UsedToken_Errors` | ✅ | 2026-08-19 | ADR 010 |
| REC-CPT-13 | Jeton valide | `POST /api/auth/reset-password` avec un mot de passe trop court | Refus, mot de passe inchangé | Conforme — `TestResetPassword_ShortPassword_Errors` | ✅ | 2026-08-19 | ADR 010 |
| REC-CPT-14 | Compte authentifié possédant des pistes | `DELETE /api/auth/me` avec le bon mot de passe | 204 ; cascade en base **et** purge des fichiers audio du volume, seulement si le delete a réussi | Conforme — `TestHandler_DeleteAccount_NoContent` ; `TestDeleteAccount_HappyPath` ; `TestService_DeleteAccount_PurgesTracks` | ✅ | 2026-08-19 | `openapi.yaml` `deleteAccount` (RGPD art. 17) · ADR 032 |
| REC-CPT-15 | Compte authentifié | `DELETE /api/auth/me` avec un mauvais mot de passe, puis sans mot de passe | Refus dans les deux cas, compte intact | Conforme — `TestDeleteAccount_WrongPassword` ; `TestDeleteAccount_EmptyPassword` ; `TestHandler_DeleteAccount_MissingPassword` | ✅ | 2026-08-19 | idem |
| REC-CPT-16 | Session ouverte | `GET` puis `PUT /api/users/me` (pseudo, bio, préférences), puis `GET` sans jeton | Lecture et mise à jour du profil ; 400 si champ requis absent ; 401 sans jeton | Conforme — `backend/internal/profiles/handler_test.go` `TestHandler_GetMe_OK`, `TestHandler_UpdateMe_AllFieldsOK`, `TestHandler_UpdateMe_MissingRequiredField`, `TestHandler_Me_RequiresToken` | ✅ | 2026-08-19 | ADR 012 · STR-44 |
| REC-CPT-17 | Application mobile lancée | Écran d'inscription : soumettre sans cocher les CGU, avec une confirmation divergente, puis avec un email déjà pris | Bouton neutralisé sans CGU ; erreurs de validation affichées ; toast serveur sur 409 | Conforme — `mobile/test/features/auth/presentation/screens/register_screen_test.dart` ; `.../utils/register_validators_test.dart` | ✅ | 2026-08-19 | US-02-01 · ADR 009 |
| REC-CPT-18 | Stack lancée, compte `user1` | Parcours mot de passe oublié depuis le mobile : demande → email Mailpit → **deep link** `streampulse://app/reset-password?token=…` → nouveau mot de passe → reconnexion | L'app s'ouvre sur l'écran de réinitialisation ; la reconnexion réussit avec le nouveau mot de passe | | ⬜ | | ADR 011 · STR-58 |
| REC-CPT-19 | Session ouverte, access token expiré (> 15 min) | Déclencher plusieurs appels authentifiés simultanés depuis le mobile | Rafraîchissement transparent, **un seul** refresh en vol pour N requêtes 401 parallèles ; échec du refresh → purge des jetons et retour à l'écran de connexion | | ⬜ | | ADR 009 |
| REC-CPT-20 | Jetons stockés sur un device réel | Inspecter le magasin (Keychain iOS / EncryptedSharedPreferences Android) | Les jetons ne sont pas lisibles en clair hors du magasin sécurisé | | ⬜ | | ADR 009 |

---

## 4. Auditeur — `REC-AUD`

Rôle : **auditeur** (invité ou `user`). Routes : `/api/streams`, `playlist.m3u8`, `segments/*`,
`events`, favoris.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-AUD-01 | Au moins un flux public en direct | `GET /api/streams` avec une session | 200, liste des directs publics ; **aucun secret** (`stream_key`, `stream_source_url`) dans la réponse | Conforme — `backend/internal/streaming/handler_test.go` `TestHandler_List_OK_NoStreamKey` | ✅ | 2026-08-19 | US-04-01 · ADR 013 |
| REC-AUD-02 | Idem, aucune session | `GET /api/streams` **sans jeton** (route montée publiquement dans `cmd/api/main.go`) | 200, même liste — découverte accessible en invité | Conforme — `TestHandler_List_AnonymousOK` : montage public (sans `RequireAuth`, comme `main.go`), aucun en-tête `Authorization`, 200 + aucun secret, et corps **identique** à l'appel authentifié | ✅ | 2026-08-20 | US-04-01 · `openapi.yaml` `listStreams` |
| REC-AUD-03 | Plus de 100 flux en direct | `GET /api/streams?limit=999&offset=-5` | Bornes appliquées : `limit` plafonné à 100, `offset` négatif ramené à 0 | Conforme — `TestHandler_List_PaginationClamp` | ✅ | 2026-08-19 | ADR 013 |
| REC-AUD-04 | Flux public en direct et prêt | `GET /api/streams/{id}/playlist.m3u8` sans jeton, puis en tant que propriétaire d'un flux **privé** | 200 dans les deux cas (chaîne `OptionalAuth` réelle) | Conforme — `TestHandler_Playlist_PublicNoAuth` ; `TestHandler_Playlist_ViaOptionalAuth` | ✅ | 2026-08-19 | US-04-02 · STR-108 |
| REC-AUD-05 | Manifeste obtenu | `GET /api/streams/{id}/segments/{segment}` sans jeton | 200, segment `.ts` servi | Conforme — `TestHandler_Segment_PublicNoAuth` | ✅ | 2026-08-19 | US-04-02 · STR-108 |
| REC-AUD-06 | Flux non live, ou live mais segmenteur pas encore prêt (~10 s) | `GET /api/streams/{id}/playlist.m3u8` | **409 JSON** (et non une page HTML ou un 500) | Conforme — `TestHandler_Playlist_NotReadyReturnsJSON409` | ✅ | 2026-08-19 | ADR 015 · ADR 023 |
| REC-AUD-07 | `HLS_MAX_CONCURRENT` atteint | Requêtes playlist et segment au-delà de la capacité | **503** `server_overloaded` + `Retry-After: 2`, sans file d'attente ; budget **partagé** playlist/segments ; `0` désactive la borne | Conforme — `backend/internal/streaming/limiter_test.go` `TestNewMaxInFlight_RejetAuDelaDeLaLimite`, `TestNewMaxInFlight_BudgetPartage`, `TestNewMaxInFlight_Desactive` | ✅ | 2026-08-19 | STR-88 · ADR 016 |
| REC-AUD-08 | Flux en direct, auditeur abonné | `GET /api/streams/{id}/events` (SSE), puis le diffuseur arrête le flux | Événement `ended` reçu puis fermeture propre ; flux non live → 409 ; sans jeton → 401 ; abonné lent → fermeture quand même | Conforme — `TestHandler_Events_StreamsEndedThenCloses`, `TestHandler_Events_NotLive_Conflict`, `TestHandler_Events_RequiresToken` ; `session_test.go` `TestLiveSessions_SubscribeReceivesEnded`, `TestLiveSessions_SlowSubscriberStillCloses` | ✅ | 2026-08-19 | STR-77 · ADR 013 |
| REC-AUD-09 | Flux public visible, ou flux privé dont on est propriétaire | `PUT /api/streams/{id}/favorite`, deux fois | 204 les deux fois — **idempotent** | Conforme — `TestHandler_AddFavorite_NoContent` ; `service_test.go` `TestService_AddFavorite_PublicOK`, `TestService_AddFavorite_OwnPrivateOK` | ✅ | 2026-08-19 | US-04-05 |
| REC-AUD-10 | Flux en favori | `DELETE /api/streams/{id}/favorite`, deux fois | 204 les deux fois ; aucun contrôle de visibilité au retrait (on peut toujours se retirer) | Conforme — `TestHandler_RemoveFavorite_NoContent` ; `TestService_RemoveFavorite_NoVisibilityCheck` | ✅ | 2026-08-19 | US-04-05 |
| REC-AUD-11 | Quelques favoris enregistrés | `GET /api/users/me/favorites`, puis sans jeton | Liste tous statuts confondus, visibles et non archivés, **sans secret** ; 401 sans jeton | Conforme — `TestHandler_ListFavorites_OK`, `TestHandler_ListFavorites_Unauthenticated` ; `TestService_ListFavorites` | ✅ | 2026-08-19 | US-04-05 |
| REC-AUD-12 | Lecture démarrée puis flux coupé | Observer le lecteur mobile : manifeste disparu, coupure réseau, flux jamais prêt | Reconnexion **bornée** (1/2/4/8 s) ; `ended` seulement si la lecture avait démarré ; sinon `error` après épuisement ; `stop()` retire la notification | Conforme — `mobile/test/features/streams/presentation/providers/audio_player_controller_test.dart` | ✅ | 2026-08-19 | US-04-02 · STR-118 · ADR 023 |
| REC-AUD-13 | Flux en lecture | Appel entrant, notification, débranchement du casque | Appel → pause puis reprise si c'est nous qui avions mis en pause ; notification → duck/unduck ; casque débranché → pause **sans** reprise | Conforme — `mobile/test/core/audio/interruption_policy_test.dart` | ✅ | 2026-08-19 | US-04-04 · STR-110 · ADR 033 |
| REC-AUD-14 | Direct en lecture, file d'attente inactive (et inversement) | Lancer une file pendant un direct, puis un direct pendant une file | Un seul lecteur : le direct est arrêté au lancement d'une file ; la file est vidée sans couper le direct à l'inverse ; le bandeau affiche la bonne source | Conforme — `mobile/test/app/shell/player_bar_test.dart` ; `mobile/test/features/streams/presentation/widgets/mini_player_test.dart` | ✅ | 2026-08-19 | US-05-04 · ADR 034 |
| REC-AUD-15 | Liste des flux ouverte | Chargement initial, rafraîchissement, pagination, armement du polling | Les trois chemins renseignent l'état sans écrasement concurrent ; le polling ne s'arme que quand il sert | Conforme — `mobile/test/features/streams/presentation/providers/stream_notifier_test.dart` ; `favorites_controller_test.dart` | ✅ | 2026-08-19 | US-04-01 · US-04-05 |
| REC-AUD-16 | Device physique, flux en lecture | Verrouiller l'écran, passer en arrière-plan, piloter depuis la notification système | La lecture continue ; les contrôles de la notification agissent sur le lecteur | | ⬜ | | US-04-03 · STR-109 · ADR 031 |
| REC-AUD-17 | Stack lancée, un diffuseur pousse réellement de l'audio | Écouter le flux depuis l'application mobile de bout en bout | Le son est audible, sans coupure, avec une latence conforme à la segmentation (~10 s) | | ⬜ | | US-04-02 · ADR 015 |

---

## 5. Bibliothèque et playlists — `REC-BIB`

Rôle : **utilisateur connecté** (`user` suffit). Routes : `/api/tracks*`, `/api/playlists*`.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-BIB-01 | Session ouverte | `POST /api/tracks` multipart (`file` MP3/AAC/OGG + `title`) | 201 ; fichier écrit sous `STORAGE_PATH`, piste référencée en base | Conforme — `backend/internal/track/handler_test.go` `TestUpload_OK` ; `track/service_test.go` `TestCreate_OK` | ✅ | 2026-08-19 | US-05-01 · STR-130 |
| REC-BIB-02 | Session ouverte | `POST /api/tracks` sans fichier, puis sans titre, puis sans jeton | 400, 400, 401 | Conforme — `TestUpload_MissingFile` ; `TestCreate_EmptyTitle` ; `TestUpload_Unauthenticated` | ✅ | 2026-08-19 | US-05-01 |
| REC-BIB-03 | Session ouverte | `POST /api/tracks` avec un fichier au-dessus de la borne (50 Mo en production) | **413** | Conforme — `TestUpload_TooLarge` | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-BIB-04 | Session ouverte | `POST /api/tracks` avec un **PDF renommé `.mp3`** | **415** ; rien n'est écrit ni persisté (MIME sniffé côté serveur) | Conforme — `TestUpload_RejectsDisguisedFile` ; `TestCreate_RejectsNonAudio` | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-BIB-05 | Compte au quota (`MaxUserStorageBytes` = 500 Mo) | `POST /api/tracks` avec un audio valide | **403** `storage_quota_exceeded` (et non 507 : condition client, hors bucket 5xx) ; rien n'est stocké | Conforme — `TestCreate_QuotaExceeded` | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-BIB-06 | Compte au quota | `POST /api/tracks` avec un **non-audio** | **415** et non 403 — le bon diagnostic prime | Conforme — `TestCreate_NonAudioWinsOverQuota` | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-BIB-07 | Session ouverte | Upload avec `duration_s` ≤ 0, puis démesurée, puis fichier vide | Refus dans les trois cas | Conforme — `TestCreate_InvalidDuration` ; `TestCreate_DurationTooLarge` ; `TestCreate_EmptyFile` | ✅ | 2026-08-19 | US-05-01 |
| REC-BIB-08 | Écriture du fichier réussie, insertion en base en échec | Upload provoquant une erreur repository | Le fichier écrit est **supprimé** — pas d'orphelin sur le volume | Conforme — `TestCreate_RemovesOrphanOnRepoError` | ✅ | 2026-08-19 | ADR 032 |
| REC-BIB-09 | Une piste au titre `T` existe déjà pour ce compte | `POST /api/tracks` avec le même titre | **409** (contrainte `uq_tracks_user_title`) | | ⬜ | | US-05-01 · `openapi.yaml` `uploadTrack` |
| REC-BIB-10 | Piste du demandeur | `GET /api/tracks/{id}/stream`, puis avec un en-tête `Range` | 200 puis **206** ; `Content-Type` lu **en base**, `Cache-Control: private, no-store` | Conforme — `TestStreamTrack_OK` ; `TestStreamTrack_Range` ; `track/service_test.go` `TestOpenTrackFile_OK` | ✅ | 2026-08-19 | US-05-04 · ADR 034 |
| REC-BIB-11 | Ligne en base sans fichier sur le volume | `GET /api/tracks/{id}/stream` | **404** + log `error` (pas de 500) | Conforme — `TestOpenTrackFile_MissingBinary` | ✅ | 2026-08-19 | ADR 034 |
| REC-BIB-12 | Quelques pistes uploadées | `GET /api/tracks` | Bibliothèque du demandeur — source du sélecteur d'ajout | Conforme — `TestListUserTracks_OK` | ✅ | 2026-08-19 | US-05-01 · US-05-03 |
| REC-BIB-13 | `STORAGE_PATH` configuré | Écrire, relire, supprimer un fichier ; relire un fichier absent | Nom = UUID + extension canonique (**jamais** le nom client → anti-traversal) ; erreurs propres | Conforme — `backend/internal/track/storage_test.go` `TestFileStorage_Save`, `TestFileStorage_Open`, `TestFileStorage_OpenMissing`, `TestFileStorage_Remove` | ✅ | 2026-08-19 | ADR 032 |
| REC-BIB-14 | Session ouverte | `POST /api/playlists`, puis avec le même nom, puis sans nom, puis sans jeton | 201, **409**, 400, 401 | Conforme — `backend/internal/playlist/handler_test.go` `TestCreate_OK`, `TestCreate_DuplicateName_409`, `TestCreate_MissingName_400`, `TestCreate_Unauthenticated_401` | ✅ | 2026-08-19 | US-05-02 · STR-131 |
| REC-BIB-15 | Plusieurs playlists | `GET /api/playlists` | Playlists du demandeur avec `track_count`, triées par date de création décroissante | Conforme — `TestList_OK` | ✅ | 2026-08-19 | US-05-02 |
| REC-BIB-16 | Playlist du demandeur | `PUT /api/playlists/{id}` (renommage), puis vers un nom déjà pris | 200 ; **409** sur doublon ; remplacement total (omettre `description` l'efface) | Conforme — `TestUpdate_OK` ; `TestUpdate_DuplicateName_409` | ✅ | 2026-08-19 | US-05-02 |
| REC-BIB-17 | Playlist du demandeur contenant des pistes | `DELETE /api/playlists/{id}` | 204, cascade sur `playlist_tracks` | Conforme — `TestDelete_OK_204` | ✅ | 2026-08-19 | US-05-02 |
| REC-BIB-18 | Playlist et piste du demandeur | `POST /api/playlists/{id}/tracks`, puis rejouer, puis sans `track_id`, puis sans jeton | 201 avec l'ordre résultant ; **409** si déjà présente ; 400 ; 401 | Conforme — `TestAddTrack_OK_201`, `TestAddTrack_AlreadyPresent_409`, `TestAddTrack_MissingTrackID_400`, `TestAddTrack_Unauthenticated_401` | ✅ | 2026-08-19 | US-05-03 · ADR 029 |
| REC-BIB-19 | Playlist de 3 pistes | `DELETE /api/playlists/{id}/tracks/{trackId}`, puis sur une piste absente | 204 et positions **recompactées** en 0..n-1 ; 404 | Conforme — `TestRemoveTrack_OK_204` ; `TestRemoveTrack_NotInPlaylist_404` | ✅ | 2026-08-19 | US-05-03 · ADR 029 |
| REC-BIB-20 | Playlist de 3 pistes | `PUT /api/playlists/{id}/tracks` avec un ordre complet, puis un doublon, puis une liste incomplète | Ordre persisté renvoyé ; **400** sur doublon ; **409** si la liste ne couvre pas exactement la playlist | Conforme — `TestReorderTracks_OK`, `TestReorderTracks_MissingField_400`, `TestReorderTracks_StaleOrder_409` | ✅ | 2026-08-19 | US-05-03 · ADR 029 |
| REC-BIB-21 | Playlist avec plusieurs pistes | Lancer la lecture depuis une piste donnée, sauter, laisser enchaîner, provoquer un échec | Enchaînement délégué au lecteur natif ; saut depuis l'app ou la notification suit le même chemin ; reprise bornée à 3 tentatives (1/2/4 s), position conservée, **seule la première** force une rotation de token | Conforme — `mobile/test/features/playlists/presentation/playlist_queue_controller_test.dart` | ✅ | 2026-08-19 | US-05-04 · ADR 034 |
| REC-BIB-22 | File d'attente en cours | Ouvrir la feuille de file, appuyer sur une ligne, manipuler le `Slider` de progression | La file visible suit l'ordre **de lecture** ; l'appui saute à la piste ; le seek repositionne la lecture | Conforme — `mobile/test/features/playlists/presentation/widgets/queue_ui_test.dart` ; `.../screens/playlist_detail_screen_test.dart` | ✅ | 2026-08-19 | US-05-04 · STR-230 |
| REC-BIB-23 | File d'attente en cours | Activer « Aléatoire », cycler la répétition (`off`/`one`/`all`), lancer « Lire en aléatoire » | L'ordre est tiré par le lecteur natif et **lu** par l'app ; `repeat one` ne gouverne que l'enchaînement **automatique** (un saut manuel avance) ; les modes survivent à `stop()` | Conforme — `mobile/test/core/audio/playback_order_test.dart` ; groupes « lecture aléatoire » / « répétition » de `playlist_queue_controller_test.dart` | ✅ | 2026-08-19 | US-05-05 · ADR 035 |
| REC-BIB-24 | Device physique, playlist de 5 pistes | Réordonner par **drag-and-drop** dans l'écran de détail, puis relancer la lecture | L'ordre persiste ; la file en cours n'est pas modifiée tant qu'on ne relance pas (photo au lancement) | | ⬜ | | US-05-03 · US-05-04 |

---

## 6. Diffuseur — `REC-DIF`

Rôle : **`broadcaster`**. Routes : `/api/streams*`, `/api/broadcaster-requests`,
`/api/users/me/streams`, ingest.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-DIF-01 | Compte `user` connecté | `POST /api/broadcaster-requests`, puis `GET /api/broadcaster-requests/me`, puis sans jeton | 201 ; statut de la demande consultable ; 401 sans jeton ; 405 sur mauvaise méthode | Conforme — `backend/internal/broadcaster/handler_test.go` `TestHandler_Create_Created`, `TestHandler_GetMine_OK`, `TestHandler_Create_RequiresToken`, `TestHandler_Create_WrongMethod` | ✅ | 2026-08-19 | ADR 014 · STR-49 |
| REC-DIF-02 | Rôle `broadcaster` | `POST /api/streams` avec titre et visibilité | 201 ; `stream_key` (32 octets base64url) et `stream_source_url` renvoyés au propriétaire | Conforme — `streaming/handler_test.go` `TestHandler_Create_OK` ; `service_test.go` `TestService_CreateStream_Success` | ✅ | 2026-08-19 | ADR 013 · STR-64 |
| REC-DIF-03 | Rôle `user` (pas diffuseur) | `POST /api/streams` | **403**, et le service n'est **pas** appelé | Conforme — `TestHandler_Create_ForbiddenForUser` | ✅ | 2026-08-19 | ADR 013 · ADR 006 |
| REC-DIF-04 | Rôle `broadcaster` | `POST /api/streams` sans titre, sans `is_public`, avec un champ inconnu | 400 dans les trois cas ; aucun appel repository sur erreur de validation | Conforme — `TestHandler_Create_MissingTitle`, `TestHandler_Create_MissingIsPublic`, `TestHandler_Create_UnknownField` ; `TestCreateStreamInput_validate` ; `TestService_CreateStream_ValidationError_NoRepoCall` | ✅ | 2026-08-19 | ADR 013 |
| REC-DIF-05 | Flux du demandeur | `PUT /api/streams/{id}` puis `DELETE /api/streams/{id}` | Mise à jour propriétaire seulement ; suppression = **soft delete** (`archived_at`) et arrêt de la session si le flux était en direct ; 404 pour un tiers | Conforme — `TestHandler_Update_OK`, `TestHandler_Update_MissingTitle`, `TestHandler_Update_NotFound`, `TestHandler_Delete_NoContent`, `TestHandler_Delete_NotFound` ; `TestService_UpdateStream_DelegatesOwnerScope`, `TestService_ArchiveStream_StopsSession` | ✅ | 2026-08-19 | ADR 013 |
| REC-DIF-06 | Flux `idle` du demandeur | `PATCH /api/streams/{id}/start` | 200, `idle → live` | Conforme — `TestHandler_Start_OK` ; `TestService_StartStream_Success` | ✅ | 2026-08-19 | US-06-01 · ADR 024 |
| REC-DIF-07 | Flux déjà `live` ou `ended` | `PATCH /api/streams/{id}/start` | **409** | Conforme — `TestHandler_Start_Conflict` ; `TestService_StartStream_NotIdle_Conflict` | ✅ | 2026-08-19 | US-06-01 |
| REC-DIF-08 | Le diffuseur a déjà un flux en direct | `PATCH /api/streams/{id}/start` sur un second flux | **409** — un seul direct par diffuseur, y compris en cas de course (violation d'unicité en base) | Conforme — `TestService_StartStream_AlreadyLive_Conflict` ; `TestService_StartStream_AlreadyLive_UniqueViolation` | ✅ | 2026-08-19 | STR-77 · ADR 013 §7 |
| REC-DIF-09 | Flux `live` du demandeur, puis flux non live | `PATCH /api/streams/{id}/stop` | 200 `live → ended` ; **409** si le flux n'était pas live | Conforme — `TestHandler_Stop_OK`, `TestHandler_Stop_Conflict` ; `TestService_StopStream_Success`, `TestService_StopStream_NotLive_Conflict` | ✅ | 2026-08-19 | US-06-01 |
| REC-DIF-10 | Flux `idle`/`ended` du demandeur | `POST /api/streams/{id}/key/rotate` | 200 avec une clé neuve ; l'ancienne cesse d'être acceptée ; entrée d'audit best-effort (son échec ne fait pas échouer la rotation) | Conforme — `TestHandler_RotateKey_OK` ; `TestService_RotateStreamKey_Success`, `TestService_RotateStreamKey_AuditFailureDoesNotFailRotation`, `TestService_RotateStreamKey_WithoutAuditRecorder` | ✅ | 2026-08-19 | US-06-04 · STR-228 · ADR 028 |
| REC-DIF-11 | Flux **en direct** | `POST /api/streams/{id}/key/rotate` | **409** — l'index `byKey` des sessions pointerait sur l'ancienne clé | Conforme — `TestHandler_RotateKey_Live_Conflict` ; `TestService_RotateStreamKey_Live_Conflict` | ✅ | 2026-08-19 | ADR 028 |
| REC-DIF-12 | — | Générer plusieurs clés de diffusion | 32 octets base64url, aléatoires et distinctes | Conforme — `backend/internal/streaming/keygen_test.go` `TestNewStreamKey` | ✅ | 2026-08-19 | ADR 013 |
| REC-DIF-13 | Flux `live`, clé valide | `POST /api/streams/ingest/{stream_key}` avec de l'**AAC**, puis sans `Content-Type` | Accepté et transmis **tel quel** au segmenteur (`-c:a copy`, aucun ré-encodage) | Conforme — `TestHandler_Ingest_AACIsPassedThroughUntouched` ; `TestHandler_Ingest_AllowsAbsentContentType` | ✅ | 2026-08-19 | ADR 015 · STR-70 |
| REC-DIF-14 | Flux `live`, clé valide | Ingest en **MP3** | Accepté ; un ffmpeg de transcodage est intercalé, le segmenteur reçoit de l'AAC/ADTS et produit un manifeste | Conforme — `TestHandler_Ingest_TranscodesMP3ToAAC` ; `transcode_test.go` `TestTranscoder_ConvertsToAAC`, `TestTranscodePipeline_MP3ToHLS` | ✅ | 2026-08-19 | US-09-05 · STR-204 · ADR 030 |
| REC-DIF-15 | Flux `live`, clé valide | Ingest avec un `Content-Type` non audio ; puis un corps indécodable ; puis une coupure de transport en cours d'envoi | Refus du non-audio ; **415** sur corps indécodable ; une erreur de transport n'est **pas** rapportée comme 415 | Conforme — `TestHandler_Ingest_RejectsNonAudioContentType`, `TestHandler_Ingest_RejectsUndecodablePayload`, `TestHandler_Ingest_TransportErrorIsNotReportedAs415` | ✅ | 2026-08-19 | ADR 030 |
| REC-DIF-16 | — | Résoudre le démultiplexeur pour chaque `Content-Type` d'ingest | Le `-f` vient d'une **table close**, jamais d'une chaîne fournie par le diffuseur ; les conteneurs partent en transcodage | Conforme — `TestResolveIngestFormat` ; `TestResolveIngestFormat_ContainersAreTranscoded` | ✅ | 2026-08-19 | ADR 030 |
| REC-DIF-17 | Diffuseur avec 0 puis N flux | `GET /api/users/me/streams`, puis sans jeton | Tous statuts non archivés **avec** `stream_key`/`stream_source_url` ; `[]` (jamais `null`, jamais 403) si aucun flux ; 401 sans jeton ; aucun contrôle de rôle (le filtre porte sur le porteur du JWT) | Conforme — `TestHandler_ListMine_OK`, `TestHandler_ListMine_EmptyIsArrayNotNull`, `TestHandler_ListMine_Unauthenticated` ; `TestService_ListMyStreams`, `TestService_ListMyStreams_NoRoleCheck` | ✅ | 2026-08-19 | US-06-01 · STR-153 · ADR 024 |
| REC-DIF-18 | Flux `live` du demandeur avec des auditeurs | `GET /api/streams/{id}/stats` ; flux non live | Auditeurs **estimés**, pic et durée ; auditeurs distincts comptés, expiration après fenêtre, pic conservé après départs, borne de capacité ; flux non live → 200 avec compteurs à zéro ; 401 sans jeton | Conforme — `TestHandler_Stats_OwnerOK`, `TestHandler_Stats_CountsListeners`, `TestHandler_Stats_Unauthenticated` ; `listeners_test.go` `TestSession_TouchListener_CountsDistinctClients`, `TestSession_Listeners_ExpireAfterWindow`, `TestSession_Peak_SurvivesDepartures`, `TestSession_Listeners_Capped` | ✅ | 2026-08-19 | US-06-02 · STR-154 · ADR 025 |
| REC-DIF-19 | Flux `live` | Cesser le push sans appeler `stop` ; puis tuer le segmenteur | Le bail d'ingest expire et clôt la session silencieuse ; une reconnexion réarme le bail ; un segmenteur mort fait « reaper » la session (pas de flux fantôme listé en direct) | Conforme — `session_test.go` `TestLiveSessions_IngestExpiryStopsSilentSession`, `TestLiveSessions_IngestReconnectResetsExpiry`, `TestLiveSessions_StopCancelsIngestExpiry` ; `hls_test.go` `TestSegmenterDeath_ReapsSession` | ✅ | 2026-08-19 | ADR 013 §7 · ADR 015 |
| REC-DIF-20 | Application mobile, compte diffuseur | Tableau de bord : créer, démarrer (avec capture micro), arrêter, régénérer la clé, supprimer ; observer l'audience | Une seule mutation à la fois ; un refus micro ne passe **jamais** le flux serveur à `live` ; `stop` termine le serveur avant de libérer le micro ; l'URL d'ingest est masquée par défaut et absente d'un flux terminé ; mesures d'audience périodiques uniquement en direct | Conforme — `mobile/test/features/broadcast/presentation/broadcast_notifier_test.dart` ; `.../screens/dashboard_screen_test.dart` ; `.../data/microphone_audio_publisher_test.dart` ; `broadcast_session_controller_test.dart` | ✅ | 2026-08-19 | US-06-01 · US-06-02 · US-06-04 · STR-156 · ADR 027 |
| REC-DIF-21 | Device physique, permission micro accordable | Démarrer un direct depuis le mobile, couper le réseau puis le rétablir, passer l'app en arrière-plan | Le direct démarre et est audible ; la reprise est bornée et annoncée ; le passage en arrière-plan arrête le live et libère le micro | | ⬜ | | STR-156 · ADR 027 |
| REC-DIF-22 | Encodeur externe (ffmpeg CLI, OBS, Icecast) | Pousser du MP3 puis de l'AAC sur `stream_source_url`, écouter le résultat | Les deux formats produisent un manifeste écoutable ; le MP3 passe par le transcodage | | ⬜ | | US-09-05 · ADR 030 |
| REC-DIF-23 | Flux `idle`, clé notée | Régénérer la clé, puis tenter un ingest avec l'**ancienne** URL | L'ancienne clé est refusée ; la nouvelle fonctionne | | ⬜ | | US-06-04 · ADR 028 |

---

## 7. Administrateur — `REC-ADM`

Rôle : **`admin`**. Routes : `/api/admin/*`.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-ADM-01 | Session admin, plusieurs comptes | `GET /api/admin/users` avec recherche, filtres rôle/statut et pagination | `{users, total}` ; filtres transmis au repository ; `limit`/`offset` bornés | Conforme — `backend/internal/admin/handler_test.go` `TestHandler_List_OK`, `TestHandler_List_PaginationClamp` ; `admin/service_test.go` `TestService_ListUsers_PassesFiltersAndReturnsTotal` | ✅ | 2026-08-19 | US-08-01 · STR-191 · ADR 017 |
| REC-ADM-02 | Session admin | `GET /api/admin/users?role=inconnu`, `?status=inconnu`, puis sur un résultat vide | 400, 400 ; liste vide sérialisée `[]` et non `null` | Conforme — `TestHandler_List_InvalidRole`, `TestHandler_List_InvalidStatus`, `TestHandler_List_EmptyUsersIsEmptyArrayNotNull` | ✅ | 2026-08-19 | US-08-01 |
| REC-ADM-03 | Session admin, compte cible actif | `PATCH /api/admin/users/{id}` avec `is_active=false`, puis `true` ; puis sans le champ ; puis sur un id inconnu | 200, 200, 400, 404 | Conforme — `TestHandler_SetActive_OK`, `TestHandler_SetActive_MissingIsActive`, `TestHandler_SetActive_NotFound` | ✅ | 2026-08-19 | US-08-01 |
| REC-ADM-04 | Session admin | Se désactiver soi-même, puis se supprimer soi-même (y compris avec un id de casse ou de format différents) | **409** dans tous les cas ; un id malformé n'est pas confondu avec une auto-action | Conforme — `TestService_SetUserActive_SelfAction`, `TestService_DeleteUser_SelfAction`, `..._CaseInsensitive`, `..._DashlessFormat`, `TestService_SetUserActive_MalformedTargetID_NotSelfAction` | ✅ | 2026-08-19 | US-08-01 · ADR 017 |
| REC-ADM-05 | Un seul admin actif | Désactiver puis supprimer cet admin ; refaire avec un second admin actif présent | **409** tant qu'il est le dernier ; opération permise dès qu'un autre admin actif existe | Conforme — `TestService_SetUserActive_LastActiveAdmin`, `TestService_DeleteUser_LastActiveAdmin`, `TestService_DeleteUser_ActiveAdmin_EnoughOtherAdmins` | ✅ | 2026-08-19 | US-08-01 · ADR 017 |
| REC-ADM-06 | Compte cible en direct et possédant des pistes | `DELETE /api/admin/users/{id}` | 204 ; les directs sont **arrêtés d'abord**, puis hard delete en cascade, puis suppression des fichiers ; si l'arrêt échoue, le delete n'a pas lieu | Conforme — `TestHandler_Delete_NoContent`, `TestHandler_Delete_Conflict`, `TestHandler_Delete_NotFound` ; `TestService_DeleteUser_StopsLiveBeforeDelete`, `TestService_DeleteUser_PurgesAroundDelete`, `TestService_DeleteUser_StopperError_PropagatesAndSkipsDelete`, `TestService_DeleteUser_NoPurger_StillDeletes` | ✅ | 2026-08-19 | US-08-01 · ADR 032 |
| REC-ADM-07 | Session admin, directs publics et privés en cours | `GET /api/admin/streams` avec pagination | `{streams, total}` : **tous** les directs avec l'identité du diffuseur ; bornes appliquées ; `[]` si vide | Conforme — `TestHandler_ListStreams_OK`, `TestHandler_ListStreams_PaginationClamp`, `TestHandler_ListStreams_EmptyStreamsIsEmptyArrayNotNull` ; `TestService_ListLiveStreams_DelegatesAndReturnsTotal` | ✅ | 2026-08-19 | US-08-02 · STR-192 |
| REC-ADM-08 | Direct en cours appartenant à un tiers | `POST /api/admin/streams/{id}/stop` | 204, `live → ended` **sans** contrôle de propriétaire, + entrée `audit_logs` ; l'échec de l'audit ne fait pas échouer l'arrêt ; l'échec de l'arrêt saute l'audit | Conforme — `TestHandler_StopStream_NoContent` ; `TestService_StopStream_OK_StopsThenAudits`, `TestService_StopStream_AuditError_StillReturnsNil`, `TestService_StopStream_ModeratorError_PropagatesAndSkipsAudit` | ✅ | 2026-08-19 | US-08-02 · ADR 018 (supervision) |
| REC-ADM-09 | Flux non live, puis flux inconnu | `POST /api/admin/streams/{id}/stop` | 409, puis 404 | Conforme — `TestHandler_StopStream_Conflict`, `TestHandler_StopStream_NotFound` ; `TestService_ForceStopStream_NotLive_Conflict`, `TestService_ForceStopStream_Absent_NotFound` | ✅ | 2026-08-19 | US-08-02 |
| REC-ADM-10 | Demandes diffuseur en attente | `GET /api/admin/broadcaster-requests`, puis approuver, puis refuser avec `review_note` ; id invalide | Liste filtrable ; approbation promeut l'utilisateur ; id invalide → 400 | Conforme — `backend/internal/broadcaster/handler_test.go` `TestHandler_Approve_UsesPathID`, `TestHandler_Approve_InvalidID` | ✅ | 2026-08-19 | ADR 014 · STR-49 |
| REC-ADM-11 | PostgreSQL réel, 5 comptes correspondant au filtre | `GET /api/admin/users` avec un `offset` au-delà du nombre de lignes filtrées | Page vide **mais** `total` = 5 (le total ne dépend pas de la pagination) | Test présent — `backend/internal/admin/repository_integration_test.go` `TestRepository_ListUsers_TotalReflectsAllMatchesNotJustPage` (build tag `integration`) — **non rejoué le 2026-08-19** | 🟡 | | US-08-01 · revue PR #264 |
| REC-ADM-12 | Application mobile, compte admin | Écrans d'administration : recherche avec debounce, filtres, désactivation (avec confirmation), suppression (mention cascade), conflits 409 | La liste se filtre ; la désactivation demande confirmation, la réactivation non ; un 409 affiche un toast et conserve la tuile ; les tuiles d'administration n'apparaissent que pour un admin | Conforme — `mobile/test/features/admin/presentation/screens/admin_users_screen_test.dart`, `admin_streams_screen_test.dart` ; `admin_users_provider_test.dart`, `admin_streams_provider_test.dart` ; `mobile/test/features/profile/presentation/screens/profile_screen_test.dart` | ✅ | 2026-08-19 | US-08-01 · US-08-02 |
| REC-ADM-13 | Diffuseur en direct, admin connecté sur un autre poste | L'admin interrompt le direct ; observer le tableau de bord du diffuseur | Le diffuseur voit son flux passer à `ended` (SSE), sans action de sa part | | ⬜ | | US-08-02 · ADR 018 (supervision) |

---

## 8. Sécurité transverse — `REC-SEC`

Ces scénarios traversent les rôles. Ils recensent notamment les contrôles **déjà implémentés**
et jusqu'ici non documentés en dehors du code.

| ID | Préconditions | Étapes | Résultat attendu | Résultat obtenu (preuve) | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-SEC-01 | Flux **public** appartenant à un tiers | `GET /api/streams/{id}` en tant que non-propriétaire | 200 avec le **même schéma**, mais `stream_key` et `stream_source_url` à **`null`** ; la valeur réelle de la clé n'apparaît nulle part ; les métadonnées publiques restent présentes | Conforme — `backend/internal/streaming/handler_test.go` `TestHandler_Get_NonOwnerNoSecrets` | ✅ | 2026-08-19 | ADR 013 |
| REC-SEC-02 | Flux **privé** appartenant à un tiers | `GET /api/streams/{id}` en tant que tiers, puis en anonyme | **404** — l'existence du flux n'est pas divulguée | Conforme — `streaming/service_test.go` `TestService_GetStream_PrivateNonOwner_NotFound`, `TestService_GetStream_PublicNonOwner`, `TestService_GetStream_Anonymous` ; `TestHandler_Get_NotFound` | ✅ | 2026-08-19 | ADR 013 |
| REC-SEC-03 | Flux en direct appartenant à un tiers | `GET /api/streams/{id}/stats` | **404 et non 403** — un tiers n'apprend ni l'audience, ni l'existence du flux | Conforme — `TestHandler_Stats_NotOwnerIs404` | ✅ | 2026-08-19 | US-06-02 · ADR 025 |
| REC-SEC-04 | Flux privé (ou inexistant) | `GET /api/streams/{id}/playlist.m3u8` **sans authentification** | **404**, jamais 401 : le handler sort sur la visibilité avant même de chercher une session | Conforme — `TestHandler_Playlist_PrivateNoAuth_Returns404` | ✅ | 2026-08-19 | US-04-02 · STR-108 |
| REC-SEC-05 | Comptes `user` et `broadcaster` | Appeler une route réservée à un rôle supérieur : création de flux en `user`, `/api/admin/users` et `/api/admin/streams` en non-admin, approbation de demande en non-admin | **403** dans tous les cas, et le service métier n'est **pas** appelé | Conforme — `TestHandler_Create_ForbiddenForUser` ; `admin/handler_test.go` `TestHandler_List_ForbiddenForNonAdmin`, `TestHandler_ListStreams_ForbiddenForNonAdmin` ; `broadcaster/handler_test.go` `TestHandler_Approve_ForbiddenForNonAdmin` | ✅ | 2026-08-19 | ADR 006 · ADR 017 |
| REC-SEC-06 | Aucune session | Appeler sans jeton : création de flux, stats, favoris, `me/streams`, admin, playlists, tracks. **Hors périmètre** : `GET /api/streams`, `playlist.m3u8` et `segments/*` sont publics par conception (REC-AUD-02, REC-AUD-04/05) | **401** partout sur le périmètre ci-dessus | Conforme — `TestHandler_Create_RequiresToken`, `TestHandler_Delete_RequiresToken`, `TestHandler_Start_RequiresToken`, `TestHandler_RotateKey_RequiresToken`, `TestHandler_Stats_Unauthenticated`, `TestHandler_ListMine_Unauthenticated`, `TestHandler_ListFavorites_Unauthenticated` ; `admin` `TestHandler_List_RequiresToken`, `TestHandler_SetActive_RequiresToken`, `TestHandler_Delete_RequiresToken`, `TestHandler_ListStreams_RequiresToken`, `TestHandler_StopStream_RequiresToken` ; `playlist` `TestCreate_Unauthenticated_401` ; `track` `TestUpload_Unauthenticated`, `TestStreamTrack_Unauthenticated` | ✅ | 2026-08-19 | ADR 006 |
| REC-SEC-07 | Jetons des quatre rôles | Traverser `RequireAuth`, `RequireRole` et `OptionalAuth` avec un jeton valide, invalide, absent | Hiérarchie `anonymous < user < broadcaster < admin` respectée ; `OptionalAuth` laisse passer en anonyme sur jeton absent **ou** invalide ; l'identité est journalisée dans l'access log | Conforme — `backend/internal/auth/middleware_test.go` `TestRequireAuth_ValidToken`, `TestRequireAuth_InvalidToken`, `TestRequireRole_Hierarchy`, `TestOptionalAuth_NoToken_Anonymous`, `TestOptionalAuth_ValidToken_InjectsIdentity`, `TestOptionalAuth_InvalidToken_Anonymous`, `TestRequireAuth_RecordsUserIDInAccessLog` | ✅ | 2026-08-19 | ADR 006 |
| REC-SEC-08 | Playlist appartenant à un tiers | `GET`, `PUT`, `DELETE /api/playlists/{id}` et `GET .../tracks` | **404** dans tous les cas — jamais 403 | Conforme — `backend/internal/playlist/handler_test.go` `TestGet_ThirdParty_404`, `TestDelete_ThirdParty_404` | ✅ | 2026-08-19 | US-05-02 · ADR 026 |
| REC-SEC-09 | Piste appartenant à un tiers | `GET /api/tracks/{id}/stream` | **404** — la propriété est filtrée **en SQL**, l'existence n'est pas révélée | Conforme — `backend/internal/track/handler_test.go` `TestStreamTrack_NotOwned` ; `track/service_test.go` `TestOpenTrackFile_NotOwned` | ✅ | 2026-08-19 | US-05-04 · ADR 034 |
| REC-SEC-10 | Compte au quota de stockage | Upload d'un audio valide | **403** `storage_quota_exceeded` — hors bucket 5xx, donc hors alerte ; rien n'est écrit | Conforme — `TestCreate_QuotaExceeded` (niveau service) | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-SEC-11 | — | Upload d'un **PDF renommé `.mp3`** | **415** : le MIME est sniffé sur le contenu, pas déduit du nom ni du `Content-Type` client | Conforme — `TestUpload_RejectsDisguisedFile` ; `TestCreate_RejectsNonAudio` | ✅ | 2026-08-19 | US-05-01 · ADR 032 |
| REC-SEC-12 | Session HLS active | Demander les segments `../etc/passwd`, `..`, `seg_1.ts/../x`, `/abs/seg_1.ts`, `seg_1.mp3`, `seg_1.TS`, `playlist.m3u8`, `""` ; puis un nom valide `seg_00000.ts` | Tous les noms hors du motif `seg_<chiffres>.ts` sont **rejetés** ; le nom valide est accepté ; la même garde s'applique au lookup de session | Conforme — `backend/internal/streaming/hls_test.go` `TestSegmentPath_RejectsTraversal` ; `TestPlaylistAndSegmentLookup` (rejet de `../secret`) | ✅ | 2026-08-19 | ADR 015 |
| REC-SEC-13 | Flux en direct dont on n'est pas propriétaire | `GET /api/streams` | La liste publique ne contient **ni** `stream_key`, **ni** `stream_source_url`, **ni** leur valeur | Conforme — `TestHandler_List_OK_NoStreamKey` | ✅ | 2026-08-19 | ADR 013 |
| REC-SEC-14 | `TRUST_PROXY_HEADERS=false` puis `true` | Émettre des requêtes en variant `X-Forwarded-For` pour gonfler le comptage d'audience | Sans proxy déclaré, l'en-tête est **ignoré** (l'IP réelle fait foi) ; derrière un proxy, seul le **dernier maillon** est lu — un en-tête forgé ne fractionne pas le compteur | Conforme — `TestHandler_ClientKey_IgnoresForwardedForByDefault`, `TestHandler_ClientKey_UsesLastForwardedHopWhenTrusted`, `TestHandler_ClientKey_ForgedForwardedForCannotSplitCount` | ✅ | 2026-08-19 | US-06-02 · ADR 025 |
| REC-SEC-15 | — | Demander une réinitialisation pour un email inconnu ; rejouer un refresh token consommé ; réinitialiser un mot de passe | Pas d'énumération de comptes ; refus du rejeu ; une réinitialisation **révoque toutes** les sessions | Conforme — `TestForgotPassword_UnknownEmail_ReturnsNil` ; `TestRefresh_TokenReuse_Rejected` ; `TestResetPassword_RevokesAllRefreshTokens` | ✅ | 2026-08-19 | ADR 006 · ADR 010 |
| REC-SEC-16 | `CORS_ALLOWED_ORIGINS` renseigné | Préflight `OPTIONS` ; requête depuis `localhost` en dev ; origine non listée en prod ; origine listée en prod ; requête sans `Origin` | Préflight court-circuité ; localhost accepté en dev quel que soit le port ; origine non listée **rejetée** en prod ; origine listée acceptée ; absence d'`Origin` sans effet | Conforme — `backend/internal/shared/httpmw/cors_test.go` `TestCORS_PreflightShortCircuited`, `TestCORS_DevAllowsLocalhostAnyPort`, `TestCORS_ProdRejectsUnlistedOrigin`, `TestCORS_ProdAllowsConfiguredOrigin`, `TestCORS_NoOriginPassesThrough` | ✅ | 2026-08-19 | ADR 004 |
| REC-SEC-17 | PostgreSQL réel, deux comptes dont un contenant l'underscore littéral | `GET /api/admin/users?search=<tag>_a_b` | `_` traité comme un **caractère littéral** et non comme un joker `ILIKE` : exactement 1 résultat | Test présent — `backend/internal/admin/repository_integration_test.go` `TestRepository_ListUsers_SearchEscapesLikeWildcards` (build tag `integration`) — **non rejoué le 2026-08-19** | 🟡 | | US-08-01 · revue PR #264 |
| REC-SEC-18 | — | Enchaîner les appels à `/api/auth/login` au-delà de la capacité ; varier `X-Forwarded-For` derrière un proxy ; attendre la reconstitution du seau | **429** + `Retry-After` au-delà de la capacité ; seaux isolés par client ; un `X-Forwarded-For` forgé ne donne **pas** un seau neuf ; les seaux inactifs sont purgés | Test présent mais **absent de `develop`** — `backend/internal/shared/httpmw/ratelimit_test.go` (`TestRateLimit_RefuseAuDelaDeLaCapacite`, `TestRateLimit_IsoleLesClients`, `TestRateLimit_SeauSeReconstitue`, `TestRateLimit_ForgedForwardedForNeDonnePasUnSeauNeuf`, `TestRateLimit_EvictionPurgeLesSeauxInactifs`), livré sur la branche `fix/str-242-config-securite-et-nettoyages` (commit `d643f18`), **non fusionnée** | 🟡 | | STR-242 (complète STR-240) |
| REC-SEC-19 | Compte au quota | Upload via le **handler HTTP** (et non le service) | **403** avec le code public `storage_quota_exceeded` de bout en bout | Test présent mais **absent de `develop`** — ajout à `backend/internal/track/handler_test.go` sur la même branche `fix/str-242-…` (commit `d643f18`). Sur `develop`, seul le niveau service est verrouillé (REC-SEC-10) | 🟡 | | US-05-01 · STR-242 |
| REC-SEC-20 | Stack de production derrière Caddy | `GET /metrics` depuis l'extérieur ; puis depuis le réseau interne | **403** depuis l'extérieur ; scrape interne fonctionnel | | ⬜ | | US-07-03 · ADR 019 |
| REC-SEC-21 | `GO_ENV=production` | `GET /swagger/` et `GET /swagger/openapi.yaml` | Endpoints **non montés** en production (montés seulement si `!cfg.IsProd()`) | | ⬜ | | ADR 012 (OpenAPI) |

---

## 9. Performance et charge — `REC-PRF`

Source : `make loadtest` → `backend/internal/streaming/loadtest/load_test.go` (build tag
`loadtest`, exclu de `go test ./...`). Décision et protocole : [ADR 016](adr/016-scalabilite-test-de-charge-et-limiteur-hls.md).

Protocole du run : serveur réel in-process (vrai mux, vraies `LiveSessions`, vrai middleware JWT,
vrai ffmpeg), 1 diffuseur sine AAC temps réel, **50 auditeurs** pendant 60 s, limiteur à 256,
`-race -count=1`. 1500 requêtes playlist + 300 segments (~50 Mo servis), aucun 503 émis.

**Ces chiffres sont ceux du run du 2026-08-18 reporté dans l'ADR 016. Ils n'ont pas été rejoués
le 2026-08-19.**

| ID | Préconditions | Étapes | Résultat attendu (seuil STR-87) | Résultat obtenu | Statut | Date | US / exigence |
|---|---|---|---|---|---|---|---|
| REC-PRF-01 | ffmpeg installé, `make loadtest` | 50 auditeurs récupèrent le manifeste en boucle pendant 60 s | p95 playlist **< 300 ms** | **22,56 ms** | 🟡 | 2026-08-18 | STR-87 · ADR 016 |
| REC-PRF-02 | idem | Les mêmes auditeurs récupèrent les segments neufs | p95 segment **< 300 ms** | **28,52 ms** | 🟡 | 2026-08-18 | STR-87 |
| REC-PRF-03 | idem | Mesure `runtime` de la mémoire dans le process serveur | **< 2 Mo/connexion** | **0,14 Mo/connexion** | 🟡 | 2026-08-18 | STR-87 |
| REC-PRF-04 | idem | Compter les échecs HTTP sur l'ensemble de la campagne | **0 échec** | **0 / 1800 requêtes** | 🟡 | 2026-08-18 | STR-87 |
| REC-PRF-05 | idem | Compter les goroutines avant charge, puis après stop et drain (dump `pprof` si dépassement) | **Aucune fuite** | **13 → 10** | 🟡 | 2026-08-18 | STR-89 · ADR 016 |
| REC-PRF-06 | N flux **simultanés** (et non N auditeurs sur un flux) | Mesurer le coût CPU de plusieurs directs concurrents (un ffmpeg par direct) | À définir — non mesuré à ce jour | | ⬜ | | STR-243 · ADR 016 |

Limites assumées du protocole : in-process (latences hors RTT réseau et TLS), source sine à débit
constant, matériel local ≠ VPS de production.

> ⚠️ Le harnais de charge est resté **non compilable du 2026-07-25 au 2026-08-18** (build tag
> excluant le fichier de `go build` comme de `go test`). Deux garde-fous ont été posés depuis
> (STR-241) : `go vet -tags loadtest,integration ./...` dans le job Test de la CI, et un
> `schedule` hebdomadaire sur le workflow « Load Test ». C'est la raison pour laquelle un
> scénario 🟡 doit être rejoué avant toute soutenance, et non tenu pour acquis.

---

## 10. Écarts connus et zones non couvertes

Consignés ici pour qu'ils soient discutés plutôt que découverts.

1. **Limitation de débit sur `/api/auth/*` (REC-SEC-18) — absente de `develop`.** Le middleware
   et ses cinq tests existent sur `fix/str-242-config-securite-et-nettoyages` uniquement. Tant que
   cette branche n'est pas fusionnée, **aucune borne** ne protège la connexion, l'inscription et
   `forgot-password` contre la force brute et le bombardement d'emails.
2. **Tests d'intégration PostgreSQL (REC-ADM-11, REC-SEC-17) — non rejoués.** Ils exigent un
   conteneur PostgreSQL, indisponible sur le poste de recette le 2026-08-19. À relancer avec la
   procédure décrite en tête de `backend/internal/admin/repository_integration_test.go`.
3. **Aucun test de bout en bout API + base réelle** dans la suite par défaut. Les handlers et
   services sont testés contre des stubs ; le SQL n'est vérifié que par les deux tests taggés
   `integration` du domaine admin. Les scénarios de ce cahier qui reposent sur une contrainte de
   base (`uq_tracks_user_title` en REC-BIB-09, unicité de position en REC-BIB-20) ne sont donc pas
   fermés au niveau SQL.
4. **Tout ce qui dépend d'un appareil** (REC-AUD-16/17, REC-BIB-24, REC-CPT-18/19/20,
   REC-DIF-21/22/23) reste manuel par nature : microphone, arrière-plan, notification système,
   deep link, magasin de jetons sécurisé.
5. **Configuration de production** (REC-SEC-20/21) : le blocage de `/metrics` par Caddy et le
   non-montage de Swagger reposent sur la configuration d'infrastructure et l'environnement, pas
   sur du code testé unitairement.

## 11. Tenue à jour

- Toute nouvelle route ou tout nouveau cas d'erreur → **un scénario ici**, avec son statut réel.
- Un scénario ⬜ passé manuellement → renseigner « résultat obtenu » et « date », en gardant ⬜
  tant qu'aucun test ne l'automatise (un passage manuel n'est pas un test de non-régression).
- Un scénario 🟡 devient ✅ **le jour où il est rejoué**, pas avant.
- Ce document est un livrable de recette : il ne doit jamais affirmer un résultat qui n'a pas été
  constaté.
