import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/network/sse_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../profile/presentation/providers/profile_controller.dart';
import '../../data/datasources/broadcast_remote_data_source.dart';
import '../../data/repositories/broadcast_repository_impl.dart';
import '../../data/services/microphone_audio_publisher.dart';
import '../../domain/entities/broadcast_stats.dart';
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';
import '../../domain/services/broadcast_audio_publisher.dart';
import '../controllers/broadcast_session_controller.dart';
import '../providers/broadcast_notifier.dart';
import '../providers/current_broadcast.dart';
import 'create_stream_sheet.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

/// Tableau de bord du diffuseur (US-06-01, ADR 024 et ADR 027) : créer un flux,
/// lancer/arrêter le direct et pousser le microphone du téléphone en AAC/ADTS.
/// L'URL d'ingest reste disponible pour un encodeur externe.
///
/// [repository] et [sse] sont injectables pour les tests ; en production ils
/// sont construits depuis [DioClient] et [SecureStorage].
///
/// `ChangeNotifierProvider` local plutôt que câblage dans `app_providers.dart`
/// (même choix qu'`AdminStreamsScreen`) : l'état du dashboard n'a aucun usage
/// hors de cet onglet, et le laisser local garantit que la souscription SSE
/// meurt avec l'écran.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    this.repository,
    this.sse,
    this.audioPublisher,
  });

  final BroadcastRepository? repository;
  final SseConnector? sse;
  final BroadcastAudioPublisher? audioPublisher;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<BroadcastNotifier>(
      create: (ctx) => BroadcastNotifier(
        repository ??
            BroadcastRepositoryImpl(
              BroadcastRemoteDataSource(ctx.read<DioClient>().streamingApi),
            ),
        // Pas de SSE sur le web : l'adaptateur navigateur de Dio ne supporte
        // pas `ResponseType.stream`, la requête échoue immédiatement
        // (`net::ERR_FAILED`) et la relancer n'y changerait rien. Le notifier
        // bascule alors sur un rafraîchissement périodique.
        sse: sse ?? (kIsWeb ? null : SseClient(ctx.read<SecureStorage>())),
        audioPublisher: audioPublisher ??
            (kIsWeb
                ? const UnsupportedBroadcastAudioPublisher()
                : MicrophoneAudioPublisher()),
        // App-level : permet au lecteur de savoir qu'il ne doit pas rejouer un
        // flux qu'on diffuse depuis cet appareil (sinon la capture est coupée).
        currentBroadcast: ctx.read<CurrentBroadcast>(),
      ),
      child: const _DashboardBody(),
    );
  }
}

class _DashboardBody extends StatefulWidget {
  const _DashboardBody();

