import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/permissions/notification_permission.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../domain/entities/live_stream.dart';
import '../providers/audio_player_controller.dart';
import '../providers/favorites_controller.dart';
import '../../../../core/widgets/accessible_icon_button.dart';

/// Lecteur audio HLS plein écran (STR-108/117, cf. ADR 023). L'audio est piloté
/// par le [AudioPlayerController] **partagé** app-level (STR-109) : la lecture
/// survit à la navigation et à l'arrière-plan ; l'écran ne le possède pas.
class StreamPlayerScreen extends StatefulWidget {
  const StreamPlayerScreen({
    super.key,
    required this.streamId,
    this.stream,
    @visibleForTesting this.controller,
  });

  final String streamId;
  final LiveStream? stream;

  /// Injecté par les widget tests (fake sans just_audio) ; en production, le
  /// [AudioPlayerController] **partagé** (app-level, STR-109) est lu du Provider.
  final PlaybackController? controller;

  @override
  State<StreamPlayerScreen> createState() => _StreamPlayerScreenState();
}

class _StreamPlayerScreenState extends State<StreamPlayerScreen> {
  late final PlaybackController _audio;

  @override
  void initState() {
    super.initState();
    // Contrôleur partagé (le service audio survit à la navigation, STR-109) :
    // l'écran ne le possède pas et ne le détruit pas.
    _audio = widget.controller ?? context.read<AudioPlayerController>();
    // Ouvrir le lecteur = intention d'écouter → on demande (Android 13+) la
    // permission notifications pour que les contrôles média soient visibles.
    unawaited(ensureNotificationPermission());
    // (Re)démarre ce flux uniquement s'il n'est pas déjà en cours : revenir sur
    // l'écran d'un flux en lecture ne le relance pas (autoplay sinon, STR-108).
    if (_audio.nowPlaying?.streamId != widget.streamId) {
      _audio.load(
        NowPlaying(
          streamId: widget.streamId,
          title: widget.stream?.title ?? 'Flux',
          broadcaster: widget.stream?.broadcasterName,
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<FavoritesController>().ensureLoaded();
    });
  }

  Future<void> _toggleFavorite() async {
    final controller = context.read<FavoritesController>();
    // Arrivée par deep-link : pas de métadonnées → placeholder pour l'update optimiste.
    final isPlaceholder = widget.stream == null;
    final wasFavorited = controller.isFavorited(widget.streamId);
    final favorite = widget.stream ??
        LiveStream(id: widget.streamId, title: 'Flux', startedAt: null);
    try {
      await controller.toggle(favorite);
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
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Métadonnées : celles passées en navigation, sinon celles du flux en cours
    // dans le contrôleur partagé (ouverture via le mini-player, sans `extra`).
    final title = widget.stream?.title ?? _audio.nowPlaying?.title ?? 'Flux';
    final subtitle =
        widget.stream?.broadcasterName ?? _audio.nowPlaying?.broadcaster;
    final listeners = widget.stream?.listenerCount;
    final isFavorited =
        context.watch<FavoritesController>().isFavorited(widget.streamId);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(colors),
            Expanded(
              child: ListenableBuilder(
                listenable: _audio,
                builder: (context, _) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      _artwork(colors),
                      const SizedBox(height: 20),
                      Icon(Icons.graphic_eq, size: 40, color: colors.primary),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: text.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style:
                              text.titleMedium?.copyWith(color: colors.primary),
                        ),
                      ],
                      if (listeners != null) ...[
                        const SizedBox(height: 10),
                        _listeners(colors, text, listeners),
                      ],
                      const SizedBox(height: 24),
                      _statusLine(colors, text),
                      const SizedBox(height: 28),
                      _controls(colors, isFavorited),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          AccessibleIconButton(
            icon: Icons.keyboard_arrow_down,
            label: 'Réduire le lecteur',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(),
          // Le badge « EN DIRECT » disparaît quand le flux est terminé ou en
          // erreur (il ne se rebuild pas avec le reste du header → listenable).
          ListenableBuilder(
            listenable: _audio,
            builder: (context, _) => (_audio.isEnded || _audio.hasError)
                ? const SizedBox.shrink()
                : _liveBadge(colors),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _liveBadge(ColorScheme colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: colors.error,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'EN DIRECT',
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.5,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _artwork(ColorScheme colors) {
    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.primary, colors.primary.withValues(alpha: 0.4)],
        ),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.5),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
        ),
        child: Icon(Icons.radio, size: 72, color: colors.onSurfaceVariant),
      ),
    );
  }

  Widget _listeners(ColorScheme colors, TextTheme text, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.headphones, size: 16, color: colors.secondary),
        const SizedBox(width: 6),
        Text(
          '$count auditeurs',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Ligne d'état : reconnexion (STR-118), chargement, erreur (flux indisponible
  /// / terminé), ou lecture/pause.
  Widget _statusLine(ColorScheme colors, TextTheme text) {
    if (_audio.isReconnecting) {
      return _busyLine(colors, text, 'Reconnexion…');
    }
    if (_audio.isBusy) {
      return _busyLine(colors, text, 'Chargement…');
    }
    if (_audio.hasError || _audio.isEnded) {
      final msg =
          _audio.isEnded ? 'Le direct est terminé' : 'Flux indisponible';
      return Text(
        msg,
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: colors.error),
      );
    }
    return Text(
      _audio.isPlaying ? 'À l’écoute' : 'En pause',
      style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
    );
  }

  Widget _busyLine(ColorScheme colors, TextTheme text, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 14,
          child:
              CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
        ),
        const SizedBox(width: 10),
        Text(label,
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
      ],
    );
  }

  Widget _controls(ColorScheme colors, bool isFavorited) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        AccessibleIconButton(
          icon: isFavorited ? Icons.favorite : Icons.favorite_border,
          label: isFavorited ? 'Retirer des favoris' : 'Ajouter aux favoris',
          onPressed: _toggleFavorite,
          iconSize: 28,
          color: isFavorited ? colors.primary : colors.onSurfaceVariant,
        ),
        _playPauseButton(colors),
      ],
    );
  }

  Widget _playPauseButton(ColorScheme colors) {
    final Widget icon;
    if (_audio.isBusy || _audio.isReconnecting) {
      icon = SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(strokeWidth: 3, color: colors.onPrimary),
      );
    } else if (_audio.hasError || _audio.isEnded) {
      icon = Icon(Icons.replay, size: 36, color: colors.onPrimary);
    } else if (_audio.isPlaying) {
      icon = Icon(Icons.pause, size: 40, color: colors.onPrimary);
    } else {
      icon = Icon(Icons.play_arrow, size: 40, color: colors.onPrimary);
    }

    // Le contrôle principal de l'écran était un InkWell nu : aucun nom, aucun
    // rôle, rien pour un lecteur d'écran. Le libellé suit l'état, sinon il
    // annoncerait « Lire » sur un flux déjà en lecture.
    final String label;
    if (_audio.isBusy || _audio.isReconnecting) {
      label = 'Chargement du flux';
    } else if (_audio.hasError || _audio.isEnded) {
      label = 'Réessayer la lecture';
    } else if (_audio.isPlaying) {
      label = 'Mettre en pause';
    } else {
      label = 'Lire';
    }

    return Semantics(
      label: label,
      button: true,
      // Pendant le chargement il n'y a rien à activer : l'annoncer évite qu'un
      // appui à l'aveugle passe pour une panne.
      enabled: !(_audio.isBusy || _audio.isReconnecting),
      excludeSemantics: true,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _audio.togglePlayPause,
          child: SizedBox(
            width: 76,
            height: 76,
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }
}
