import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../domain/entities/live_stream.dart';
import '../providers/favorites_controller.dart';

class StreamPlayerScreen extends StatefulWidget {
  const StreamPlayerScreen({
    super.key,
    required this.streamId,
    this.stream,
  });

  final String streamId;
  final LiveStream? stream;

  @override
  State<StreamPlayerScreen> createState() => _StreamPlayerScreenState();
}

class _StreamPlayerScreenState extends State<StreamPlayerScreen> {
  @override
  void initState() {
    super.initState();
    // Charge l'état des favoris pour afficher le bon état initial du cœur.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoritesController>().ensureLoaded();
    });
  }

  Future<void> _toggleFavorite() async {
    final controller = context.read<FavoritesController>();
    // Arrivée par deep-link : on n'a pas les métadonnées du flux, on ajoute
    // donc un placeholder ('Flux' / statut inconnu) pour l'update optimiste.
    final isPlaceholder = widget.stream == null;
    final wasFavorited = controller.isFavorited(widget.streamId);
    final favorite = widget.stream ??
        LiveStream(id: widget.streamId, title: 'Flux', startedAt: null);
    try {
      await controller.toggle(favorite);
      // Si l'action était un AJOUT avec placeholder, la section « Favoris »
      // afficherait une tuile fantôme ('Flux' / '—') jusqu'au prochain load.
      // On recharge depuis le serveur pour la remplacer par les vraies
      // métadonnées du flux (retrait ou métadonnées déjà connues : inutile).
      if (isPlaceholder && !wasFavorited) {
        await controller.load();
      }
    } on AuthException catch (_) {
      if (!mounted) return;
      showAuthErrorToast(
        context,
        'Connectez-vous pour ajouter ce flux aux favoris',
      );
    } on Object catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Impossible de mettre à jour les favoris');
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final title = widget.stream?.title ?? 'Flux';
    final isFavorited =
        context.watch<FavoritesController>().isFavorited(widget.streamId);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: _toggleFavorite,
            icon: Icon(
              isFavorited ? Icons.favorite : Icons.favorite_border,
            ),
            color: isFavorited ? colors.primary : null,
            tooltip: isFavorited ? 'Retirer des favoris' : 'Ajouter aux favoris',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.graphic_eq,
                  size: 72,
                  color: colors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: text.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Lecteur à venir',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  widget.streamId,
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