  @override
  State<_DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends State<_DashboardBody>
    with WidgetsBindingObserver {
  /// Fait battre l'affichage de la durée de direct. Actif uniquement lorsqu'un
  /// flux est en direct : inutile de reconstruire l'écran chaque seconde sinon.
  Timer? _ticker;

  /// Le direct peut s'arrêter sans action de l'utilisateur (micro définitivement
  /// perdu) : sans ce toast, la tuile passerait de « en direct » à « terminé »
  /// sans explication.
  StreamSubscription<BroadcastAudioFailure>? _audioFailureSubscription;

  /// Le diffuseur voit « Reconnexion audio… » pendant la coupure, mais rien ne
  /// lui disait, une fois revenu, combien de temps n'était pas parti (ADR 050).
  StreamSubscription<Duration>? _audioRecoverySubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final profile = context.read<ProfileController>();
      if (profile.profile == null && !profile.isLoading) {
        profile.load();
      }
      final notifier = context.read<BroadcastNotifier>();
      notifier.setActive(true);
      _audioFailureSubscription = notifier.audioFailures.listen((failure) {
        if (!mounted) return;
        // Deux fins de capture qui se ressemblent à l'écran, mais l'une laisse
        // un direct mort et l'autre un direct qui continue sans nous : le même
        // message pour les deux mentirait dans un cas sur deux.
        switch (failure.reason) {
          case BroadcastAudioEndReason.microphoneLost:
            showAuthErrorToast(
              context,
              'Diffusion arrêtée : le microphone n\'est plus disponible',
            );
          case BroadcastAudioEndReason.supersededByOtherSource:
            showAuthInfoToast(
              context,
              'Une autre source a pris le relais : le direct continue sans '
              'votre microphone.',
            );
        }
      });
      _audioRecoverySubscription = notifier.audioRecoveries.listen((coupure) {
        if (!mounted) return;
        final secondes = coupure.inSeconds;
        // Sous la seconde, l'annoncer serait du bruit : le diffuseur n'a rien
        // perdu d'intelligible et n'a rien à redire.
        if (secondes < 1) return;
        showAuthInfoToast(
          context,
          'Connexion rétablie — $secondes s n\'ont pas été diffusées.',
        );
      });
      notifier.load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_audioFailureSubscription?.cancel());
    unawaited(_audioRecoverySubscription?.cancel());
    _ticker?.cancel();
    super.dispose();
  }

  /// Coupe la souscription SSE quand l'application passe en arrière-plan et la
  /// rétablit au retour — une connexion HTTP ouverte n'a aucune valeur pendant
  /// que l'écran n'est pas regardé.
  ///
  /// **La diffusion, elle, ne s'arrête pas** (ADR 049). Quitter l'application
  /// pour aller ailleurs sur son téléphone est un geste normal en cours de
  /// direct ; c'est le service de premier plan Android qui maintient la capture
  /// micro. Le distinguo est entre « je vais ailleurs » et « je ferme » :
  ///
  ///   - `inactive` / `hidden` : rien. Sur le web, un simple changement
  ///     d'onglet navigateur produit `hidden` ; sur mobile il précède toujours
  ///     `paused`. Le traiter comme un départ coupait le direct en pleine
  ///     diffusion, sans que l'application ait été quittée.
  ///   - `paused` : l'application passe en arrière-plan. Le micro continue.
  ///   - `detached` : l'application est **fermée** (balayage depuis les
  ///     récents). Là le direct doit s'arrêter — personne ne diffuse depuis une
  ///     application qu'il vient de fermer. Best-effort : le processus meurt,
  ///     et si la requête ne part pas, le bail d'ingest du serveur prend le
  ///     relais.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final notifier = context.read<BroadcastNotifier>();
    notifier.setActive(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.detached) {
      unawaited(notifier.stopForAppClosed());
    }
  }

  /// (Dés)active le battement de seconde selon la présence d'un direct.
  void _syncTicker(bool hasLive) {
    if (hasLive && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasLive && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _onRefresh() => context.read<BroadcastNotifier>().refresh();

  Future<void> _onCreate() async {
    final values = await CreateStreamSheet.show(context);
    if (!mounted || values == null) return;

    final notifier = context.read<BroadcastNotifier>();
    try {
      await notifier.create(
        title: values.title,
        isPublic: values.isPublic,
        description: values.description,
        category: values.category,
      );
      if (!mounted) return;
      showAuthSuccessToast(context, 'Flux créé');
    } on ValidationException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } on ServerException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la création du flux');
    }
  }

  Future<void> _onStart(BroadcastStream stream) async {
    final notifier = context.read<BroadcastNotifier>();
    try {
      final started = await notifier.start(stream.id);
      if (!mounted) return;
      // `false` = no-op (une autre mutation était en vol) : rien n'a démarré,
      // annoncer un succès mentirait à l'utilisateur.
      if (started) showAuthSuccessToast(context, 'Vous êtes en direct');
    } on ConflictException {
      // Le backend renvoie 409 pour deux raisons distinctes — « un autre flux
      // est déjà en direct » et « ce flux n'est pas au repos ». On tranche sur
      // l'état local plutôt qu'en analysant la prose anglaise du serveur.
      if (!mounted) return;
      showAuthErrorToast(
        context,
        notifier.hasLiveStream
            ? 'Un autre flux est déjà en direct'
            : 'Ce flux n\'est plus démarrable',
      );
      // L'état local était périmé : on repart de la vérité serveur plutôt que
      // de laisser l'écran mentir.
      await notifier.refresh();
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } on ServerException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on MicrophonePermissionException {
      if (!mounted) return;
      showAuthErrorToast(
        context,
        'Autorisez le microphone pour démarrer le direct',
      );
    } on AudioEncoderUnsupportedException {
      if (!mounted) return;
      showAuthErrorToast(
        context,
        'La diffusion AAC n\'est pas disponible sur cet appareil',
      );
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec du démarrage');
    }
  }

  Future<void> _onStop(BroadcastStream stream) async {
    final notifier = context.read<BroadcastNotifier>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Arrêter « ${stream.title} » ?'),
        content: const Text('Les auditeurs seront déconnectés.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('dashboard_confirm_stop_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      final stopped = await notifier.stop(stream.id);
      if (!mounted) return;
      if (stopped) showAuthSuccessToast(context, 'Diffusion arrêtée');
    } on ConflictException {
      // Le flux n'était déjà plus en direct (arrêt par un administrateur) :
      // recharger suffit à réaligner l'écran.
      if (!mounted) return;
      showAuthInfoToast(context, 'Ce flux était déjà arrêté');
      await notifier.refresh();
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } on ServerException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de l\'arrêt');
    }
  }

  /// Régénère la clé d'ingest (US-06-04). L'ancienne cesse d'être acceptée
  /// immédiatement : la confirmation le dit, et rappelle que tout encodeur
  /// externe déjà configuré devra recevoir la nouvelle URL — sans quoi le
  /// diffuseur découvrirait la coupure à son prochain direct.
  Future<void> _onRotateKey(BroadcastStream stream) async {
    final notifier = context.read<BroadcastNotifier>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Régénérer la clé de diffusion ?'),
        content: const Text(
          'L\'ancienne clé cessera immédiatement de fonctionner. Si vous '
          'diffusez depuis un encodeur externe (OBS, ffmpeg, Mixxx), '
          'reconfigurez-le avec la nouvelle URL avant votre prochain direct.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('dashboard_confirm_rotate_key_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Régénérer'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      final rotated = await notifier.rotateKey(stream.id);
      if (!mounted) return;
      if (rotated) showAuthSuccessToast(context, 'Nouvelle clé générée');
    } on ConflictException {
      // Le flux est passé en direct entre l'ouverture du menu et la
      // confirmation : recharger réaligne l'écran sur la vérité serveur.
      if (!mounted) return;
      showAuthErrorToast(
        context,
        'Arrêtez la diffusion avant de régénérer la clé',
      );
      await notifier.refresh();
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } on ServerException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la régénération de la clé');
    }
  }

  /// Supprime un flux. Le backend fait une suppression douce (`archived_at`) et
  /// **termine la diffusion au passage** si le flux est en direct : la
  /// confirmation le dit explicitement plutôt que de laisser l'utilisateur
  /// couper son propre direct sans le savoir.
  Future<void> _onDelete(BroadcastStream stream) async {
    final notifier = context.read<BroadcastNotifier>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Supprimer « ${stream.title} » ?'),
        content: Text(
          stream.isLive
              ? 'Ce flux est en direct : la diffusion sera arrêtée et les '
                  'auditeurs déconnectés. Cette action est définitive.'
              : 'Le flux disparaîtra de votre tableau de bord. Cette action '
                  'est définitive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            key: const Key('dashboard_confirm_delete_button'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    try {
      final deleted = await notifier.delete(stream.id);
      if (!mounted) return;
      if (deleted) showAuthSuccessToast(context, 'Flux supprimé');
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } on ServerException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la suppression');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileController>();
    final notifier = context.watch<BroadcastNotifier>();
    _syncTicker(notifier.hasLiveStream);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tableau de bord'),
        actions: [
          if (_isBroadcaster(profile))
            AccessibleIconButton(
              key: const Key('dashboard_create_button'),
              icon: Icons.add,
              label: 'Créer un flux',
              onPressed: notifier.creating ? null : _onCreate,
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _buildBody(context, profile, notifier),
        ),
      ),
    );
  }

  /// Le rôle vient du profil serveur, seule source de vérité : un utilisateur
  /// promu diffuseur pendant sa session voit l'onglet s'activer au prochain
  /// chargement du profil.
  bool _isBroadcaster(ProfileController profile) {
    final role = profile.profile?.role;
    return role == 'broadcaster' || role == 'admin';
  }

  Widget _buildBody(
    BuildContext context,
    ProfileController profile,
    BroadcastNotifier notifier,
  ) {
    if (profile.profile == null && profile.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Onglet public : un visiteur non connecté y accède aussi.
    if (profile.profile == null) {
      return _MessageView(
        icon: Icons.lock_outline,
        title: 'Connectez-vous',
        message: 'Le tableau de bord est réservé aux comptes diffuseurs.',
        actionLabel: 'Se connecter',
        actionKey: const Key('dashboard_login_button'),
        onAction: () => context.go('/login'),
      );
    }

    if (!_isBroadcaster(profile)) {
      return _MessageView(
        icon: Icons.mic_none_outlined,
        title: 'Diffusez vos propres flux',
        message: 'Demandez le rôle diffuseur pour créer et lancer un direct.',
        actionLabel: 'Devenir diffuseur',
        actionKey: const Key('dashboard_become_broadcaster_button'),
        onAction: () => context.push('/broadcaster-request'),
      );
    }

    if (notifier.loading && notifier.streams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.error != null && notifier.streams.isEmpty) {
      return _MessageView(
        icon: notifier.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        title: 'Chargement impossible',
        message: notifier.error!,
        actionLabel: 'Réessayer',
        actionKey: const Key('dashboard_retry_button'),
        onAction: () => context.read<BroadcastNotifier>().load(),
      );
    }

    if (notifier.streams.isEmpty) {
      return _MessageView(
        icon: Icons.podcasts_outlined,
        title: 'Aucun flux',
        message: 'Créez un flux pour commencer à diffuser.',
        actionLabel: 'Créer mon flux',
        actionKey: const Key('dashboard_empty_create_button'),
        onAction: _onCreate,
      );
    }

    return ListView.separated(
      key: const Key('dashboard_streams_list'),
      // Conserve le pull-to-refresh même quand la liste ne remplit pas
      // l'écran (un diffuseur a typiquement un ou deux flux).
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: notifier.streams.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final stream = notifier.streams[index];
        return _StreamCard(
          stream: stream,
          // Un seul direct par diffuseur : on désactive le démarrage des
          // autres flux plutôt que de laisser l'utilisateur découvrir la
          // règle par un 409.
          blockedByOtherLive: notifier.hasLiveStream && !stream.isLive,
          mutating: notifier.mutatingId == stream.id,
          // Tant qu'une mutation quelconque est en vol, les autres tuiles sont
          // neutralisées : leur flux n'est pas encore à jour localement, un tap
          // partirait sur un état périmé.
          otherMutationInFlight:
              notifier.isMutating && notifier.mutatingId != stream.id,
          // L'audience ne concerne que le direct en cours.
          stats: stream.isLive ? notifier.stats : null,
          audioState: notifier.audioState,
          publishingAudio: notifier.isPublishingAudio(stream.id),
          // Sur une plateforme sans capture (web), `prepare()` échouerait après
          // coup : mieux vaut neutraliser le bouton et le dire.
          audioSupported: notifier.audioSupported,
          onStart: () => _onStart(stream),
          onStop: () => _onStop(stream),
          onRotateKey: () => _onRotateKey(stream),
          onDelete: () => _onDelete(stream),
        );
      },
    );
  }
}

