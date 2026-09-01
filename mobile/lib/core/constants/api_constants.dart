class ApiConstants {
  ApiConstants._();

  // Défaut : device physique (USB) ou simulateur iOS via `localhost`.
  // Device physique : nécessite `adb reverse tcp:8080 tcp:8080`.
  // Émulateur Android : surcharger avec
  //   --dart-define=API_BASE_URL=http://10.0.2.2:8080
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8080',
  );

  // Auth
  static const String login = '/api/auth/login';
  static const String googleLogin = '/api/auth/google';
  static const String register = '/api/auth/register';
  static const String refresh = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';
  static const String forgotPassword = '/api/auth/forgot-password';
  static const String resetPassword = '/api/auth/reset-password';
  static const String deleteAccount = '/api/auth/me';

  // Streams
  static const String streams = '/api/streams';

  /// Chemin du manifeste HLS d'un flux, **relatif** à [baseUrl] — la forme
  /// qu'attend Dio, qui préfixe lui-même. Utilisé par la sonde de manifeste
  /// (STR-229).
  static String playlistPath(String streamId) =>
      '/api/streams/$streamId/playlist.m3u8';

  /// URL du manifeste HLS d'un flux (lecture publique, ADR 023). Passée telle
  /// quelle au player natif via `AudioSource.uri` — sans en-tête d'auth. Dérivée
  /// de [playlistPath] : le player natif et la sonde doivent viser le même
  /// endpoint, les laisser diverger rendrait la sonde muette sur ce qui joue.
  static String hlsPlaylist(String streamId) =>
      '$baseUrl${playlistPath(streamId)}';

  // Tracks
  static const String tracks = '/api/tracks';

  /// URL du binaire audio d'une piste de la bibliothèque (US-05-04). Passée au
  /// player natif via `AudioSource.uri` — contrairement au manifeste HLS
  /// public, elle exige un en-tête `Authorization` (contenu privé).
  static String trackStream(String trackId) =>
      '$baseUrl/api/tracks/$trackId/stream';

  // Chat WebSocket (US-09-01)
  static String chatWebSocket(String streamId) {
    final wsBase = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '$wsBase/ws/streams/$streamId/chat';
  }

  // Recommandation (US-09-04)
  static const String recommendedTracks = '/api/recommendations/tracks';

  // Utilisateur connecté
  static const String me = '/api/users/me';
}
