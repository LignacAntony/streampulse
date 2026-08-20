# Dossier RGPD

Ce que StreamPulse collecte, pourquoi, sur quelle base légale, combien de temps,
et comment une personne exerce ses droits.

StreamPulse est un projet d'étude : il n'a pas de délégué à la protection des
données ni de sous-traitant. Ce dossier est écrit comme s'il en avait, parce que
c'est la seule façon de vérifier que le code fait ce qu'on croit.

**Documents liés** — [securite.md](securite.md) (contrôles techniques),
[politique-confidentialite.md](politique-confidentialite.md) (version destinée
aux utilisateurs), [cgu.md](cgu.md).

---

## 1. Registre des traitements

| Traitement | Données | Finalité | Base légale | Conservation |
|---|---|---|---|---|
| Compte utilisateur | Email, nom d'utilisateur, condensat du mot de passe, rôle, état actif, dates | Identifier la personne, contrôler ses accès | Exécution du contrat (art. 6.1.b) | Jusqu'à suppression du compte |
| Profil | Pseudonyme, biographie, URL d'avatar, thème, notifications, qualité audio | Personnaliser l'application | Exécution du contrat | Supprimé avec le compte (cascade) |
| Session | Condensat SHA-256 du refresh token, expiration | Maintenir la connexion sans redemander le mot de passe | Exécution du contrat | Jusqu'à expiration, rotation ou déconnexion |
| Réinitialisation de mot de passe | Condensat du jeton, expiration, date d'usage | Permettre de retrouver l'accès | Exécution du contrat | Jeton à usage unique, courte durée |
| Demande de rôle diffuseur | Motivation, statut, note du relecteur, identité du relecteur | Instruire la demande | Exécution du contrat | Supprimée avec le compte |
| Flux de diffusion | Titre, description, visibilité, `stream_key`, statut, horodatages | Fournir le service de diffusion | Exécution du contrat | Supprimé avec le compte |
| Bibliothèque de pistes | Titre, artiste, durée, type MIME, taille, chemin du fichier, **et le fichier audio lui-même** | Permettre l'écoute de ses propres fichiers | Exécution du contrat | Supprimée avec le compte (base et volume) |
| Playlists et favoris | Noms, descriptions, ordre des pistes, flux mis en favori | Fournir la fonctionnalité | Exécution du contrat | Supprimés avec le compte |
| Journaux d'accès | Préfixe réseau de l'adresse (`/24` ou `/48`), identifiant utilisateur, méthode, chemin, statut, durée, `request_id`, `trace_id` | Exploiter le service, diagnostiquer les incidents | Intérêt légitime (art. 6.1.f) | **30 jours** |
| Traces distribuées | Chemin, statut, durée, requêtes SQL sans leurs arguments | Diagnostiquer les latences | Intérêt légitime | **7 jours** |
| Métriques | Compteurs et histogrammes agrégés, **sans identifiant de personne** | Superviser la santé du service | Intérêt légitime | 90 jours |
| Journal d'audit | Identifiant de l'administrateur, action, cible, date | Tracer les actes de modération | Intérêt légitime | Conservé ; l'identité est détachée à la suppression du compte |

Aucun traitement ne repose sur le **consentement** au sens de l'art. 6.1.a : il
n'y a ni marketing, ni analyse comportementale, ni traceur publicitaire.
L'acceptation de la politique de confidentialité à l'inscription est une
information (art. 12-13), pas une base légale.

**Aucune donnée n'est transmise à un tiers.** Pas de service d'analyse
d'audience, pas de régie, pas d'hébergeur de traces externe. La seule sortie est
l'envoi d'emails transactionnels — réinitialisation de mot de passe — vers le
relais SMTP configuré.

## 2. Politique de rétention par magasin

| Magasin | Contenu | Durée | Comment elle est appliquée |
|---|---|---|---|
| PostgreSQL | Comptes, contenus, sessions, audit | Vie du compte | Suppression du compte → cascade SQL |
| Volume `track_storage` | Fichiers audio téléversés | Vie du compte | `PurgeUserTracks` après le succès du `DELETE` en base |
| Loki | Journaux d'accès JSON | **30 jours** | `compactor` + `retention_period: 720h` |
| Tempo | Traces OpenTelemetry | **7 jours** | `compactor.compaction.block_retention: 168h` |
| Prometheus | Séries de métriques | 90 jours | `--storage.tsdb.retention.time=90d` |
| Grafana | Tableaux de bord, alertes | Sans objet | Aucune donnée personnelle |

