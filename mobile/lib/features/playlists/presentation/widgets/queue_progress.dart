import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/playlist_queue_controller.dart';
import '../track_labels.dart';

/// Avancement de la piste en cours (STR-230), en deux formes : un trait sur le
/// mini-player ([QueueProgressLine]) et une barre manipulable dans la file
/// d'attente ([QueueProgressSlider]).
///
/// Les deux s'abonnent **directement** aux flux du contrôleur plutôt que de
/// lire un état exposé par `notifyListeners` : la position émet plusieurs fois
/// par seconde, la faire transiter par le contrôleur app-level reconstruirait
/// tout l'arbre (mini-player, file, écran en cours) à cette cadence.
///
/// La durée vient du **lecteur**, pas de la base : `duration_s` est déclaré par
/// le client à l'upload (ADR 032) et peut être faux. Celle de la piste ne sert
/// que de valeur d'attente, le temps que le lecteur ouvre le fichier — sans
/// elle, la barre resterait vide une seconde à chaque changement de piste.
class QueueProgressLine extends StatelessWidget {
  const QueueProgressLine({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return _ProgressBuilder(
      builder: (context, position, buffered, duration) {
        if (duration == null || duration == Duration.zero) {
          return const SizedBox(height: 2);
        }
        return SizedBox(
          height: 2,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LinearProgressIndicator(
                value: _fraction(buffered, duration),
                backgroundColor: colors.surfaceContainerHighest,
                color: colors.primary.withValues(alpha: 0.25),
              ),
              LinearProgressIndicator(
                value: _fraction(position, duration),
                backgroundColor: Colors.transparent,
                color: colors.primary,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Barre manipulable : glisser dedans déplace la lecture.
class QueueProgressSlider extends StatefulWidget {
  const QueueProgressSlider({super.key});

  @override
  State<QueueProgressSlider> createState() => _QueueProgressSliderState();
}

class _QueueProgressSliderState extends State<QueueProgressSlider> {
  /// Position sous le pouce pendant un glissement. Tant qu'elle est posée, les
  /// positions venant du lecteur sont ignorées : sinon le pouce se ferait
  /// doubler par la lecture qui continue, et la barre tremblerait.
  Duration? _dragging;

  Future<void> _onChangeEnd(Duration target) async {
    await context.read<PlaylistQueueController>().seek(target);
    if (!mounted) return;
    // Relâchée seulement après le déplacement : l'effacer avant ferait revenir
    // le pouce à l'ancienne position le temps que le lecteur rattrape.
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return _ProgressBuilder(
      builder: (context, position, buffered, duration) {
        final total = duration ?? Duration.zero;
        final shown = _dragging ?? position;
        final enabled = total > Duration.zero;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                key: const Key('queue_progress_slider'),
                min: 0,
                // Un maximum nul ferait lever le Slider : tant que la durée est
                // inconnue, on garde une échelle d'une seconde, désactivée.
                max: enabled ? total.inMilliseconds.toDouble() : 1,
                value: enabled
                    ? shown.inMilliseconds
                        .clamp(0, total.inMilliseconds)
                        .toDouble()
                    : 0,
                onChanged: enabled
                    ? (value) => setState(
                          () => _dragging =
                              Duration(milliseconds: value.round()),
                        )
                    : null,
                onChangeEnd: enabled
                    ? (value) =>
                        _onChangeEnd(Duration(milliseconds: value.round()))
                    : null,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatTrackDuration(shown.inSeconds),
                    style: text.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  Text(
                    enabled ? formatTrackDuration(total.inSeconds) : '--:--',
                    style: text.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Assemble les trois flux d'avancement en un seul `builder`.
///
/// **Un seul abonnement par flux, posé à la construction** — et surtout pas des
/// `StreamBuilder` imbriqués : `Stream` n'est pas une valeur stable ici (un
/// getter de flux rend un objet neuf à chaque accès), si bien qu'à chaque
/// reconstruction un `StreamBuilder` se réabonnerait. Sur un flux continu ça ne
/// coûte qu'un tick, mais la **durée n'est émise qu'une fois par piste** : elle
/// serait perdue et la barre resterait muette.
///
/// Le tampon est facultatif au sens strict, mais sans lui une lecture qui
/// bufferise paraît figée : la barre grise montre que ça télécharge.
class _ProgressBuilder extends StatefulWidget {
  const _ProgressBuilder({required this.builder});

  final Widget Function(
    BuildContext context,
    Duration position,
    Duration buffered,
    Duration? duration,
  ) builder;

  @override
  State<_ProgressBuilder> createState() => _ProgressBuilderState();
}

class _ProgressBuilderState extends State<_ProgressBuilder> {
  final _subscriptions = <StreamSubscription<Object?>>[];

  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    final queue = context.read<PlaylistQueueController>();
    _subscriptions.addAll([
      queue.positionStream.listen((v) => _set(() => _position = v)),
      queue.bufferedPositionStream.listen((v) => _set(() => _buffered = v)),
      queue.durationStream.listen((v) => _set(() => _duration = v)),
    ]);
  }

  /// `setState` ne reconstruit que cette barre : c'est tout l'intérêt de garder
  /// ces flux hors du contrôleur app-level.
  void _set(VoidCallback change) {
    if (!mounted) return;
    setState(change);
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Durée déclarée de la piste : valeur d'attente le temps que le lecteur
    // lise la vraie dans le fichier. Suivie par `watch` pour se rafraîchir au
    // changement de piste.
    final declared =
        context.watch<PlaylistQueueController>().currentTrack?.durationS;

    return widget.builder(
      context,
      _position,
      _buffered,
      _duration ?? (declared == null ? null : Duration(seconds: declared)),
    );
  }
}

double _fraction(Duration value, Duration total) =>
    total <= Duration.zero
        ? 0
        : (value.inMilliseconds / total.inMilliseconds).clamp(0, 1).toDouble();
