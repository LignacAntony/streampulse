import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../playlists/domain/entities/playlist.dart';
import '../../../playlists/domain/repositories/playlist_repository.dart';
import '../../../streams/domain/entities/live_stream.dart';
import '../../../streams/presentation/providers/favorites_controller.dart';
import '../../../streams/presentation/providers/stream_notifier.dart';
import '../../../../core/widgets/message_view.dart';
import '../../../streams/presentation/widgets/stream_tile.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const String _homeLocation = '/home';

  final ScrollController _scrollController = ScrollController();
  late final StreamNotifier _notifier;
  late final FavoritesController _favorites;
  late final AppLifecycleListener _lifecycleListener;
  GoRouter? _router;
  bool _appResumed = true;

  // Playlists favorites (STR-250) : vitrine en haut de l'accueil. Chargées via le
  // repository (pas un contrôleur app-level) et rafraîchies à l'arrivée sur
  // l'écran — l'épinglage se fait dans la Bibliothèque.
  List<Playlist> _favoritePlaylists = const [];

  @override
  void initState() {
    super.initState();
    _notifier = context.read<StreamNotifier>();
    _favorites = context.read<FavoritesController>();
    _scrollController.addListener(_onScroll);
    _lifecycleListener = AppLifecycleListener(onStateChange: (state) {
      _appResumed = state == AppLifecycleState.resumed;
      _syncPolling();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifier.load();
      _favorites.ensureLoaded();
      // La vitrine des favoris se (re)charge à chaque arrivée sur l'accueil,
      // piloté par `_syncPolling` (appelé ici et à chaque navigation).
      _syncPolling();
    });
  }

  /// (Re)charge les playlists épinglées. Best-effort : un échec laisse la vitrine
  /// vide sans casser le reste de l'accueil (les flux restent affichés).
  Future<void> _loadFavoritePlaylists() async {
    try {
      final all = await context.read<PlaylistRepository>().list();
      if (!mounted) return;
      setState(() {
        _favoritePlaylists =
            all.where((p) => p.isFavorite).toList(growable: false);
      });
    } catch (_) {
      // Silencieux : la vitrine est un bonus, pas un bloquant.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_syncPolling);
      _router = router..routerDelegate.addListener(_syncPolling);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_syncPolling);
    _lifecycleListener.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _notifier.stopPolling();
    super.dispose();
  }

  void _onScroll() {
    if (!_notifier.hasMore || _notifier.isLoadingMore) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _notifier.loadMore();
    }
  }

  Future<void> _onRefresh() async {
    await Future.wait([
      _notifier.refresh(),
      _favorites.load(),
      _loadFavoritePlaylists(),
    ]);
  }

  /// Ne poll que si l'app est au premier plan ET l'écran d'accueil est visible
  /// (aucun autre onglet du shell sélectionné, aucune route poussée par-dessus).
  void _syncPolling() {
    final onHome =
        _router?.routerDelegate.currentConfiguration.uri.path == _homeLocation;
    if (_appResumed && onHome) {
      _notifier.startPolling();
      // Rafraîchit la vitrine au retour sur l'accueil (ex. après avoir épinglé
      // une playlist depuis la Bibliothèque).
      _loadFavoritePlaylists();
    } else {
      _notifier.stopPolling();
    }
  }

  @override
  Widget build(BuildContext context) {
    final notifier = context.watch<StreamNotifier>();

    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: _buildBody(context, notifier),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, StreamNotifier notifier) {
    if (notifier.isLoading && notifier.streams.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notifier.hasError && notifier.streams.isEmpty) {
      return MessageView(
        icon: Icons.wifi_off_outlined,
        message: 'Impossible de charger les flux',
        actionLabel: 'Réessayer',
        onAction: notifier.load,
      );
    }

    final favorites = context.watch<FavoritesController>();

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        if (notifier.hasError)
          const SliverToBoxAdapter(child: _StaleBanner()),
        // Bloc « Favoris » unique (STR-250) : playlists épinglées (rangée
        // horizontale) puis flux favoris, avant la section « En direct ».
        const SliverToBoxAdapter(child: _SectionHeader('Favoris')),
        if (_favoritePlaylists.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _FavoritePlaylistsRow(playlists: _favoritePlaylists),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
        ],
        if (favorites.favorites.isEmpty)
          const SliverToBoxAdapter(
            child: _EmptyHint('Aucun flux en favori'),
          )
        else
          _StreamSliverList(streams: favorites.favorites),
        const SliverToBoxAdapter(child: _SectionHeader('En direct')),
        if (notifier.streams.isEmpty)
          const SliverToBoxAdapter(
            child: _EmptyHint('Aucun flux actif pour le moment'),
          )
        else
          _StreamSliverList(streams: notifier.streams),
        SliverToBoxAdapter(child: _ListFooter(notifier: notifier)),
        const SliverToBoxAdapter(child: SizedBox(height: 16)),
      ],
    );
  }
}

/// Liste de tuiles de flux avec espacement, factorisée pour les deux sections.
class _StreamSliverList extends StatelessWidget {
  const _StreamSliverList({required this.streams});

  final List<LiveStream> streams;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.separated(
        itemCount: streams.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => StreamTile(stream: streams[index]),
      ),
    );
  }
}

/// Vitrine horizontale des playlists épinglées (STR-250), en haut de l'accueil.
class _FavoritePlaylistsRow extends StatelessWidget {
  const _FavoritePlaylistsRow({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) => _PlaylistFavoriteCard(
          playlist: playlists[index],
          index: index,
        ),
      ),
    );
  }
}

/// Carte d'une playlist favorite : cover dégradée + nom + nombre de titres.
/// Un appui ouvre le détail dans l'onglet Bibliothèque.
class _PlaylistFavoriteCard extends StatelessWidget {
  const _PlaylistFavoriteCard({required this.playlist, required this.index});

  final Playlist playlist;
  final int index;

  // Dégradés doux, variés par index (mêmes teintes que les covers de la biblio).
  static const List<List<Color>> _gradients = [
    [Color(0xFF7C4DFF), Color(0xFF448AFF)],
    [Color(0xFF26C6DA), Color(0xFF66BB6A)],
    [Color(0xFFFF7043), Color(0xFFFFCA28)],
    [Color(0xFFEC407A), Color(0xFFAB47BC)],
  ];

  String _trackCountLabel(int count) {
    if (count == 0) return 'Aucun titre';
    return '$count ${count == 1 ? 'titre' : 'titres'}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final gradient = _gradients[index % _gradients.length];

    return SizedBox(
      width: 132,
      child: Semantics(
        button: true,
        label: 'Playlist ${playlist.name}, ${_trackCountLabel(playlist.trackCount)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              height: 122,
              child: Material(
                borderRadius: BorderRadius.circular(20),
                clipBehavior: Clip.antiAlias,
                color: Colors.transparent,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: gradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: InkWell(
                    key: Key('home_playlist_${playlist.id}'),
                    onTap: () => context.go(
                      '/library/playlist/${playlist.id}',
                      extra: playlist.name,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.queue_music,
                        size: 44,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              _trackCountLabel(playlist.trackCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _StaleBanner extends StatelessWidget {
  const _StaleBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      color: colors.errorContainer,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: colors.onErrorContainer),
          const SizedBox(width: 8),
          Text(
            'Hors ligne — liste peut-être périmée',
            style: text.bodySmall?.copyWith(color: colors.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.notifier});

  final StreamNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (notifier.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (notifier.hasMore) {
      return Center(
        child: OutlinedButton(
          onPressed: notifier.loadMore,
          child: const Text('Charger plus'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
