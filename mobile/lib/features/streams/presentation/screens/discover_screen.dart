import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../../../playlists/presentation/providers/playlist_queue_controller.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../recommendations/data/datasources/recommendation_remote_data_source.dart';
import '../../../recommendations/data/repositories/recommendation_repository_impl.dart';
import '../../../recommendations/domain/repositories/recommendation_repository.dart';
import '../../../recommendations/presentation/providers/recommendations_controller.dart';
import '../../../recommendations/presentation/widgets/recommended_track_tile.dart';
import '../../../tracks/domain/entities/public_track.dart';
import '../providers/discover_notifier.dart';
import '../../../../core/widgets/message_view.dart';
import '../widgets/stream_tile.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({
    super.key,
    this.recommendationRepository,
    this.isAuthenticated,
  });

  /// Injectable pour les tests (STR-250). En production, construit depuis
  /// [DioClient].
  final RecommendationRepository? recommendationRepository;

  /// Force l'état d'authentification (tests). En production, résolu depuis
  /// [SecureStorage].
  final bool? isAuthenticated;

  @override
  Widget build(BuildContext context) {
    // Contrôleur « Pour toi » local à l'écran (même patron que la Bibliothèque
    // avant STR-250) : la section vit désormais dans « Découvrir », au-dessus
    // des pistes publiques.
    return ChangeNotifierProvider<RecommendationsController>(
      create: (ctx) => RecommendationsController(
        recommendationRepository ??
            RecommendationRepositoryImpl(
              RecommendationRemoteDataSource(ctx.read<DioClient>().dio),
            ),
      ),
      child: _DiscoverView(forcedAuth: isAuthenticated),
    );
  }
}

/// Nombre maximum de recommandations affichées dans « Pour toi » : les premières
/// de la liste (les mieux classées par le serveur). Une vitrine, pas un
/// catalogue — la bibliothèque reste l'endroit pour tout parcourir.
const int _maxRecommendations = 8;

class _DiscoverView extends StatefulWidget {
  const _DiscoverView({this.forcedAuth});

  final bool? forcedAuth;

  @override
  State<_DiscoverView> createState() => _DiscoverViewState();
}

class _DiscoverViewState extends State<_DiscoverView> {
  static const String _discoverLocation = '/discover';

  late final DiscoverNotifier _notifier;
  late final AppLifecycleListener _lifecycleListener;
  GoRouter? _router;
  bool _appResumed = true;

  // Sections repliables « Pour toi » / « Pistes publiques » (dépliées par défaut).
  bool _recosExpanded = true;
  bool _publicExpanded = true;

  @override
  void initState() {
    super.initState();
    _notifier = context.read<DiscoverNotifier>();
    _lifecycleListener = AppLifecycleListener(onStateChange: (state) {
      _appResumed = state == AppLifecycleState.resumed;
      _syncPolling();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      _syncPolling();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `maybeOf` : l'écran peut être monté hors d'un GoRouter (tests).
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_syncPolling);
      _router = router?..routerDelegate.addListener(_syncPolling);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_syncPolling);
    _lifecycleListener.dispose();
    _notifier.stopPolling();
    super.dispose();
  }

  void _syncPolling() {
    final onDiscover =
        _router?.routerDelegate.currentConfiguration.uri.path ==
            _discoverLocation;
    if (_appResumed && onDiscover) {
      _notifier.startPolling();
    } else {
      _notifier.stopPolling();
    }
  }

