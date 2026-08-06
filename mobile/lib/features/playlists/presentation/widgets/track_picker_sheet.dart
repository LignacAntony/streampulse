import 'package:flutter/material.dart';

import '../../domain/entities/track.dart';
import '../track_labels.dart';

/// Feuille modale de sélection d'une piste à ajouter à une playlist (US-05-03).
///
/// Reçoit un chargeur plutôt qu'une liste : la bibliothèque est demandée à
/// l'ouverture de la feuille, pas au montage de l'écran de détail (elle n'est
/// utile qu'ici). Renvoie l'identifiant choisi via `Navigator.pop`, ou `null` si
/// la feuille est fermée sans choix.
class TrackPickerSheet extends StatefulWidget {
  const TrackPickerSheet({super.key, required this.loadTracks});

  final Future<List<Track>> Function() loadTracks;

  static Future<String?> show(
    BuildContext context, {
    required Future<List<Track>> Function() loadTracks,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Navigator racine : sans lui la feuille s'ouvre dans la branche du shell
      // et la barre de navigation reste visible, non atténuée, sous le voile.
      useRootNavigator: true,
      builder: (_) => TrackPickerSheet(loadTracks: loadTracks),
    );
  }

  @override
  State<TrackPickerSheet> createState() => _TrackPickerSheetState();
}

class _TrackPickerSheetState extends State<TrackPickerSheet> {
  late Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadTracks();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajouter une piste',
              style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // Hauteur bornée : la feuille ne doit pas dépasser la moitié de
            // l'écran même avec une longue bibliothèque. Les états spinner /
            // vide / erreur se dimensionnent à leur contenu (cf. _PickerMessage)
            // pour que la feuille reste courte quand il n'y a rien à lister.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
                minWidth: double.infinity,
              ),
              child: FutureBuilder<List<Track>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      // heightFactor: 1 → la hauteur suit le contenu, la largeur
                      // reste pleine pour centrer horizontalement.
                      child: Align(
                        heightFactor: 1,
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return const _PickerMessage(
                      key: Key('track_picker_error'),
                      message: 'Impossible de charger la bibliothèque',
                    );
                  }
                  final tracks = snapshot.data ?? const <Track>[];
                  if (tracks.isEmpty) {
                    return const _PickerMessage(
                      key: Key('track_picker_empty'),
                      message: 'Aucune piste disponible à ajouter',
                    );
                  }
                  return ListView.builder(
                    key: const Key('track_picker_list'),
                    shrinkWrap: true,
                    itemCount: tracks.length,
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      return ListTile(
                        key: Key('track_picker_item_${track.id}'),
                        leading: const Icon(Icons.music_note),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          trackSubtitle(
                            artist: track.artist,
                            durationS: track.durationS,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(track.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickerMessage extends StatelessWidget {
  const _PickerMessage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    // Pas de `Center` : dans la ConstrainedBox de la feuille il s'étirerait à la
    // hauteur maximale et laisserait une demi-page vide sous le message.
    // `Align(heightFactor: 1)` garde la largeur pleine (texte centré) sans
    // prendre la hauteur disponible.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Align(
        heightFactor: 1,
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ),
    );
  }
}
