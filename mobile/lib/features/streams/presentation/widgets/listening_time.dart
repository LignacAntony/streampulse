import 'dart:async';

import 'package:flutter/material.dart';

import '../providers/audio_player_controller.dart';

/// Temps d'écoute d'un direct (STR-244).
///
/// Le sujet demande une barre de progression au lecteur. Un direct n'en a pas :
/// il n'a pas de fin connue, donc pas de fraction à remplir, et une barre qui
/// n'avance jamais serait un mensonge visuel. Ce qu'il a — et ce que l'auditeur
/// veut savoir — c'est depuis combien de temps il écoute.
///
/// ## Le cumul vit dans le contrôleur, le tic vit ici
///
/// L'horloge appartient au [PlaybackController] **app-level**, pas au `State`
/// de ce widget. La lecture survit à la navigation (ADR 031) : dans le `State`,
/// revenir en arrière puis rouvrir le plein écran repartait de `00:00` alors
/// que le direct jouait depuis dix minutes — ce qui contredisait la promesse du
/// libellé (revue PR #331).
///
/// Ce widget n'apporte donc que l'affichage et son tic, **local** : il bat une
/// fois par seconde, et rien au-dessus ne se reconstruit — même règle que la
/// position de la file d'attente (`queue_progress.dart`).
class ListeningTime extends StatefulWidget {
  const ListeningTime({super.key, required this.controller, this.now});

  final PlaybackController controller;

  /// Source de l'heure courante. Injectable parce que `tester.pump(Duration)`
  /// n'avance que l'horloge **simulée** de Flutter : un widget qui appellerait
  /// `DateTime.now()` en dur ne verrait jamais le temps passer sous test.
  final DateTime Function()? now;

  @override
  State<ListeningTime> createState() => _ListeningTimeState();
}

class _ListeningTimeState extends State<ListeningTime> {
  Timer? _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onPlaybackChanged);
    _onPlaybackChanged();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onPlaybackChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onPlaybackChanged() {
    _syncTicker();
    if (mounted) setState(() {});
  }

  /// Le tic ne bat que pendant une lecture effective : une lecture en pause n'a
  /// aucune raison de réveiller l'application chaque seconde.
  void _syncTicker() {
    if (widget.controller.isPlaying && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!widget.controller.isPlaying) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final elapsed = widget.controller.listeningElapsed(_now());

    // Rien à afficher avant la première seconde écoutée : un « 00:00 » figé
    // pendant le chargement laisse croire que la lecture est bloquée.
    if (elapsed == Duration.zero) return const SizedBox.shrink();

    final label = formatListeningTime(elapsed);
    return Semantics(
      // Sans libellé, un lecteur d'écran annonce « 12 deux-points 03 », ce qui
      // ne veut rien dire hors contexte visuel.
      label: 'Temps d\'écoute : $label',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              // Chiffres à chasse fixe : sans cela, la ligne se décale à chaque
              // seconde parce que « 1 » est plus étroit que « 8 ».
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// `mm:ss` en deçà d'une heure, `h:mm:ss` au-delà — une écoute de trois heures
/// affichée « 180:24 » se lit mal.
String formatListeningTime(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  final s = (seconds % 60).toString().padLeft(2, '0');
  final m = (seconds ~/ 60) % 60;
  final h = seconds ~/ 3600;
  if (h == 0) return '${m.toString().padLeft(2, '0')}:$s';
  return '$h:${m.toString().padLeft(2, '0')}:$s';
}
