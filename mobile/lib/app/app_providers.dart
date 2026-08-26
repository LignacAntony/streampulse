import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../core/audio/audio_playback_service.dart';
import '../core/audio/playback_auth.dart';
import '../core/audio/queue_playback_service.dart';
import '../core/network/dio_client.dart';
import '../core/offline/connectivity_service.dart';
import '../core/offline/connectivity_service_impl.dart';
import '../core/offline/offline_cache_repository.dart';
import '../core/offline/offline_cache_repository_impl.dart';
import '../core/offline/offline_database.dart';
import '../core/offline/track_download_service.dart';
import '../core/storage/secure_storage.dart';
import '../features/auth/data/datasources/auth_remote_data_source.dart';
import '../features/auth/data/repositories/auth_repository_impl.dart';
import '../features/auth/domain/repositories/auth_repository.dart';
import '../features/auth/presentation/providers/forgot_password_controller.dart';
import '../features/auth/presentation/providers/login_controller.dart';
import '../features/auth/presentation/providers/register_controller.dart';
import '../features/auth/presentation/providers/reset_password_controller.dart';
import '../features/broadcaster/data/datasources/broadcaster_remote_data_source.dart';
import '../features/broadcaster/data/repositories/broadcaster_repository_impl.dart';
import '../features/broadcaster/domain/repositories/broadcaster_repository.dart';
import '../features/broadcaster/presentation/providers/broadcaster_controller.dart';
import '../features/playlists/presentation/providers/offline_playlist_controller.dart';
import '../features/playlists/presentation/providers/playlist_queue_controller.dart';
import '../features/profile/data/datasources/profile_remote_data_source.dart';
import '../features/profile/data/repositories/profile_repository_impl.dart';
import '../features/profile/domain/repositories/profile_repository.dart';
import '../features/profile/presentation/providers/profile_controller.dart';
import '../features/streams/data/datasources/stream_remote_data_source.dart';
import '../features/streams/data/repositories/stream_repository_impl.dart';
import '../features/streams/domain/repositories/stream_repository.dart';
import '../features/streams/presentation/providers/audio_player_controller.dart';
import '../features/streams/presentation/providers/discover_notifier.dart';
import '../features/streams/presentation/providers/favorites_controller.dart';
import '../features/streams/presentation/providers/stream_notifier.dart';
import '../core/audio/volume_store.dart';

/// Conteneur racine d'injection de dépendances (remplace `ProviderScope`).
///
/// Les dépendances infra sont des singletons paresseux (`Provider`), les
/// contrôleurs des `ChangeNotifierProvider`. Chaque `create` résout ses
/// dépendances via `context.read`, ce qui respecte le principe D (inversion
/// de dépendances) : aucun concret n'est instancié en interne.
class StreamPulseApp extends StatelessWidget {
  const StreamPulseApp({
    super.key,
    required this.audioService,
    required this.queueService,
    required this.child,
  });