  /// Flux + pistes publiques (publics, invité compris) et recommandations
  /// (authentifiées) chargés ensemble. « Pour toi » n'est tenté que pour un
  /// utilisateur connecté : la route est `RequireAuth`, un invité récolterait un
  /// 401 sans rien à afficher.
  Future<void> _load() async {
    final forced = widget.forcedAuth;
    final authenticated =
        forced ?? (await context.read<SecureStorage>().getAccessToken()) != null;
    if (!mounted) return;
    await Future.wait([
      _notifier.load(),
      if (authenticated) context.read<RecommendationsController>().load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<DiscoverNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Découvrir')),
      body: SafeArea(
        child: ResponsiveContent(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _buildBody(context, notifier),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, DiscoverNotifier notifier) {
    if (notifier.isLoading &&
        notifier.streams.isEmpty &&
        notifier.publicTracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.hasError &&
        notifier.streams.isEmpty &&
        notifier.publicTracks.isEmpty) {
      return MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: _notifier.load,
      );
    }

    final recommendations = context.watch<RecommendationsController>();
    // « Pour toi » : les premières recommandations (mieux classées), plafonnées —
    // une vitrine en haut de « Découvrir », pas la liste complète.
    final recos =
        recommendations.items.take(_maxRecommendations).toList(growable: false);

    if (notifier.isEmpty && recos.isEmpty) {
      return const MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Rien à découvrir pour le moment',
      );
    }

    final text = Theme.of(context).textTheme;
    final publicTracks = notifier.publicTracks;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (notifier.streams.isNotEmpty) ...[
          Text('En direct',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final stream in notifier.streams) ...[
            StreamTile(stream: stream),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
        // « Pour toi » (US-09-04, déplacée dans « Découvrir » en STR-250) :
        // masquée sans contenu, placée au-dessus des pistes publiques.
        if (recos.isNotEmpty) ...[
          _CollapsibleHeader(
            title: 'Pour toi',
            count: recos.length,
            expanded: _recosExpanded,
            onToggle: () => setState(() => _recosExpanded = !_recosExpanded),
          ),
          _CollapsibleContent(
            expanded: _recosExpanded,
            child: Column(
              children: [
                const SizedBox(height: 8),
                for (var i = 0; i < recos.length; i++)
                  RecommendedTrackTile(
                    recommended: recos[i],
                    // La liste affichée (plafonnée) part en file, à partir de
                    // l'item touché : précédent/suivant et modes de lecture
                    // gardent un sens.
                    onPlay: () => context.read<PlaylistQueueController>().play(
                          tracks:
                              recos.map((r) => r.track).toList(growable: false),
                          sourceName: 'Pour toi',
                          startIndex: i,
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (publicTracks.isNotEmpty) ...[
          _CollapsibleHeader(
            title: 'Pistes publiques',
            count: publicTracks.length,
            expanded: _publicExpanded,
            onToggle: () => setState(() => _publicExpanded = !_publicExpanded),
          ),
          _CollapsibleContent(
            expanded: _publicExpanded,
            child: Column(
              children: [
                const SizedBox(height: 8),
                for (var i = 0; i < publicTracks.length; i++)
                  _PublicTrackTile(
                    track: publicTracks[i],
                    onPlay: () => context.read<PlaylistQueueController>().play(
                          tracks:
                              publicTracks.map((t) => t.toTrack()).toList(),
                          sourceName: 'Pistes publiques',
                          startIndex: i,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// En-tête de section repliable : titre + compteur discret + chevron qui pivote.
/// Toute la ligne est tappable.
class _CollapsibleHeader extends StatelessWidget {
  const _CollapsibleHeader({
    required this.title,
    required this.count,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      label: '$title, ${expanded ? 'réduire' : 'développer'} la section',
      onTap: onToggle,
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: text.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenu d'une section repliable : anime la hauteur entre le contenu complet
/// et zéro, avec un fondu, quand [expanded] change.
class _CollapsibleContent extends StatelessWidget {
  const _CollapsibleContent({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: expanded ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: expanded ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}

class _PublicTrackTile extends StatelessWidget {
  const _PublicTrackTile({required this.track, required this.onPlay});

  final PublicTrack track;
  final VoidCallback onPlay;

  String _formatDuration(int? seconds) {
    if (seconds == null) return '';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isCurrent = context.select<PlaylistQueueController, bool>(
      (queue) => queue.hasQueue && queue.currentTrack?.id == track.id,
    );

    return ListTile(
      key: Key('public_track_tile_${track.id}'),
      onTap: onPlay,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.surfaceContainerHighest,
        child: Icon(
          isCurrent ? Icons.graphic_eq : Icons.music_note,
          color: isCurrent ? colors.primary : colors.onSurfaceVariant,
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? TextStyle(color: colors.primary) : null,
      ),
      subtitle: Text(
        [
          if (track.artist != null) track.artist!,
          track.ownerName,
          if (track.durationS != null) _formatDuration(track.durationS),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) => _onMenuAction(context, value),
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'add_to_playlist',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.playlist_add),
              title: Text('Ajouter à une playlist'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onMenuAction(BuildContext context, String action) async {
    if (action != 'add_to_playlist') return;
    final repo = context.read<PlaylistRepository>();
    final playlistId = await AddToPlaylistSheet.show(
      context,
      loadPlaylists: repo.list,
    );
    if (playlistId == null || !context.mounted) return;
    try {
      await repo.addTrack(playlistId, track.id);
      if (!context.mounted) return;
      showAuthSuccessToast(context, 'Piste ajoutée à la playlist');
    } on ConflictException {
      if (!context.mounted) return;
      showAuthInfoToast(context, 'Cette piste est déjà dans la playlist');
    } catch (e) {
      if (!context.mounted) return;
      showAuthErrorToast(context, 'Impossible d\'ajouter la piste');
    }
  }
}
