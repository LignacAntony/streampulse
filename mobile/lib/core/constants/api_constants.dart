class ApiConstants {
  ApiConstants._();

  // 10.0.2.2 pointe vers localhost depuis l'émulateur Android.
  // Sur device physique ou simulateur iOS, utiliser l'IP du Mac (ex: 192.168.x.x).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );

  // Auth
  static const String login = '/api/auth/login';
  static const String register = '/api/auth/register';
  static const String refresh = '/api/auth/refresh';
  static const String logout = '/api/auth/logout';

  // Streams
  static const String streams = '/api/streams';

  // Tracks
  static const String tracks = '/api/tracks';

  // Utilisateur connecté
  static const String me = '/api/users/me';
}
