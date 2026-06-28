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
  static const String register = '/api/auth/register';
  static const String refresh = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';
  static const String forgotPassword = '/api/auth/forgot-password';
  static const String resetPassword = '/api/auth/reset-password';
  static const String deleteAccount = '/api/auth/me';

  // Streams
  static const String streams = '/api/streams';

  // Tracks
  static const String tracks = '/api/tracks';

  // Utilisateur connecté
  static const String me = '/api/users/me';
}
