import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/permissions/notification_permission.dart';
import '../../../../core/widgets/accessible_icon_button.dart';
import '../../../../core/widgets/volume_slider.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../widgets/listening_time.dart';
import '../../../chat/presentation/providers/chat_controller.dart';
import '../../../chat/presentation/widgets/chat_panel.dart';
import '../../../profile/presentation/providers/profile_controller.dart';
import '../../domain/entities/live_stream.dart';
import '../../domain/repositories/stream_repository.dart';
import '../providers/audio_player_controller.dart';
import '../providers/favorites_controller.dart';

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
  ChatController? _chat;
  ProfileController? _profileController;

  /// Audience estimée, rafraîchie pendant l'écoute. Initialisée à l'instantané
  /// porté par le flux (liste), puis mise à jour par le serveur : sans ça, le
  /// compteur resterait figé sur la valeur d'avant que l'auditeur ne compte.
  int? _listeners;
  Timer? _listenersTimer;

  @override
  void initState() {
    super.initState();
    _audio = widget.controller ?? context.read<AudioPlayerController>();
    _listeners = widget.stream?.listenerCount;
    _audio.addListener(_syncListenersPoll);
    _syncListenersPoll();
    unawaited(ensureNotificationPermission());
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
      _tryConnectChat();
    });
  }

  void _tryConnectChat() {
    final pc = context.read<ProfileController>();
    final profile = pc.profile;
    if (profile != null) {
      _connectChat(profile.id);
      return;
    }
    _profileController = pc;
    _profileController!.addListener(_onProfileLoaded);
    if (!pc.isLoading) pc.load();
  }

  void _onProfileLoaded() {
    final profile = _profileController?.profile;
    if (profile == null) return;
    _profileController!.removeListener(_onProfileLoaded);
    _profileController = null;
    if (!mounted) return;
    _connectChat(profile.id);
  }

  void _connectChat(String userId) {
    _chat = context.read<ChatController>();
    _chat!.connect(widget.streamId, userId);
    setState(() {});
  }

  @override
  void dispose() {
    _profileController?.removeListener(_onProfileLoaded);
    _audio.removeListener(_syncListenersPoll);
    _listenersTimer?.cancel();
    _chat?.disconnect();
    super.dispose();
  }

  /// Ne sonde l'audience que pendant une lecture effective : c'est là que
  /// l'auditeur compte côté serveur (ses requêtes de manifeste alimentent
  /// l'estimation), et un flux en pause n'a pas à réveiller l'application.
  /// Même discipline que le chrono d'écoute ([ListeningTime]).
  void _syncListenersPoll() {
    if (_audio.isPlaying) {
      if (_listenersTimer == null) {
        unawaited(_fetchListeners());
        _listenersTimer = Timer.periodic(
          const Duration(seconds: 8),
          (_) => unawaited(_fetchListeners()),
        );
      }
    } else {
      _listenersTimer?.cancel();
      _listenersTimer = null;
    }
  }

  Future<void> _fetchListeners() async {
    final count =
        await context.read<StreamRepository>().streamListenerCount(widget.streamId);
    // `null` = échec réseau : on garde la dernière valeur affichée plutôt que
    // de faire retomber le compteur à zéro.
    if (!mounted || count == null) return;
    setState(() => _listeners = count);
  }

  Future<void> _toggleFavorite() async {
    final controller = context.read<FavoritesController>();
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
    final title = widget.stream?.title ?? _audio.nowPlaying?.title ?? 'Flux';
    final subtitle =
        widget.stream?.broadcasterName ?? _audio.nowPlaying?.broadcaster;
    final listeners = _listeners;
    final isFavorited =
        context.watch<FavoritesController>().isFavorited(widget.streamId);
    final profile = context.watch<ProfileController>().profile;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(colors, isFavorited),
            const SizedBox(height: 8),
            _nowPlaying(colors, text, title, subtitle, listeners),
            const SizedBox(height: 8),
            _controls(colors),
            const Divider(height: 24),
            Expanded(
              child: _chat != null && profile != null
                  ? ListenableBuilder(
                      listenable: _chat!,
                      builder: (context, _) => ChatPanel(
                        controller: _chat!,
                        currentUserId: profile.id,
                      ),
                    )
                  : Center(
                      child: Text(
                        'Connectez-vous pour accéder au chat',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bloc « en cours » centré : grande pochette dégradée, titre, diffuseur et
  /// nombre d'auditeurs. La pochette est décorative (pas d'image dans le modèle).
  Widget _nowPlaying(
    ColorScheme colors,
    TextTheme text,
    String title,
    String? subtitle,
    int? listeners,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 224,
            height: 224,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [colors.primary, colors.secondary],
              ),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.4),
                  blurRadius: 60,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 2,
                      ),
                    ),
                  ),
                ),
                Icon(Icons.radio, size: 72, color: colors.onPrimary),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: colors.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          ...[
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.headphones, size: 16, color: colors.secondary),
                const SizedBox(width: 6),
                Text(
                  '${listeners ?? 0} auditeur${(listeners ?? 0) > 1 ? 's' : ''}',
                  style:
                      text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Rangée de commandes : temps d'écoute à gauche, gros bouton lecture/pause
  /// **centré**, volume compact à droite (comme la maquette).
  ///
  /// Les deux côtés ont la même largeur fixe et le bouton occupe le centre
  /// extensible : il reste donc parfaitement centré à l'écran, que le temps
  /// d'écoute soit affiché ou non. Le volume est borné en largeur au lieu de
  /// s'étaler sur toute la droite — c'est ce déséquilibre qui décentrait le
  /// bouton.
  Widget _controls(ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerLeft,
              child: ListeningTime(controller: _audio),
            ),
          ),
          Expanded(
            child: Center(
              child: ListenableBuilder(
                listenable: _audio,
                builder: (context, _) => _bigPlayButton(colors),
              ),
            ),
          ),
          const SizedBox(
            width: 130,
            child: Align(
              alignment: Alignment.centerRight,
              child: VolumeSlider(compact: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bigPlayButton(ColorScheme colors) {
    final Widget icon;
    if (_audio.isBusy || _audio.isReconnecting) {
      icon = SizedBox(
        width: 26,
        height: 26,
        child:
            CircularProgressIndicator(strokeWidth: 3, color: colors.onPrimary),
      );
    } else if (_audio.hasError || _audio.isEnded) {
      icon = Icon(Icons.replay, size: 32, color: colors.onPrimary);
    } else if (_audio.isPlaying) {
      icon = Icon(Icons.pause, size: 36, color: colors.onPrimary);
    } else {
      icon = Icon(Icons.play_arrow, size: 36, color: colors.onPrimary);
    }

    final String label;
    if (_audio.hasError || _audio.isEnded) {
      label = 'Réessayer la lecture';
    } else if (_audio.isPlaying) {
      label = 'Mettre en pause';
    } else {
      label = 'Lire';
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: colors.primary,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _audio.togglePlayPause,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(child: icon),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme colors, bool isFavorited) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          AccessibleIconButton(
            icon: Icons.keyboard_arrow_down,
            label: 'Réduire le lecteur',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Center(
              child: ListenableBuilder(
                listenable: _audio,
                builder: (context, _) => (_audio.isEnded || _audio.hasError)
                    ? const SizedBox.shrink()
                    : _liveBadge(colors),
              ),
            ),
          ),
          IconButton(
            onPressed: _toggleFavorite,
            iconSize: 24,
            color: isFavorited ? colors.error : colors.onSurfaceVariant,
            tooltip: isFavorited ? 'Retirer des favoris' : 'Ajouter aux favoris',
            icon: Icon(isFavorited ? Icons.favorite : Icons.favorite_border),
          ),
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
}
