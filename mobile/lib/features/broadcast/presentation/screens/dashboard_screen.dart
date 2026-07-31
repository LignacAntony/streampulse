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
import '../../domain/entities/broadcast_stream.dart';
import '../../domain/repositories/broadcast_repository.dart';
import '../providers/broadcast_notifier.dart';
import 'create_stream_sheet.dart';

/// Tableau de bord du diffuseur (US-06-01, ADR 024) : créer un flux, lancer et
/// arrêter le direct, récupérer l'URL d'ingest à donner à son encodeur.
///
/// La capture micro depuis le téléphone ne fait PAS partie de cette US : le
/// diffuseur pousse son audio vers `stream_source_url` avec l'encodeur de son
/// choix (ffmpeg, BUTT, Mixxx). Cf. STR-156 pour le push mobile.
///
/// [repository] et [sse] sont injectables pour les tests ; en production ils
/// sont construits depuis [DioClient] et [SecureStorage].
///
/// `ChangeNotifierProvider` local plutôt que câblage dans `app_providers.dart`
/// (même choix qu'`AdminStreamsScreen`) : l'état du dashboard n'a aucun usage
/// hors de cet onglet, et le laisser local garantit que la souscription SSE
/// meurt avec l'écran.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.repository, this.sse});

  final BroadcastRepository? repository;
  final SseConnector? sse;

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
      notifier.load();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    super.dispose();
  }

  /// Coupe la souscription SSE quand l'application passe en arrière-plan et la
  /// rétablit au retour — une connexion HTTP ouverte n'a aucune valeur pendant
  /// que l'écran n'est pas regardé.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    context
        .read<BroadcastNotifier>()
        .setActive(state == AppLifecycleState.resumed);
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
      await notifier.start(stream.id);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Vous êtes en direct');
    } on ConflictException {
      // Le backend renvoie 409 pour deux raisons distinctes — « un autre flux
      // est déjà en direct » et « ce flux n'est pas au repos ». On tranche sur
      // l'état local plutôt qu'en analysant la prose anglaise du serveur.
      if (!mounted) return;
      showAuthErrorToast(
        context,
        notifier.hasLiveStream
            ? 'Un autre flux est déjà en direct'
            : "Ce flux n'est plus démarrable",
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
      await notifier.stop(stream.id);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Diffusion arrêtée');
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
      showAuthErrorToast(context, "Échec de l'arrêt");
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
            IconButton(
              key: const Key('dashboard_create_button'),
              icon: const Icon(Icons.add),
              tooltip: 'Créer un flux',
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
        message:
            'Demandez le rôle diffuseur pour créer et lancer un direct.',
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
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final stream = notifier.streams[index];
        return _StreamCard(
          stream: stream,
          // Un seul direct par diffuseur : on désactive le démarrage des
          // autres flux plutôt que de laisser l'utilisateur découvrir la
          // règle par un 409.
          blockedByOtherLive:
              notifier.hasLiveStream && !stream.isLive,
          mutating: notifier.mutatingId == stream.id,
          onStart: () => _onStart(stream),
          onStop: () => _onStop(stream),
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
    required this.onStart,
    required this.onStop,
  });

  final BroadcastStream stream;
  final bool blockedByOtherLive;
  final bool mutating;
  final VoidCallback onStart;
  final VoidCallback onStop;

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
                Expanded(
                  child: Text(stream.title, style: text.titleMedium),
                ),
                _StatusBadge(status: stream.status),
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
            if (stream.streamSourceUrl != null) ...[
              const SizedBox(height: 12),
              _IngestUrlRow(
                streamId: stream.id,
                sourceUrl: stream.streamSourceUrl!,
              ),
            ],
            const SizedBox(height: 12),
            // Un flux terminé n'a aucune action : le backend n'autorise que la
            // transition idle -> live, un bouton « Démarrer » ne pourrait que
            // renvoyer un 409.
            if (stream.isEnded)
              Text(
                'Diffusion terminée. Créez un nouveau flux pour rediffuser.',
                style: text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: stream.isLive
                    ? FilledButton.tonalIcon(
                        key: Key('dashboard_stop_button_${stream.id}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.errorContainer,
                          foregroundColor: colors.onErrorContainer,
                        ),
                        onPressed: mutating ? null : onStop,
                        icon: const Icon(Icons.stop_circle_outlined),
                        label: const Text('Arrêter la diffusion'),
                      )
                    : FilledButton.icon(
                        key: Key('dashboard_start_button_${stream.id}'),
                        onPressed:
                            mutating || blockedByOtherLive ? null : onStart,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Démarrer la diffusion'),
                      ),
              ),
            if (blockedByOtherLive && stream.isIdle) ...[
              const SizedBox(height: 6),
              Text(
                'Un autre flux est en direct',
                style: text.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
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
    showAuthSuccessToast(context, "URL d'ingest copiée");
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
                  "URL d'ingest",
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
          IconButton(
            key: Key('dashboard_reveal_key_${widget.streamId}'),
            icon: Icon(
              _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            ),
            tooltip: _revealed ? 'Masquer' : 'Révéler 15 s',
            onPressed: _toggleReveal,
          ),
          IconButton(
            key: Key('dashboard_copy_key_${widget.streamId}'),
            icon: const Icon(Icons.copy_outlined),
            tooltip: "Copier l'URL",
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
    final isLive = status == 'live';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isLive ? colors.error : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          color: isLive ? colors.onError : colors.secondary,
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
