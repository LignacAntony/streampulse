class AppConstants {
  AppConstants._();

  // Durée d'affichage du splash avant la redirection
  static const Duration splashDuration = Duration(seconds: 2);

  // Taille minimale des zones tactiles — WCAG 2.1 niveau AA
  static const double minTouchTarget = 44.0;

  // Timeouts HTTP
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 10);
}
