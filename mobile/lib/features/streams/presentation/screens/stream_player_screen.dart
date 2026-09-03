import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/permissions/notification_permission.dart';
import '../../../../core/widgets/accessible_icon_button.dart';
import '../../../../core/widgets/volume_slider.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../widgets/listening_time.dart';
import '../widgets/live_elapsed_time.dart';
import '../../../broadcast/presentation/providers/current_broadcast.dart';
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

  /// Vrai quand ce téléphone **diffuse** le flux ouvert : on ne démarre alors
  /// pas la lecture HLS. Le faire couperait la capture micro (la session audio
  /// `playback` interrompt l'enregistrement) et rejouerait le direct en boucle
  /// larsen. Calculé une fois à l'ouverture : la décision de lecture ne se
  /// reprend pas après coup.
  bool _isOwnBroadcast = false;

  @override
  void initState() {
    super.initState();
    _audio = widget.controller ?? context.read<AudioPlayerController>();
    unawaited(ensureNotificationPermission());
    _isOwnBroadcast =
        context.read<CurrentBroadcast>().isBroadcasting(widget.streamId);
    if (!_isOwnBroadcast && _audio.nowPlaying?.streamId != widget.streamId) {
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
      // `bottom: false` : la barre de saisie du chat gère elle-même l'encoche
      // du bas, afin de coller au bord de l'écran sans vide au-dessus.
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(colors, isFavorited),
            // Hero en `Expanded` (fit tight), et non `Flexible` (loose) : un
            // Flexible loose plus court que sa part gaspille la différence, qui
            // retombe en bas de la colonne et surélève l'input du chat de ~80 px.
            // En tight il consomme exactement sa part (1/2), le chat prend
            // l'autre moitié et colle au bord bas. Le `SingleChildScrollView`
            // laisse le hero défiler et se contracter quand le clavier réduit la
            // place, plutôt que de déborder.
            Expanded(
              child: SingleChildScrollView(
                child: _hero(colors, text, title, subtitle, listeners),
              ),
            ),
            // Barre de volume identique à celle de la musique (STR-250), placée
            // juste au-dessus du chat. Inutile quand on diffuse ce flux : le
            // lecteur n'est pas chargé, il n'y a rien à régler.
            if (!_isOwnBroadcast)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: VolumeSlider(),
              ),
            const Divider(height: 1),
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

  Widget _hero(
    ColorScheme colors,
    TextTheme text,
    String title,
    String? subtitle,
    int? listeners,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          _artwork(colors),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (listeners != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.headphones, size: 16, color: colors.secondary),
                const SizedBox(width: 6),
                Text(
                  '$listeners auditeurs',
                  style: text.bodyMedium
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          _transport(colors),
        ],
      ),
    );
  }

  Widget _artwork(ColorScheme colors) {
    // Carré borné : un AspectRatio dans une Column prendrait toute la largeur
    // disponible et deviendrait aussi haut, débordant la hauteur.
    final side = MediaQuery.sizeOf(context).width.clamp(0.0, 140.0);
    return SizedBox.square(
      dimension: side,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.primary,
              Color.lerp(colors.primary, colors.tertiary, 0.6) ??
                  colors.primary,
            ],
          ),
        ),
        child: Icon(Icons.mic, size: 56, color: colors.onPrimary),
      ),
    );
  }

  /// Temps du direct à gauche, gros bouton lecture centré (comme le mockup) — le
  /// volume qui l'accompagnait devient la [VolumeSlider] au-dessus du chat.
  ///
  /// On affiche le temps **de diffusion** (depuis le début du live) quand il est
  /// connu ; à défaut (arrivée deep-link sans métadonnées, `startedAt` inconnu)
  /// on retombe sur le temps d'écoute de l'auditeur.
  Widget _transport(ColorScheme colors) {
    final startedAt = widget.stream?.startedAt;
    // En diffusion : pas de bouton de lecture (on n'écoute pas son propre
    // direct), et le temps affiché est celui du direct, jamais un temps
    // d'écoute qui n'existe pas.
    if (_isOwnBroadcast) {
      return Column(
        children: [
          if (startedAt != null) ...[
            LiveElapsedTime(startedAt: startedAt),
            const SizedBox(height: 12),
          ],
          _broadcastingIndicator(colors),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: startedAt != null
                ? LiveElapsedTime(startedAt: startedAt)
                : ListeningTime(controller: _audio),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: ListenableBuilder(
            listenable: _audio,
            builder: (context, _) => _playButton(colors),
          ),
        ),
        const Expanded(child: SizedBox()),
      ],
    );
  }

  /// Remplace le bouton de lecture quand on diffuse ce flux : on ne s'écoute
  /// pas soi-même. Un simple bandeau informe qu'on est la source.
  Widget _broadcastingIndicator(ColorScheme colors) {
    return Semantics(
      label: 'Vous diffusez ce flux',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.podcasts, size: 20, color: colors.onPrimaryContainer),
            const SizedBox(width: 8),
            Text(
              'Vous diffusez ce flux',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playButton(ColorScheme colors) {
    final String label;
    final Widget icon;
    if (_audio.isBusy || _audio.isReconnecting) {
      label = 'Chargement';
      icon = SizedBox(
        width: 26,
        height: 26,
        child:
            CircularProgressIndicator(strokeWidth: 2.5, color: colors.onPrimary),
      );
    } else if (_audio.hasError || _audio.isEnded) {
      label = 'Réessayer';
      icon = Icon(Icons.replay, size: 32, color: colors.onPrimary);
    } else if (_audio.isPlaying) {
      label = 'Mettre en pause';
      icon = Icon(Icons.pause, size: 34, color: colors.onPrimary);
    } else {
      label = 'Lire';
      icon = Icon(Icons.play_arrow, size: 34, color: colors.onPrimary);
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
          child: SizedBox(width: 72, height: 72, child: Center(child: icon)),
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
          const Spacer(),
          // En diffusion, le direct est vivant par définition (c'est nous qui
          // l'alimentons) : badge constant, sans dépendre de l'état du lecteur
          // qu'on ne charge pas.
          if (_isOwnBroadcast)
            _liveBadge(colors)
          else
            ListenableBuilder(
              listenable: _audio,
              builder: (context, _) => (_audio.isEnded || _audio.hasError)
                  ? const SizedBox.shrink()
                  : _liveBadge(colors),
            ),
          const Spacer(),
          IconButton(
            onPressed: _toggleFavorite,
            iconSize: 22,
            color: isFavorited ? colors.primary : colors.onSurfaceVariant,
            tooltip: isFavorited
                ? 'Retirer des favoris'
                : 'Ajouter aux favoris',
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
