# Changelog

## [1.3.2](https://github.com/LignacAntony/streampulse/compare/v1.3.1...v1.3.2) (2026-08-24)


### Bug Fixes

* **ci:** corriger la configuration Flutter du job CD Android ([#354](https://github.com/LignacAntony/streampulse/issues/354)) ([191f8c7](https://github.com/LignacAntony/streampulse/commit/191f8c733f6f7e235bd2d95a6f8e6c348db9807b))

## [1.3.1](https://github.com/LignacAntony/streampulse/compare/v1.3.0...v1.3.1) (2026-08-24)


### Bug Fixes

* **ci:** définir la branche cible develop pour Dependabot ([9dcbf4e](https://github.com/LignacAntony/streampulse/commit/9dcbf4ed80e5589b53a80d34224c451fc65d906a))
* **ci:** définir la branche cible develop pour Dependabot ([5ce8137](https://github.com/LignacAntony/streampulse/commit/5ce8137b858c016900680348b80067d53ed01c27))

## [1.3.0](https://github.com/LignacAntony/streampulse/compare/v1.2.0...v1.3.0) (2026-08-23)


### Features

* **api:** mesurer le débit, les départs d'auditeurs et exposer un résumé admin ([#328](https://github.com/LignacAntony/streampulse/issues/328)) ([7d055ed](https://github.com/LignacAntony/streampulse/commit/7d055edf84b923c2164c9b9cc5ae0067cd219a5b))
* **mobile:** cache hors ligne des playlists (US-09-02) ([#296](https://github.com/LignacAntony/streampulse/issues/296)) ([391d93f](https://github.com/LignacAntony/streampulse/commit/391d93fbc88e54bb76314014d5988c3c47cdaa66))
* **mobile:** construire et livrer l'application Android à chaque release ([#326](https://github.com/LignacAntony/streampulse/issues/326)) ([fb418e7](https://github.com/LignacAntony/streampulse/commit/fb418e7524c945b7f60ba8f763fa1b3a7dfe84d7))
* **mobile:** nommer les contrôles pour les lecteurs d'écran et adapter aux largeurs ([#332](https://github.com/LignacAntony/streampulse/issues/332)) ([2bba957](https://github.com/LignacAntony/streampulse/commit/2bba957f1c677a1faeaa3bf6aecadd02cb33076e))
* **mobile:** régler le volume dans l'application et afficher le temps d'écoute ([#331](https://github.com/LignacAntony/streampulse/issues/331)) ([1f11343](https://github.com/LignacAntony/streampulse/commit/1f11343393d46f92bd295ae1a2a87cecf7775cf7))


### Bug Fixes

* **api:** fermer les défauts de configuration et de sécurité ([#316](https://github.com/LignacAntony/streampulse/issues/316)) ([d38dbef](https://github.com/LignacAntony/streampulse/commit/d38dbef6a55e273ed7cd772c96e821a9b572779e))
* **api:** rétablir le démarrage en distinguant l'URL de migration ([#323](https://github.com/LignacAntony/streampulse/issues/323)) ([464b5c7](https://github.com/LignacAntony/streampulse/commit/464b5c71960f810d45cd4e85398fad8c702ba998))
* dossier sécurité et RGPD, rétention des données personnelles bornée ([#321](https://github.com/LignacAntony/streampulse/issues/321)) ([126a3c0](https://github.com/LignacAntony/streampulse/commit/126a3c04c62ce7e4b0420e4d30898d2d6b080927))
* **infra:** restreindre l'exposition des services en production ([#312](https://github.com/LignacAntony/streampulse/issues/312)) ([389f385](https://github.com/LignacAntony/streampulse/commit/389f385d9c2eb1031e7eae384fb56ea1498da38e))
* **mobile:** restreindre le trafic en clair au développement ([#313](https://github.com/LignacAntony/streampulse/issues/313)) ([ceb79c3](https://github.com/LignacAntony/streampulse/commit/ceb79c3398af8c9cea5a946b8ca17fd917126e7e))

## [1.2.0](https://github.com/LignacAntony/streampulse/compare/v1.1.0...v1.2.0) (2026-08-14)


### Features

* ajout et réorganisation de pistes dans une playlist (US-05-03) ([#280](https://github.com/LignacAntony/streampulse/issues/280)) ([e620c30](https://github.com/LignacAntony/streampulse/commit/e620c30a6efd18f7957f514f8d52b7ea5d3c6ea7))
* **api:** arret gracieux du serveur (SIGTERM) ([6684b77](https://github.com/LignacAntony/streampulse/commit/6684b7724279d2bb61241d5a783d3d497f2cdf03))
* **api:** composant LiveSessions (registre goroutines + context) ([05a487d](https://github.com/LignacAntony/streampulse/commit/05a487dc49b6a936469c09fafd891686ed492811))
* **api:** création et configuration d'un flux live ([bc1e383](https://github.com/LignacAntony/streampulse/commit/bc1e383b1e8007f3142e99af6e4bd05f9387f7c9))
* **api:** créer le domaine admin de gestion des utilisateurs (STR-193) ([5555709](https://github.com/LignacAntony/streampulse/commit/555570929a1ab2df55513eabbb1b7938772472bf))
* **api:** démarrage et arrêt du flux (diffuseur) ([46bec7f](https://github.com/LignacAntony/streampulse/commit/46bec7fc3ee66ac34a0b9108d08f6ebcfaeb0505))
* **api:** endpoints PATCH start/stop du flux (STR-82/83) ([ec63465](https://github.com/LignacAntony/streampulse/commit/ec63465a8e10f4d320aaf5be0756d9878f909aae))
* **api:** exposer la supervision et l'interruption des flux aux administrateurs (STR-197, STR-198) ([206079e](https://github.com/LignacAntony/streampulse/commit/206079ec95f1d917ad0b3a8d5200efe3546c0f4f))
* **api:** exposer les endpoints admin de gestion des utilisateurs (STR-194, STR-196) ([485ce08](https://github.com/LignacAntony/streampulse/commit/485ce08719c79fec5336c489ab66f72aea26f42b))
* **api:** heartbeat keep-alive sur le flux SSE ([26a7674](https://github.com/LignacAntony/streampulse/commit/26a767406309ff8db0a020298824e723b5be7993))
* **api:** logs structurés JSON zerolog et collecte Loki via Alloy ([6e81b56](https://github.com/LignacAntony/streampulse/commit/6e81b56f41ba6bbe8afb58c4f458abea00e49485))
* **api:** logs structurés JSON zerolog et collecte Loki via Alloy ([105c6a9](https://github.com/LignacAntony/streampulse/commit/105c6a92644795d2b62e0d71e8b81667e4df8c97))
* **api:** métriques métier du streaming et dashboard Grafana Live ([#272](https://github.com/LignacAntony/streampulse/issues/272)) ([9276214](https://github.com/LignacAntony/streampulse/commit/92762141b934d3fce90ca1f26c284d0d5e06c43e))
* **api:** métriques Prometheus, node_exporter et dashboards Grafana API & Infra ([05f756d](https://github.com/LignacAntony/streampulse/commit/05f756d222107eaf0e9efa621365c92d324ca1d3))
* **api:** métriques Prometheus, node_exporter et dashboards Grafana API & Infra ([50ce2cc](https://github.com/LignacAntony/streampulse/commit/50ce2cce3ccddc31af7f5c7aaf4ac1437abbb3f7))
* **api:** moteur HLS — segmentation et génération du manifeste ([#259](https://github.com/LignacAntony/streampulse/issues/259)) ([5f915ae](https://github.com/LignacAntony/streampulse/commit/5f915aee9eb48e585cb0f8b4a4e1da95c2ee8daa))
* **api:** notification SSE d'arret de flux (STR-85) ([b162a9c](https://github.com/LignacAntony/streampulse/commit/b162a9c3d5ec413e58f6888bfef37b66b962282d))
* **api:** permettre l'interruption d'un flux par un administrateur (STR-197) ([f487534](https://github.com/LignacAntony/streampulse/commit/f4875342a674dbddb0bdf4b9490e32855a7b4a15))
* **api:** permettre la lecture publique HLS sans authentification ([#263](https://github.com/LignacAntony/streampulse/issues/263)) ([ef30f7a](https://github.com/LignacAntony/streampulse/commit/ef30f7a8c8e3b84d764a2b63759d58affe7f4d79))
* **api:** rotation de la clé de diffusion (STR-228) ([#279](https://github.com/LignacAntony/streampulse/issues/279)) ([11a2bd5](https://github.com/LignacAntony/streampulse/commit/11a2bd52edcdefde1ce99fd17b6e27cc9c253e5f))
* **api:** scalabilité 50 auditeurs — test de charge, limiteur HLS et rapport ([31d175a](https://github.com/LignacAntony/streampulse/commit/31d175ab0ca6d7e0f9f352b2ed4cae1e161500d1))
* **api:** scalabilité 50 auditeurs — test de charge, limiteur HLS et rapport ([8408991](https://github.com/LignacAntony/streampulse/commit/84089910ec96e820ce461e111c262f91cbb25646))
* **api:** statistiques d'audience en temps réel du diffuseur (STR-154) ([#277](https://github.com/LignacAntony/streampulse/issues/277)) ([93d448d](https://github.com/LignacAntony/streampulse/commit/93d448d37fc291f6b74eb54e9c193acf89dab371))
* **api:** supervision et interruption admin des flux actifs ([d7b5258](https://github.com/LignacAntony/streampulse/commit/d7b5258305010a9f7b6684ca1979ce92012dd5ce))
* **api:** tableau de bord admin — gestion des utilisateurs ([86a147c](https://github.com/LignacAntony/streampulse/commit/86a147c20612d0d4808a947909c8172345882812))
* **api:** traces OpenTelemetry OTLP vers Tempo avec spans HTTP et SQL ([#269](https://github.com/LignacAntony/streampulse/issues/269)) ([b64ef81](https://github.com/LignacAntony/streampulse/commit/b64ef81b5e70daa8ac8e600fdf6482924948e16d))
* **api:** transcodage à la volée des formats d'ingest non-AAC (STR-204) ([#281](https://github.com/LignacAntony/streampulse/issues/281)) ([83d6868](https://github.com/LignacAntony/streampulse/commit/83d68686d78e6cf45fe0dadd3ae663e780a0132f))
* création et gestion de playlists (US-05-02) ([#276](https://github.com/LignacAntony/streampulse/issues/276)) ([dd1b456](https://github.com/LignacAntony/streampulse/commit/dd1b4565fc5b72aa0cae8e390fe3d8d416701352))
* **infra:** dashboard Grafana Logs & Erreurs et alertes provisionnées par email ([#271](https://github.com/LignacAntony/streampulse/issues/271)) ([95322ab](https://github.com/LignacAntony/streampulse/commit/95322aba981254967565afb276d9ffa6cebfdd1a))
* lecture d'une playlist avec file d'attente (US-05-04) ([#287](https://github.com/LignacAntony/streampulse/issues/287)) ([05e6d0c](https://github.com/LignacAntony/streampulse/commit/05e6d0c5379b91e8e975b4ece040b14f4910c7ad))
* merge develop into main ([0d284c1](https://github.com/LignacAntony/streampulse/commit/0d284c1fe2c0e3e3f0ab9b46c7a726e376b6d247))
* **mobile:** ajout d'un flux aux favoris (STR-111) ([c1c9927](https://github.com/LignacAntony/streampulse/commit/c1c9927b980849877903efd59ee79349bf124648))
* **mobile:** ajouter la couche données de supervision des flux (STR-199) ([569ff36](https://github.com/LignacAntony/streampulse/commit/569ff364787b2aee400db74e1d42889fd431df67))
* **mobile:** ajouter la couche données du module admin (STR-195) ([3db4b4a](https://github.com/LignacAntony/streampulse/commit/3db4b4a99678b46ec0aac649d57ccc3ff289e644))
* **mobile:** barre de progression et navigation dans la piste (STR-230) ([#292](https://github.com/LignacAntony/streampulse/issues/292)) ([ffba42c](https://github.com/LignacAntony/streampulse/commit/ffba42c6c51644871424ae9969c6797f6933ac46))
* **mobile:** diffuse le microphone en AAC ([#278](https://github.com/LignacAntony/streampulse/issues/278)) ([3c42547](https://github.com/LignacAntony/streampulse/commit/3c425473caa86a5fd17e3975ba3a054e9b6a880f))
* **mobile:** écran d'administration des utilisateurs (STR-195) ([fdb5242](https://github.com/LignacAntony/streampulse/commit/fdb524253d53f1dd8b5187bf73292a4ad7b4cabf))
* **mobile:** écran de supervision et d'interruption des flux (STR-199) ([5344d2c](https://github.com/LignacAntony/streampulse/commit/5344d2ce8d42f393df18fb26d2fc2a0d46ca51e2))
* **mobile:** gestion des interruptions audio (US-04-04) ([#286](https://github.com/LignacAntony/streampulse/issues/286)) ([0ae822d](https://github.com/LignacAntony/streampulse/commit/0ae822d68231aa9e0960afacd564d826342d05fa))
* **mobile:** lecteur audio HLS play/pause/volume (STR-108) ([#273](https://github.com/LignacAntony/streampulse/issues/273)) ([a858859](https://github.com/LignacAntony/streampulse/commit/a8588598168e17adb17c311a19ed8a9b3622951a))
* **mobile:** lecture audio en arrière-plan (US-04-03) ([#282](https://github.com/LignacAntony/streampulse/issues/282)) ([e6234a5](https://github.com/LignacAntony/streampulse/commit/e6234a5da2936cf205fcd32fb5657e23622a27b3))
* **mobile:** lecture d'une piste depuis la bibliothèque (STR-231) ([#293](https://github.com/LignacAntony/streampulse/issues/293)) ([d171741](https://github.com/LignacAntony/streampulse/commit/d171741605b8b24cd47feafd7096c1dd1792b971))
* **mobile:** modes shuffle et repeat de la file d'attente (US-05-05) ([#289](https://github.com/LignacAntony/streampulse/issues/289)) ([14027bd](https://github.com/LignacAntony/streampulse/commit/14027bd62752dda7f41823991e1afc615e7e5467))
* **mobile:** tableau de bord diffuseur — lancer et arrêter un flux (STR-153) ([#274](https://github.com/LignacAntony/streampulse/issues/274)) ([3eefd65](https://github.com/LignacAntony/streampulse/commit/3eefd654b4a1067bbcf832e1bee3b058a9f69cab))
* **streams:** implement live stream discovery and listing functionality ([#256](https://github.com/LignacAntony/streampulse/issues/256)) ([ef0087c](https://github.com/LignacAntony/streampulse/commit/ef0087c1a4d91b5f2b4a6c3b2dcbbfc3bfc73b0b))
* upload d'une piste audio dans la bibliothèque (US-05-01) ([#284](https://github.com/LignacAntony/streampulse/issues/284)) ([abd5856](https://github.com/LignacAntony/streampulse/commit/abd5856376fa7c201112bcd55567dc5485baaaf6))


### Bug Fixes

* **api:** archiver un flux live le termine et libere sa session ([514a528](https://github.com/LignacAntony/streampulse/commit/514a528739534730a7d8ede252daa34020bbaf73))
* **api:** corrige la course Subscribe/Stop du flux SSE ([7ea006b](https://github.com/LignacAntony/streampulse/commit/7ea006b98188be0f42ad93395e41610c095c7eb2))
* **api:** corriger les alertes gosec de l'upload de pistes ([#288](https://github.com/LignacAntony/streampulse/issues/288)) ([b71f75d](https://github.com/LignacAntony/streampulse/commit/b71f75d54da7f7faed5c0362382592f999bdec6a))
* **api:** durcir les gardes admin, corriger le total paginé et l'enum de rôle ([196fdab](https://github.com/LignacAntony/streampulse/commit/196fdaba74854d36e4b9a5a10e50f47435580c42))
* **api:** durcir les métriques Prometheus suite à la revue ([76cb4b5](https://github.com/LignacAntony/streampulse/commit/76cb4b5cb55649db593166807399d52dd8f7365e))
* **api:** masquer le stream_key dans les logs d'erreur HTTP ([96c14c6](https://github.com/LignacAntony/streampulse/commit/96c14c606b09369ee52a70b84f8d6d0bb680c84a))
* **api:** masquer le stream_key dans les logs d'erreur HTTP ([111cc8f](https://github.com/LignacAntony/streampulse/commit/111cc8f238bc0aa462b3e5640f9ba63823682a68))
* **api:** neutraliser le faux positif gosec G204 sur l'appel ffmpeg ([#260](https://github.com/LignacAntony/streampulse/issues/260)) ([aa4e929](https://github.com/LignacAntony/streampulse/commit/aa4e929990b47483f02943fbd6eac0ed7f71246b))
* **api:** remonte les erreurs de demarrage HTTP ([df16740](https://github.com/LignacAntony/streampulse/commit/df16740cabdd107a44e7e8da345c51ae895fde3e))
* **api:** rendre la garde self-action insensible à la casse et stabiliser le tri admin ([5d5c1f7](https://github.com/LignacAntony/streampulse/commit/5d5c1f7a839b321c8c4a564fb94649a1408ffd72))
* **api:** traite les retours de review sur le cycle de vie du direct ([5ae037c](https://github.com/LignacAntony/streampulse/commit/5ae037cac9943e379180d250923c8e8f14be82ca))
* **api:** traite les retours de review sur le domaine streaming ([8027aea](https://github.com/LignacAntony/streampulse/commit/8027aeaf48b13c68e3b40aeefc14ee39bc95cacc))
* **api:** utiliser zerolog pour la supervision admin ([cab35d1](https://github.com/LignacAntony/streampulse/commit/cab35d18a432743eb5050b8b1f0e6b93a072ac25))
* **api:** verifie l'erreur d'ecriture du flux SSE (errcheck) ([3c94dbe](https://github.com/LignacAntony/streampulse/commit/3c94dbe9e045904da6c3a3fb950338a3e147102b))
* **mobile:** éviter le spinner figé de la liste admin sous mutation concurrente ([8493268](https://github.com/LignacAntony/streampulse/commit/849326864b7982cc2d3eb1fb9c2371b5459b432e))
* **mobile:** fiabiliser les chargements concurrents de la liste admin ([0ff46a0](https://github.com/LignacAntony/streampulse/commit/0ff46a0ccdee71cf26f349c220821b66193ab93e))
* **mobile:** fiabiliser les mutations concurrentes et les retours d'erreur de la liste admin ([00e9925](https://github.com/LignacAntony/streampulse/commit/00e9925fb44d1a43a8459dc966997f77d71003cd))

## [1.1.0](https://github.com/LignacAntony/streampulse/compare/v1.0.0...v1.1.0) (2026-06-29)


### Features

* 12-factor app config (STR-23) ([#101](https://github.com/LignacAntony/streampulse/issues/101)) ([38a9f1a](https://github.com/LignacAntony/streampulse/commit/38a9f1a0ccd5671a5658fcfd268d406956bde0ca))
* Add CORS_ALLOWED_ORIGINS environment variable to API service ([15958b9](https://github.com/LignacAntony/streampulse/commit/15958b97b4199846fd0aa61d49bcdcb1c97febb6))
* Add Profile API and update profile handling ([2824d19](https://github.com/LignacAntony/streampulse/commit/2824d19aad886a8785b6ed3e070383d00c84b201))
* **api:** configurer OpenAPI et le client généré ([bd387ad](https://github.com/LignacAntony/streampulse/commit/bd387ad8fbcf015652a3ccef890eba14264ec8e1))
* **api:** configurer OpenAPI et le client généré ([ba5dfd2](https://github.com/LignacAntony/streampulse/commit/ba5dfd2808a6c8ef517513fca8cc971d286fc133))
* **app:** ajouter écran d'accueil /welcome et bouton retour sur /register ([6f9a678](https://github.com/LignacAntony/streampulse/commit/6f9a6781d7e80a04fc84fbe84eb3a19e53f4b1ff))
* **app:** ajouter l'écran d'inscription Flutter (STR-36) ([c8556c1](https://github.com/LignacAntony/streampulse/commit/c8556c11c2eb79de1ebd9d77ddd2c54c4dec0e85))
* **app:** ajouter l'écran d'inscription Flutter (STR-36) ([5b2dd63](https://github.com/LignacAntony/streampulse/commit/5b2dd631f604141d5ae982a9a49c2aeafae4c555))
* **app:** ajouter les onglets Connexion/Inscription sur /register ([3b74659](https://github.com/LignacAntony/streampulse/commit/3b74659dca7b0398df1de39ac718c9132b5fe691))
* **app:** aligner /register sur la maquette et stub /login avec onglets ([c104ac0](https://github.com/LignacAntony/streampulse/commit/c104ac07f3db7a2eb0822ff25828d56fa9458520))
* **app:** demander et gérer le rôle Diffuseur via de nouvelles API e… ([#129](https://github.com/LignacAntony/streampulse/issues/129)) ([b9e1c53](https://github.com/LignacAntony/streampulse/commit/b9e1c53495da6843d2b7808218145dac64a07c68))
* **app:** implémenter les thèmes light et dark selon la charte StreamPulse ([17c5fb7](https://github.com/LignacAntony/streampulse/commit/17c5fb7690c8088a06eb7b5045c03d771970e6ff))
* **app:** initialiser le projet Flutter mobile avec Clean Architecture ([439731e](https://github.com/LignacAntony/streampulse/commit/439731e340dfe41e4bf313a7b6bb257328d9466e))
* **app:** mettre à jour Flutter vers 3.27.0 et ajuster la configuration ci ([bec54c1](https://github.com/LignacAntony/streampulse/commit/bec54c12ad08406e92907e12c07c28306ca1ed5c))
* **auth:** ajouter l'inscription utilisateur (STR-33) ([cbd808b](https://github.com/LignacAntony/streampulse/commit/cbd808b8f5170f3d09a2eec0921a5782ed80bdcc))
* **auth:** ajouter l'inscription utilisateur (STR-33) ([3e85881](https://github.com/LignacAntony/streampulse/commit/3e85881ef0be148e7d571d2ca231c247d12b7c5f))
* **auth:** ajouter la suppression de compte conforme au RGPD ([#130](https://github.com/LignacAntony/streampulse/issues/130)) ([17283f8](https://github.com/LignacAntony/streampulse/commit/17283f8746eabf80c3c0a45f21c5fa0093d08f57))
* **auth:** connexion sécurisée avec JWT côté mobile ([#121](https://github.com/LignacAntony/streampulse/issues/121)) ([388451a](https://github.com/LignacAntony/streampulse/commit/388451a58725efec5f38734ed7c15aea01f93e7b))
* **auth:** implement JWT authentication with access and refresh tokens ([#119](https://github.com/LignacAntony/streampulse/issues/119)) ([9446567](https://github.com/LignacAntony/streampulse/commit/9446567187432f657f5f6a12fbbe02305abaf36f))
* **auth:** implement registration form with validation and local environment configuration ([4e83e30](https://github.com/LignacAntony/streampulse/commit/4e83e302b2b7a9a881a5afa7636d737bd8aee053))
* **auth:** refactor registration and login screens with new form object and toast notifications ([3e1bd2d](https://github.com/LignacAntony/streampulse/commit/3e1bd2d2d03c7bd08f02b9b9dca93bb0b2a23321))
* **auth:** str-54-reinitialisation-du-mot-de-passe ([#120](https://github.com/LignacAntony/streampulse/issues/120)) ([d7347db](https://github.com/LignacAntony/streampulse/commit/d7347dbefa254ec91eff4d15c352fcade03e23d8))
* **docs:** add ADR 006 for handler/service/repository architecture pattern ([521c523](https://github.com/LignacAntony/streampulse/commit/521c523dc353e849986be48669f19db1b6cf6b77))
* Implement CORS middleware and update profile handling with error management ([48a92f9](https://github.com/LignacAntony/streampulse/commit/48a92f9deb622ef99dd5e1bd6c92eda575245ec4))
* merge develop in profil branch ([a86f74d](https://github.com/LignacAntony/streampulse/commit/a86f74d4568a91731b92230fd9a21dd16fabc0ad))
* **mobile:** 92 us 01 06 initialisation du projet flutter mobile ([867b17f](https://github.com/LignacAntony/streampulse/commit/867b17f575eb5c86d4bd1a53b8d915064806913e))
* **profile:** add tests for user profile management and create ADR for profile handling ([a795ce5](https://github.com/LignacAntony/streampulse/commit/a795ce5115d1b02078825c13e03e4a4f47461823))
* **profile:** add user profile endpoints and response schemas to OpenAPI ([9f7cc02](https://github.com/LignacAntony/streampulse/commit/9f7cc02e145a05ee95cd40acbd00798f7d507700))
* **profile:** gestion du profil utilisateur ([e1d0c43](https://github.com/LignacAntony/streampulse/commit/e1d0c431f4e4b77c26b41b7179984863fc6e0617))
* **profile:** implement user profile management with screens, controllers, and data sources ([05e954d](https://github.com/LignacAntony/streampulse/commit/05e954de3895bbddbcecf7b6d6128aef6f994f25))
* **profiles:** implement user profile management with CRUD operations and database migrations ([1a40dc4](https://github.com/LignacAntony/streampulse/commit/1a40dc408f9d7318c00959e037ceb447024239a2))


### Bug Fixes

* **api:** durcir l'exposition OpenAPI et fiabiliser la génération du client ([2dcd1c5](https://github.com/LignacAntony/streampulse/commit/2dcd1c5d211a4af1a6ad81e5fc13fc3636235f29))
* **auth:** some lint errors ([350c2b8](https://github.com/LignacAntony/streampulse/commit/350c2b865461c20fc168937c3eccb52fffe1bd79))
* **ci:** exclure les fichiers générés de l'analyse gosec et sécuriser les logs HTTP ([#123](https://github.com/LignacAntony/streampulse/issues/123)) ([ea21984](https://github.com/LignacAntony/streampulse/commit/ea219847611602815c0f94f3bb21bcf505708e18))
* **ci:** supprimer le commentaire nolint redondant dans httpjson.go ([#124](https://github.com/LignacAntony/streampulse/issues/124)) ([66c369e](https://github.com/LignacAntony/streampulse/commit/66c369e8ce113a0d13f51ac67de5656623d32c46))

## 1.0.0 (2026-05-04)


### Bug Fixes

* **docker:** ajouter l'image GHCR pour le service API ([#99](https://github.com/LignacAntony/streampulse/issues/99)) ([8df1130](https://github.com/LignacAntony/streampulse/commit/8df11307bbea3d254f475121215165f5f1259ed7))

## Changelog

All notable changes to StreamPulse will be documented in this file.

See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.
