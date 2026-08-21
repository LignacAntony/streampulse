import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../audio/playback_transport.dart';
import '../audio/volume_store.dart';

/// Réglage du niveau sonore de l'application (STR-245).
///
/// Le volume appartient au **transport**, pas à une source : le même curseur
/// sert donc au direct et à la file d'attente, et lit l'interface la plus
/// étroite qui le porte ([PlaybackTransport], principe I).
///
/// ## Pourquoi pas un `ChangeNotifier` app-level
///
/// Un glissement émet des dizaines de valeurs par seconde. Les faire transiter
/// par un contrôleur applicatif reconstruirait tout l'arbre sous lui à cette
/// cadence — même règle que la position de lecture (`queue_progress.dart`). Ce
/// widget s'abonne donc directement au flux, une fois, et ne reconstruit que
/// lui-même.
///
/// ## Réglage appliqué en continu, enregistré une fois
///
/// `onChanged` applique (l'auditeur doit entendre pendant qu'il glisse),
/// `onChangeEnd` enregistre. Écrire à chaque tick userait le magasin pour un
/// résultat identique — seule la valeur relâchée compte.
///
/// Ce curseur ne remplace pas les boutons matériels : ceux-ci pilotent le
/// volume du **système**, celui-ci atténue StreamPulse à l'intérieur. On peut
/// donc baisser la radio sans baisser ses notifications.
class VolumeSlider extends StatefulWidget {
  const VolumeSlider({super.key, this.showLabel = true});

  /// Affiche le pourcentage à droite du curseur. Coupé sur les surfaces
  /// étroites où la place manque.
  final bool showLabel;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  late final PlaybackTransport _transport;
  late final VolumeStore _store;
  StreamSubscription<double>? _subscription;

  double _volume = 1;

  /// Niveau d'avant la coupure, restauré au second appui sur l'icône. Nul tant
  /// que le son n'a pas été coupé depuis ce widget.
  double? _beforeMute;

  @override
  void initState() {
    super.initState();
    _transport = context.read<PlaybackTransport>();
    _store = context.read<VolumeStore>();
    // Valeur de départ lue directement : le flux n'émet qu'aux changements,
    // s'y fier seul laisserait le curseur à sa valeur par défaut jusqu'au
    // premier réglage.
    _volume = _transport.volume;
    _subscription = _transport.volumeStream.listen((value) {
      if (!mounted) return;
      setState(() => _volume = value);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _apply(double value) => _transport.setVolume(value);

  Future<void> _persist(double value) => _store.write(value);

  Future<void> _toggleMute() async {
    if (_volume > 0) {
      _beforeMute = _volume;
      await _apply(0);
      await _persist(0);
      return;
    }
    // Restaurer à 1 quand rien n'a été mémorisé : l'auditeur a démarré
    // l'application déjà en sourdine, l'appui doit lui rendre du son plutôt
    // que de ne rien faire.
    final restored = _beforeMute ?? 1.0;
    _beforeMute = null;
    await _apply(restored);
    await _persist(restored);
  }

  IconData get _icon {
    if (_volume <= 0) return Icons.volume_off;
    if (_volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final percent = (_volume * 100).round();

    return Row(
      children: [
        IconButton(
          key: const Key('volume_mute_toggle'),
          onPressed: _toggleMute,
          icon: Icon(_icon, color: colors.onSurfaceVariant),
          // Un tooltip n'est pas lu par TalkBack/VoiceOver comme un libellé :
          // il faut les deux (STR-245).
          tooltip: _volume <= 0 ? 'Rétablir le son' : 'Couper le son',
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              key: const Key('volume_slider'),
              value: _volume.clamp(0.0, 1.0),
              // Le lecteur d'écran annonce « 42 pour cent » plutôt que « 0.42 ».
              semanticFormatterCallback: (value) =>
                  'Volume ${(value * 100).round()} %',
              onChanged: (value) {
                setState(() => _volume = value);
                unawaited(_apply(value));
              },
              onChangeEnd: (value) => unawaited(_persist(value)),
            ),
          ),
        ),
        if (widget.showLabel)
          SizedBox(
            width: 40,
            child: Text(
              '$percent %',
              textAlign: TextAlign.end,
              style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
