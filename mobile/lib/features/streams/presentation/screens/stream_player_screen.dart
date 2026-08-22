import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/permissions/notification_permission.dart';
import '../../../../core/widgets/accessible_icon_button.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../chat/presentation/providers/chat_controller.dart';
import '../../../chat/presentation/widgets/chat_panel.dart';
import '../../../profile/presentation/providers/profile_controller.dart';
import '../../domain/entities/live_stream.dart';
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

  @override
  void initState() {
    super.initState();
    _audio = widget.controller ?? context.read<AudioPlayerController>();
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
    _chat?.disconnect();
    super.dispose();
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
    final listeners = widget.stream?.listenerCount;
    final isFavorited =
        context.watch<FavoritesController>().isFavorited(widget.streamId);
    final profile = context.watch<ProfileController>().profile;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(colors),
            _compactStreamInfo(colors, text, title, subtitle, listeners, isFavorited),
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

  Widget _compactStreamInfo(
    ColorScheme colors,
    TextTheme text,
    String title,
    String? subtitle,
    int? listeners,
    bool isFavorited,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [colors.primary, colors.primary.withValues(alpha: 0.4)],
              ),
            ),
            child: Icon(Icons.radio, size: 24, color: colors.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: colors.primary),
                  ),
                if (listeners != null)
                  Row(
                    children: [
                      Icon(Icons.headphones, size: 12, color: colors.secondary),
                      const SizedBox(width: 4),
                      Text(
                        '$listeners',
                        style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: _audio,
            builder: (context, _) => _compactPlayButton(colors),
          ),
          IconButton(
            onPressed: _toggleFavorite,
            iconSize: 22,
            color: isFavorited ? colors.primary : colors.onSurfaceVariant,
            icon: Icon(isFavorited ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
    );
  }

  Widget _compactPlayButton(ColorScheme colors) {
    final Widget icon;
    if (_audio.isBusy || _audio.isReconnecting) {
      icon = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: colors.onPrimary),
      );
    } else if (_audio.hasError || _audio.isEnded) {
      icon = Icon(Icons.replay, size: 22, color: colors.onPrimary);
    } else if (_audio.isPlaying) {
      icon = Icon(Icons.pause, size: 24, color: colors.onPrimary);
    } else {
      icon = Icon(Icons.play_arrow, size: 24, color: colors.onPrimary);
    }

    return Material(
      color: colors.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _audio.togglePlayPause,
        child: SizedBox(width: 40, height: 40, child: Center(child: icon)),
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
}
