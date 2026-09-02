import 'dart:async';

import 'package:flutter/material.dart';

import 'listening_time.dart' show formatListeningTime;

/// Temps écoulé du **direct** : depuis le début de la diffusion (`startedAt`),
/// et non depuis que l'auditeur a rejoint (STR-250).
///
/// Différence de sémantique avec [ListeningTime] : ce chrono suit l'horloge du
/// flux, pas la lecture locale. Il avance donc en continu tant que le direct
/// vit — y compris quand l'auditeur met en pause de son côté — parce que la
/// diffusion, elle, ne s'arrête pas.
///
/// Comme [ListeningTime], le tic est **local** : il bat une fois par seconde et
/// ne reconstruit que lui-même.
class LiveElapsedTime extends StatefulWidget {
  const LiveElapsedTime({super.key, required this.startedAt, this.now});

  /// Instant de démarrage de la diffusion. La différence avec [now] est
  /// calculée sur l'instant absolu (epoch), donc juste que `startedAt` soit en
  /// UTC ou local.
  final DateTime startedAt;

  /// Source de l'heure courante, injectable pour les tests (cf. [ListeningTime]).
  final DateTime Function()? now;

  @override
  State<LiveElapsedTime> createState() => _LiveElapsedTimeState();
}

class _LiveElapsedTimeState extends State<LiveElapsedTime> {
  Timer? _ticker;

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // Le direct court en permanence : le tic n'est pas conditionné à l'état de
    // lecture (contrairement à ListeningTime).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    var elapsed = _now().difference(widget.startedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;

    final label = formatListeningTime(elapsed);
    return Semantics(
      label: 'Temps de diffusion : $label',
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
              // Chiffres à chasse fixe : la ligne ne saute pas d'une seconde à
              // l'autre (cf. ListeningTime).
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