  /// Service de lecture partagé (STR-109), créé au démarrage dans `main()` puis
  /// injecté ici : durée de vie = celle de l'application.
  ///
  /// [audioService] (direct) et [queueService] (file d'attente) sont deux vues
  /// du **même** lecteur natif. Deux paramètres plutôt qu'un objet portant les
  /// deux rôles : chaque contrôleur ne dépend ainsi que de ce qu'il utilise
  /// (principe I), et un test peut n'en simuler qu'un.
  final AudioPlaybackService audioService;
  final QueuePlaybackService queueService;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AudioPlaybackService>.value(value: audioService),
        Provider<QueuePlaybackService>.value(value: queueService),
        // Le volume ne dépend pas de la source : le curseur lit l'interface la
        // plus étroite qui le porte (principe I) et fonctionne donc aussi bien
        // pendant un direct que pendant une file d'attente (STR-244).
        Provider<PlaybackTransport>.value(value: audioService),
        Provider<VolumeStore>(
          create: (_) => const SharedPreferencesVolumeStore(),
        ),
        Provider<SecureStorage>(create: (_) => SecureStorage()),
        Provider<DioClient>(
          create: (ctx) => DioClient(ctx.read<SecureStorage>()),
        ),
        // Le lecteur natif ouvre ses propres connexions HTTP : il ne traverse
        // pas les intercepteurs de DioClient et doit obtenir son token ici.
        Provider<PlaybackAuth>(
          create: (ctx) =>
              PlaybackAuth(ctx.read<SecureStorage>(), ctx.read<DioClient>()),
        ),
        Provider<AuthRemoteDataSource>(
          create: (ctx) => AuthRemoteDataSource(ctx.read<DioClient>().authApi),
        ),
        Provider<AuthRepository>(
          create: (ctx) => AuthRepositoryImpl(
            ctx.read<AuthRemoteDataSource>(),
            ctx.read<SecureStorage>(),
          ),
        ),
        ChangeNotifierProvider<LoginController>(
          create: (ctx) => LoginController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<RegisterController>(
          create: (ctx) => RegisterController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<ForgotPasswordController>(
          create: (ctx) => ForgotPasswordController(ctx.read<AuthRepository>()),
        ),
        ChangeNotifierProvider<ResetPasswordController>(
          create: (ctx) => ResetPasswordController(ctx.read<AuthRepository>()),
        ),
        Provider<ProfileRemoteDataSource>(
          create: (ctx) =>
              ProfileRemoteDataSource(ctx.read<DioClient>().profileApi),
        ),
        Provider<ProfileRepository>(
          create: (ctx) =>
              ProfileRepositoryImpl(ctx.read<ProfileRemoteDataSource>()),
        ),
        ChangeNotifierProvider<ProfileController>(
          create: (ctx) => ProfileController(ctx.read<ProfileRepository>()),
        ),
        Provider<BroadcasterRemoteDataSource>(
          create: (ctx) =>
              BroadcasterRemoteDataSource(ctx.read<DioClient>().broadcasterApi),
        ),
        Provider<BroadcasterRepository>(
          create: (ctx) =>
              BroadcasterRepositoryImpl(ctx.read<BroadcasterRemoteDataSource>()),
        ),
        ChangeNotifierProvider<BroadcasterController>(
          create: (ctx) =>
              BroadcasterController(ctx.read<BroadcasterRepository>()),
        ),
        Provider<StreamRemoteDataSource>(
          create: (ctx) => StreamRemoteDataSource(
            ctx.read<DioClient>().streamingApi,
            ctx.read<DioClient>().dio,
          ),
        ),
        Provider<StreamRepository>(
          create: (ctx) =>
              StreamRepositoryImpl(ctx.read<StreamRemoteDataSource>()),
        ),
        ChangeNotifierProvider<StreamNotifier>(
          create: (ctx) => StreamNotifier(ctx.read<StreamRepository>()),
        ),
        ChangeNotifierProvider<FavoritesController>(
          create: (ctx) => FavoritesController(ctx.read<StreamRepository>()),
        ),
        ChangeNotifierProvider<DiscoverNotifier>(
          create: (ctx) => DiscoverNotifier(ctx.read<StreamRepository>()),
        ),
        // Lecteur audio partagé (STR-109) : un seul contrôleur app-level pilote
        // le service de premier plan ; le plein écran et le mini-player le lisent.
        ChangeNotifierProvider<AudioPlayerController>(
          create: (ctx) => AudioPlayerController(
            service: ctx.read<AudioPlaybackService>(),
            manifestStatus: ctx.read<StreamRepository>().manifestStatus,
          ),
        ),
        Provider<OfflineDatabase>(create: (_) => OfflineDatabase()),
        Provider<OfflineCacheRepository>(
          create: (ctx) =>
              OfflineCacheRepositoryImpl(ctx.read<OfflineDatabase>()),
        ),
        Provider<TrackDownloadService>(
          create: (ctx) => TrackDownloadService(
            ctx.read<DioClient>().dio,
            ctx.read<OfflineCacheRepository>(),
          ),
        ),
        ChangeNotifierProvider<ConnectivityService>(
          create: (_) => ConnectivityServiceImpl(),
        ),
        ChangeNotifierProvider<OfflinePlaylistController>(
          create: (ctx) => OfflinePlaylistController(
            cacheRepository: ctx.read<OfflineCacheRepository>(),
            downloadService: ctx.read<TrackDownloadService>(),
          )..init(),
        ),
        ChangeNotifierProvider<PlaylistQueueController>(
          create: (ctx) {
            final live = ctx.read<AudioPlayerController>();
            final queue = PlaylistQueueController(
              service: ctx.read<QueuePlaybackService>(),
              token: ctx.read<PlaybackAuth>().token,
              stopLive: live.stop,
              resolveTrackUri:
                  ctx.read<OfflineCacheRepository>().cachedFilePath,
            );
            live.onTakeOver = queue.clear;
            return queue;
          },
        ),
      ],
      child: child,
    );
  }
}
