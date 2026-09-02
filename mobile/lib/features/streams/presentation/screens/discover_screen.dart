import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/storage/secure_storage.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../broadcast/domain/entities/broadcast_stream.dart'
    show kStreamCategories;
import '../../../broadcast/presentation/screens/create_stream_sheet.dart'
    show streamCategoryLabel;
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../../../playlists/presentation/providers/playlist_queue_controller.dart';
import '../../../playlists/presentation/widgets/add_to_playlist_sheet.dart';
import '../../../recommendations/data/datasources/recommendation_remote_data_source.dart';
import '../../../recommendations/data/repositories/recommendation_repository_impl.dart';
import '../../../recommendations/domain/entities/recommended_track.dart';
import '../../../recommendations/domain/repositories/recommendation_repository.dart';
import '../../../recommendations/presentation/providers/recommendations_controller.dart';
import '../../../recommendations/presentation/widgets/recommended_track_tile.dart';
import '../../../tracks/domain/entities/public_track.dart';
import '../../domain/entities/live_stream.dart';
import '../providers/discover_notifier.dart';
import '../../../../core/widgets/collapsible_section.dart';
import '../../../../core/widgets/message_view.dart';
import '../../../../core/widgets/search_field.dart';
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

  // Recherche + filtre catégorie (« Tous » = null).
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedCategory;

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
    _searchController.dispose();
    super.dispose();
  }

  String _norm(String s) => s.trim().toLowerCase();

  /// Vrai si la requête est vide, ou si l'un des champs la contient (titre,
  /// auteur, diffuseur…).
  bool _textMatches(List<String?> fields) {
    final q = _norm(_query);
    if (q.isEmpty) return true;
    return fields.any((f) => f != null && _norm(f).contains(q));
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
          child: _buildBody(context, notifier),
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

    if (notifier.isEmpty && recommendations.items.isEmpty) {
      return const MessageView(
        icon: Icons.podcasts_outlined,
        message: 'Rien à découvrir pour le moment',
      );
    }

    // Liste fixe des catégories (miroir du backend) : les chips sont toujours
    // visibles, indépendamment des lives présents. Elles ne portent que sur les
    // flux — les pistes n'ont pas de catégorie dans les données.
    final activeCategory = _selectedCategory;

    // Flux : filtre catégorie + texte (titre / diffuseur).
    final streams = notifier.streams
        .where((s) =>
            (activeCategory == null || s.category == activeCategory) &&
            _textMatches([s.title, s.broadcasterName]))
        .toList(growable: false);

    // Les pistes n'ont pas de catégorie : une catégorie ≠ « Tous » ne peut donc
    // rien matcher côté pistes → on les masque (sinon le filtre semble sans
    // effet). Sans catégorie, « Pour toi » reste une vitrine plafonnée ; avec
    // requête, on cherche dans toute la liste (le plafond ne doit pas cacher un
    // résultat).
    final showTracks = activeCategory == null;
    final recosBase = _query.trim().isEmpty
        ? recommendations.items.take(_maxRecommendations).toList(growable: false)
        : recommendations.items;
    final recos = !showTracks
        ? const <RecommendedTrack>[]
        : recosBase
            .where((r) => _textMatches([r.track.title, r.track.artist]))
            .toList(growable: false);
    final publicTracks = !showTracks
        ? const <PublicTrack>[]
        : notifier.publicTracks
            .where((t) => _textMatches([t.title, t.artist, t.ownerName]))
            .toList(growable: false);

    final hasResults =
        streams.isNotEmpty || recos.isNotEmpty || publicTracks.isNotEmpty;

    return Column(
      children: [
        _SearchArea(
          controller: _searchController,
          categories: kStreamCategories,
          selectedCategory: activeCategory,
          onQueryChanged: (q) => setState(() => _query = q),
          onCategorySelected: (c) => setState(() => _selectedCategory = c),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: hasResults
                ? _resultsList(context, streams, recos, publicTracks)
                : _noResults(context),
          ),
        ),
      ],
    );
  }

  Widget _noResults(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // `ListView` (et non `Center`) pour que le pull-to-refresh reste actif et que
    // la barre de recherche au-dessus reste éditable même sans résultat.
    return ListView(
      children: [
        SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
        Icon(Icons.search_off_outlined,
            size: 56, color: colors.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(
          'Aucun résultat',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Essaie un autre mot ou une autre catégorie.',
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _resultsList(
    BuildContext context,
    List<LiveStream> streams,
    List<RecommendedTrack> recos,
    List<PublicTrack> publicTracks,
  ) {
    final text = Theme.of(context).textTheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        if (streams.isNotEmpty) ...[
          Text('En direct',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          for (final stream in streams) ...[
            StreamTile(stream: stream),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 16),
        ],
        // « Pour toi » (US-09-04, déplacée dans « Découvrir » en STR-250) :
        // masquée sans contenu, placée au-dessus des pistes publiques.
        if (recos.isNotEmpty) ...[
          CollapsibleHeader(
            title: 'Pour toi',
            count: recos.length,
            expanded: _recosExpanded,
            onToggle: () => setState(() => _recosExpanded = !_recosExpanded),
          ),
          CollapsibleContent(
            expanded: _recosExpanded,
            child: Column(
              children: [
                const SizedBox(height: 8),
                for (var i = 0; i < recos.length; i++)
                  RecommendedTrackTile(
                    recommended: recos[i],
                    // La liste affichée part en file, à partir de l'item touché :
                    // précédent/suivant et modes de lecture gardent un sens.
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
          CollapsibleHeader(
            title: 'Pistes publiques',
            count: publicTracks.length,
            expanded: _publicExpanded,
            onToggle: () => setState(() => _publicExpanded = !_publicExpanded),
          ),
          CollapsibleContent(
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

/// Barre de recherche (titre / auteur) + chips de catégories des flux, épinglée
/// en haut de « Découvrir ».
class _SearchArea extends StatelessWidget {
  const _SearchArea({
    required this.controller,
    required this.categories,
    required this.selectedCategory,
    required this.onQueryChanged,
    required this.onCategorySelected,
  });

  final TextEditingController controller;
  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<String?> onCategorySelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchField(
            controller: controller,
            onChanged: onQueryChanged,
            hintText: 'Rechercher un flux, un diffuseur…',
          ),
          if (categories.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 36,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length + 1,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _CategoryChip(
                      label: 'Tous',
                      selected: selectedCategory == null,
                      onTap: () => onCategorySelected(null),
                    );
                  }
                  final category = categories[index - 1];
                  return _CategoryChip(
                    label: streamCategoryLabel(category),
                    selected: selectedCategory == category,
                    onTap: () => onCategorySelected(category),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pastille de catégorie sélectionnable (violet plein quand active).
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primary : colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              child: Text(
                label,
                style: text.labelLarge?.copyWith(
                  color: selected ? colors.onPrimary : colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
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
