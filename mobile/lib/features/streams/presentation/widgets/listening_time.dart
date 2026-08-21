import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/audio/listening_clock.dart';
import '../providers/audio_player_controller.dart';

/// Temps d'écoute d'un direct (STR-244).
///
/// Le sujet demande une barre de progression au lecteur. Un direct n'en a pas :
/// il n'a pas de fin connue, donc pas de fraction à remplir, et une barre qui
/// n'avance jamais serait un mensonge visuel. Ce qu'il a — et ce que l'auditeur
/// veut savoir — c'est depuis combien de temps il écoute.
///
/// La valeur vient d'une [ListeningClock] pilotée par l'**état de lecture**, et
/// non de `positionStream`. La raison est dans `listening_clock.dart` : le
/// contrôleur recharge l'URL à chaque reprise après erreur (STR-118), ce qui
/// remettrait la position du lecteur à zéro à la moindre coupure réseau.
///
/// Le tic est **local à ce widget**. Il bat une fois par seconde, et rien
/// au-dessus ne se reconstruit — même règle que la position de la file
/// d'attente (`queue_progress.dart`).
class ListeningTime extends StatefulWidget {
  const ListeningTime({super.key, required this.controller, this.now});

  final PlaybackController controller;

  /// Source de l'heure courante. Injectable parce que `tester.pump(Duration)`
  /// n'avance que l'horloge **simulée** de Flutter : un widget qui appellerait
  /// `DateTime.now()` en dur ne verrait jamais le temps passer sous test, et
  /// tout ce fichier serait invérifiable. Même parti que le `controller`
  /// injectable de `StreamPlayerScreen`.
  final DateTime Function()? now;

  @override
  State<ListeningTime> createState() => _ListeningTimeState();
}

class _ListeningTimeState extends State<ListeningTime> {
  final _clock = ListeningClock();
  Timer? _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  /// Flux auquel le décompte se rapporte. Changer de direct redémarre
  /// l'horloge : sans ce repère, le temps d'écoute d'une radio serait
  /// attribué à la suivante.
  String? _streamId;

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
    final controller = widget.controller;
    final streamId = controller.nowPlaying?.streamId;

    if (streamId != _streamId) {
      _streamId = streamId;
      _clock.reset();
    }

    // L'horloge ne tourne que pendant une lecture effective. Une reconnexion
    // n'en est pas une : l'auditeur n'entend rien, et un compteur qui court sur
    // du silence surestimerait ce qu'il a réellement écouté.
    if (controller.isPlaying) {
      _clock.start(_now());
    } else {
      // Couvre aussi la fin de flux et l'erreur : dans les deux cas plus rien
      // ne joue, et le compteur doit s'arrêter là où l'écoute s'est arrêtée.
      _clock.pause(_now());
    }

    _syncTicker();
    if (mounted) setState(() {});
  }

  /// Le tic ne bat que quand l'horloge tourne : une lecture en pause n'a aucune
  /// raison de réveiller l'application chaque seconde.
  void _syncTicker() {
    if (_clock.running && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_clock.running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final elapsed = _clock.elapsedAt(_now());

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