class _StreamCard extends StatelessWidget {
  const _StreamCard({
    required this.stream,
    required this.blockedByOtherLive,
    required this.mutating,
    required this.otherMutationInFlight,
    required this.stats,
    required this.audioState,
    required this.publishingAudio,
    required this.audioSupported,
    required this.onStart,
    required this.onStop,
    required this.onRotateKey,
    required this.onDelete,
  });

  final BroadcastStream stream;
  final bool blockedByOtherLive;
  final bool mutating;
  final bool otherMutationInFlight;

  /// Audience du direct, ou null si le flux n'est pas en direct ou si aucune
  /// mesure n'est encore arrivée.
  final BroadcastStats? stats;
  final BroadcastAudioState audioState;
  final bool publishingAudio;

  /// Faux sur une plateforme incapable de capturer le micro : le démarrage est
  /// neutralisé plutôt que rejeté après coup par un toast fugace.
  final bool audioSupported;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRotateKey;
  final VoidCallback onDelete;

  /// Vrai dès qu'une mutation touche cette carte ou une autre : dans les deux
  /// cas ses actions doivent être neutralisées.
  bool get _busy => mutating || otherMutationInFlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final duration = stream.liveDurationAt(DateTime.now());

    return Card(
      key: Key('dashboard_stream_card_${stream.id}'),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(stream.title, style: text.titleMedium)),
                _StatusBadge(status: stream.status),
                PopupMenuButton<String>(
                  key: Key('dashboard_stream_menu_${stream.id}'),
                  enabled: !_busy,
                  tooltip: 'Actions',
                  onSelected: (value) {
                    if (value == 'rotate-key') onRotateKey();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    // Visible aussi sur un flux terminé depuis l'ADR 048 :
                    // celui-ci est relançable, donc sa clé redevient un secret
                    // vivant qu'on peut vouloir renouveler avant de rediffuser.
                    // Sur un direct l'entrée reste visible mais inerte : la
                    // règle se découvre dans le menu plutôt que par un 409.
                    PopupMenuItem(
                      key: Key('dashboard_rotate_key_item_${stream.id}'),
                      value: 'rotate-key',
                      enabled: !stream.isLive,
                      child: Row(
                        children: [
                          const Icon(Icons.key_outlined),
                          const SizedBox(width: 12),
                          // Expanded : le libellé du cas « en direct » est
                          // plus long que la largeur naturelle du menu.
                          Expanded(
                            child: Text(
                              stream.isLive
                                  ? 'Régénérer la clé\n(arrêtez la diffusion)'
                                  : 'Régénérer la clé',
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      key: Key('dashboard_delete_item_${stream.id}'),
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, color: colors.error),
                          const SizedBox(width: 12),
                          const Text('Supprimer'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  stream.isPublic ? 'Public' : 'Privé',
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                if (stream.category != null) ...[
                  Text(
                    ' · ',
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    streamCategoryLabel(stream.category!),
                    style: text.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (duration != null) ...[
                  const Spacer(),
                  Text(
                    key: Key('dashboard_stream_timer_${stream.id}'),
                    _formatDuration(duration),
                    style: text.titleSmall?.copyWith(
                      color: colors.primary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ],
            ),
            // Présente dès que le flux est en direct, même sans mesure : la
            // faire apparaître au premier fetch ferait sauter la mise en page,
            // et `_cancelStats()` la ferait disparaître au passage en
            // arrière-plan. C'est la métrique cœur de l'US, elle reste à sa
            // place et affiche « — » en attendant.
            if (stream.isLive) ...[
              const SizedBox(height: 12),
              _MicrophoneStatusRow(
                streamId: stream.id,
                state: audioState,
                publishing: publishingAudio,
              ),
              const SizedBox(height: 8),
              _AudienceRow(streamId: stream.id, stats: stats),
            ],
            // Affichée aussi sur un flux terminé (ADR 048) : il est
            // relançable, donc l'encodeur externe qui pousse sur cette URL
            // reste un chemin valide. La masquer laissait croire le contraire.
            if (stream.streamSourceUrl != null) ...[
              const SizedBox(height: 12),
              _IngestUrlRow(
                streamId: stream.id,
                sourceUrl: stream.streamSourceUrl!,
              ),
            ],
            const SizedBox(height: 12),
            // Un flux terminé se relance (ADR 048) : même bouton, libellé
            // différent. Auparavant la tuile n'offrait plus rien et invitait à
            // recréer un flux — ce qui obligeait à rediffuser une clé neuve
            // après le moindre direct coupé par le bail d'ingest.
            SizedBox(
              width: double.infinity,
              child: stream.isLive
                  ? FilledButton.tonalIcon(
                      key: Key('dashboard_stop_button_${stream.id}'),
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.errorContainer,
                        foregroundColor: colors.onErrorContainer,
                      ),
                      onPressed: _busy ? null : onStop,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Arrêter la diffusion'),
                    )
                  : FilledButton.icon(
                      key: Key('dashboard_start_button_${stream.id}'),
                      onPressed: _busy || blockedByOtherLive || !audioSupported
                          ? null
                          : onStart,
                      icon: Icon(
                        stream.isEnded
                            ? Icons.replay_circle_filled_outlined
                            : Icons.play_circle_outline,
                      ),
                      label: Text(
                        stream.isEnded
                            ? 'Relancer la diffusion'
                            : 'Démarrer la diffusion',
                      ),
                    ),
            ),
            if (!audioSupported && stream.canStart) ...[
              const SizedBox(height: 6),
              Text(
                key: Key('dashboard_audio_unsupported_${stream.id}'),
                'Diffusion disponible depuis l\'application mobile. '
                'L\'URL d\'ingest ci-dessus reste utilisable par un encodeur '
                'externe.',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ] else if (blockedByOtherLive && stream.canStart) ...[
              const SizedBox(height: 6),
              Text(
                'Un autre flux est en direct',
                style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MicrophoneStatusRow extends StatelessWidget {
  const _MicrophoneStatusRow({
    required this.streamId,
    required this.state,
    required this.publishing,
  });

  final String streamId;
  final BroadcastAudioState state;
  final bool publishing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (IconData, String, Color) inactive = (
      Icons.devices_outlined,
      'Microphone de cet appareil inactif',
      colors.onSurfaceVariant,
    );
    final (IconData icon, String label, Color color) = !publishing
        ? inactive
        : switch (state) {
            BroadcastAudioState.connecting => (
                Icons.mic_none_outlined,
                'Connexion du microphone…',
                colors.primary,
              ),
            BroadcastAudioState.reconnecting => (
                Icons.wifi_tethering_error_outlined,
                'Reconnexion audio…',
                colors.tertiary,
              ),
            BroadcastAudioState.live => (
                Icons.mic_outlined,
                'Microphone diffusé',
                colors.primary,
              ),
            BroadcastAudioState.failed => (
                Icons.mic_off_outlined,
                'Diffusion du micro interrompue',
                colors.error,
              ),
            BroadcastAudioState.superseded => (
                Icons.cast_connected_outlined,
                'Une autre source alimente ce direct',
                colors.tertiary,
              ),
            // Fenêtre courte entre l'arrêt du micro et la remise à zéro de
            // `publishing` par le contrôleur : la ligne inactive est plus juste
            // qu'un état d'erreur, l'arrêt étant volontaire.
            BroadcastAudioState.idle => inactive,
          };

    return Column(
      key: Key('dashboard_microphone_status_$streamId'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label, style: text.bodySmall?.copyWith(color: color)),
            ),
          ],
        ),
        // La reprise est bornée (cf. MicrophoneAudioPublisher) : le dire évite
        // de laisser croire à une reconnexion indéfinie, et prépare
        // l'utilisateur à l'arrêt automatique si le réseau ne revient pas.
        if (publishing && state == BroadcastAudioState.reconnecting) ...[
          const SizedBox(height: 4),
          Text(
            'Le direct s\'arrêtera si la reconnexion échoue.',
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Audience du direct : auditeurs connectés et pic depuis le démarrage.
///
/// Le libellé reste volontairement prudent — « estimé » — parce que le compte
/// l'est réellement : HLS n'a pas de connexion persistante, deux lecteurs
/// derrière la même adresse publique comptent pour un, et un auditeur parti met
/// quelques dizaines de secondes à disparaître (cf. ADR 025).
class _AudienceRow extends StatelessWidget {
  const _AudienceRow({required this.streamId, required this.stats});

  final String streamId;

  /// Null tant qu'aucune mesure n'est arrivée, ou pendant un passage en
  /// arrière-plan : la ligne reste alors affichée avec des tirets.
  final BroadcastStats? stats;

  static const String _explanation =
      'Estimation basée sur les requêtes récentes : deux auditeurs derrière '
      'la même connexion comptent pour un, et un auditeur parti met une '
      'demi-minute à disparaître.';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final measured = stats;

    // Le pic dérive exactement des mêmes mesures que le compteur courant : il
    // est tout aussi estimé, et le libellé ne doit pas laisser croire l'inverse.
    return Tooltip(
      message: _explanation,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.headphones_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 8),
            Text(
              key: Key('dashboard_listeners_$streamId'),
              measured == null ? '—' : '${measured.listeners}',
              style: text.titleMedium?.copyWith(color: colors.primary),
            ),
            const SizedBox(width: 6),
            Text(
              measured != null && measured.listeners > 1
                  ? 'auditeurs estimés'
                  : 'auditeur estimé',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const Spacer(),
            Icon(Icons.trending_up, size: 14, color: colors.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              key: Key('dashboard_peak_$streamId'),
              measured == null ? 'Pic : —' : 'Pic : ${measured.peak}',
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(width: 6),
            Icon(Icons.info_outline, size: 14, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Affiche l'URL d'ingest sans exposer la clé de diffusion par défaut.
///
/// `stream_key` est un secret de type bearer : quiconque la détient peut
/// diffuser à la place du propriétaire, et **aucun endpoint de rotation
/// n'existe** aujourd'hui. Elle reste donc masquée jusqu'à une action
/// explicite, et la révélation se referme d'elle-même — un partage d'écran ou
/// une capture ne doit pas l'emporter par accident.
///
/// La copie place l'URL entière dans le presse-papier sans jamais l'afficher.
/// Limite assumée : sur Android le presse-papier est lisible par d'autres
/// applications, et `Clipboard.setData` n'expose pas le drapeau « contenu
/// sensible » d'Android 13+.
class _IngestUrlRow extends StatefulWidget {
  const _IngestUrlRow({required this.streamId, required this.sourceUrl});

  final String streamId;
  final String sourceUrl;

  @override
  State<_IngestUrlRow> createState() => _IngestUrlRowState();
}

class _IngestUrlRowState extends State<_IngestUrlRow> {
  static const Duration _revealDuration = Duration(seconds: 15);

  bool _revealed = false;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _toggleReveal() {
    _hideTimer?.cancel();
    setState(() => _revealed = !_revealed);
    if (_revealed) {
      _hideTimer = Timer(_revealDuration, () {
        if (mounted) setState(() => _revealed = false);
      });
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.sourceUrl));
    if (!mounted) return;
    // Le toast ne réécrit surtout pas la valeur copiée.
    showAuthSuccessToast(context, 'URL d\'ingest copiée');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'URL d\'ingest',
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  key: Key('dashboard_ingest_url_${widget.streamId}'),
                  _revealed
                      ? widget.sourceUrl
                      : maskIngestUrl(widget.sourceUrl),
                  // Révélée, l'URL doit être lisible en entier : la tronquer
                  // rendrait le bouton « révéler » inutile. Masquée, deux
                  // lignes suffisent et gardent la carte compacte.
                  maxLines: _revealed ? null : 2,
                  overflow:
                      _revealed ? TextOverflow.visible : TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          AccessibleIconButton(
            key: Key('dashboard_reveal_key_${widget.streamId}'),
            icon: _revealed
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            // « Révéler 15 s » ne dit pas ce qui va s'afficher — or c'est une
            // clé secrète, et l'annoncer compte.
            label: _revealed
                ? 'Masquer la clé de diffusion'
                : 'Révéler la clé de diffusion pendant 15 secondes',
            tooltip: _revealed ? 'Masquer' : 'Révéler 15 s',
            onPressed: _toggleReveal,
          ),
          AccessibleIconButton(
            key: Key('dashboard_copy_key_${widget.streamId}'),
            icon: Icons.copy_outlined,
            label: 'Copier l\'URL de diffusion',
            onPressed: _copy,
          ),
        ],
      ),
    );
  }
}

/// Remplace la clé de diffusion par des points, en laissant les 4 derniers
/// caractères pour que le diffuseur puisse distinguer deux flux sans révéler
/// le secret.
String maskIngestUrl(String sourceUrl) {
  final separator = sourceUrl.lastIndexOf('/');
  if (separator == -1 || separator == sourceUrl.length - 1) {
    return '••••';
  }
  final prefix = sourceUrl.substring(0, separator + 1);
  final key = sourceUrl.substring(separator + 1);
  if (key.length <= 4) return '$prefix••••';
  return '$prefix${'•' * 10}${key.substring(key.length - 4)}';
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Trois états, trois traitements distincts. `PRÊT` et `TERMINÉ` partageaient
    // la même couleur : seul le mot les séparait, alors que l'un est
    // actionnable et l'autre non.
    final (Color background, Color foreground) = switch (status) {
      'live' => (colors.error, colors.onError),
      'idle' => (colors.primaryContainer, colors.onPrimaryContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  String _label(String status) {
    switch (status) {
      case 'live':
        return 'EN DIRECT';
      case 'ended':
        return 'TERMINÉ';
      default:
        return 'PRÊT';
    }
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.actionKey,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Key? actionKey;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      // Garde le pull-to-refresh actif sur les états vides et d'erreur.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(icon, size: 64, color: colors.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: text.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 24),
          Center(
            child: FilledButton(
              key: actionKey,
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}