Trois de ces durées **n'existaient pas** avant ce dossier : Loki, Tempo et
Prometheus fonctionnaient sur leurs défauts, et pour Loki le défaut est
« indéfiniment ». Une conservation sans durée définie contrevient à
l'art. 5(1)(e). C'est corrigé dans la même modification que ce document.

**L'adresse IP n'est plus journalisée en entier.** `httpjson.AnonymizeIP` réduit
l'adresse à son préfixe réseau — `/24` en IPv4, `/48` en IPv6 — avant écriture.
Le champ garde ce à quoi il sert (reconnaître qu'une rafale vient d'un même
réseau) et cesse de désigner une ligne d'abonné.

## 3. Droits des personnes

| Droit | Article | Disponible | Comment |
|---|---|---|---|
| Accès | 15 | Partiellement | L'application montre profil, flux, playlists, pistes et favoris. Pas d'export global en un geste. |
| Rectification | 16 | Oui | `PUT /api/users/me` depuis l'écran de profil |
| Effacement | 17 | Oui | `DELETE /api/auth/me` — suppression définitive, confirmée par le mot de passe |
| Portabilité | 20 | **Non** | Aucun export machine lisible. Écart assumé, § 5. |
| Opposition | 21 | Sans objet | Aucun traitement fondé sur l'intérêt légitime au-delà de l'exploitation technique |
| Limitation | 18 | Par équivalent | Un administrateur peut désactiver un compte, ce qui suspend tout usage |

### Ce que fait exactement la suppression de compte

`DELETE /api/auth/me` exige le mot de passe — un jeton volé ne suffit pas à
effacer un compte. La suppression est ensuite un **hard delete**, pas un
marquage :

1. Les chemins des fichiers audio de la personne sont relevés.
2. La ligne `users` est supprimée. Onze clés étrangères réparties sur dix tables
   propagent la suppression : neuf en `ON DELETE CASCADE` (profil, sessions,
   jetons de réinitialisation, flux, pistes, playlists, file d'attente, favoris,
   demandes de rôle) et deux en `ON DELETE SET NULL`.
3. Les fichiers audio sont retirés du volume — **seulement si le `DELETE` a
   réussi**. L'ordre est délibéré : l'inverse laisserait des lignes pointant
   vers des fichiers absents.

Les deux `ON DELETE SET NULL` sont `audit_logs.actor_id` et
`broadcaster_requests.reviewed_by`. La trace d'un acte de modération survit à la
suppression du compte de l'administrateur, **sans son identité**. C'est
l'arbitrage entre l'art. 17 et l'obligation de garder une trace des décisions :
on efface la personne, pas le fait.

## 4. Information et consentement

À l'inscription, l'application affiche une case à cocher renvoyant à la
politique de confidentialité et aux conditions d'utilisation. Ces deux documents
sont **embarqués dans l'application** (`mobile/assets/legal/`) : ils s'ouvrent
sans réseau et sans compte, ce qui est la seule façon d'être lisible *avant*
l'inscription.

Ils sont la copie exacte de [politique-confidentialite.md](politique-confidentialite.md)
et [cgu.md](cgu.md). Un contrôle d'intégrité en CI échoue si les deux copies
divergent — un document légal qui dérive silencieusement de sa version publiée
est pire que pas de document.

## 5. Écarts connus

1. **Pas de portabilité (art. 20).** Aucun export machine lisible des données
   d'une personne. Le droit d'accès est couvert « par l'usage » — la personne
   voit ses données dans l'application — ce qui n'est pas la même chose.
2. **Pas de purge automatique des jetons expirés.** Les lignes de
   `refresh_tokens` et `password_reset_tokens` dépassées restent en base : elles
   ne sont plus utilisables, mais elles continuent de rattacher une date à un
   compte. Une tâche de nettoyage périodique manque.
3. **Pas de registre des violations.** Aucune procédure écrite de notification
   sous 72 heures (art. 33).
4. **La rétention Loki n'est effective qu'après déploiement.** Tant que la
   configuration n'est pas appliquée sur le serveur, les journaux déjà collectés
   restent sans durée. Suivi par le ticket STR-240.
5. **Pas d'analyse d'impact (AIPD).** Le traitement ne figure pas dans les cas
   qui l'imposent, mais l'absence n'est pas documentée formellement.
