import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/playlists/presentation/providers/playlist_queue_controller.dart';
import '../../features/playlists/presentation/widgets/queue_mini_player.dart';
import '../../features/streams/presentation/widgets/mini_player.dart';

/// Barre de lecture persistante, au-dessus de la navigation.
///
/// Direct (STR-109) et file d'attente (US-05-04) se partagent un unique lecteur
/// natif : au plus une des deux surfaces a du sens à un instant donné. Cet
/// arbitrage vit dans la couche `app`, seule légitime à connaître les deux
/// features — ni le mini-player du direct ni celui de la file n'a à savoir que
/// l'autre existe.
///
/// La file gagne quand elle est active : c'est elle qui vient d'être lancée (la
/// démarrer arrête le direct, cf. `PlaylistQueueController.play`).
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context) {
    final hasQueue = context.select<PlaylistQueueController, bool>(
      (queue) => queue.hasQueue,
    );
    return hasQueue ? const QueueMiniPlayer() : const MiniPlayer();
  }
}
