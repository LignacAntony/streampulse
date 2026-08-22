import 'package:integration_test/integration_test_driver.dart';

/// Pilote des tests d'intégration (STR-243).
///
/// Nécessaire uniquement parce que `flutter test` n'accepte pas `--profile` :
/// seul `flutter drive` sait lancer un test d'intégration sur un binaire
/// optimisé. Or une mesure de trame en mode debug ne prouve rien — le code Dart
/// y est interprété sans optimisation.
///
/// Cf. `make frame-budget`.
Future<void> main() => integrationDriver();
