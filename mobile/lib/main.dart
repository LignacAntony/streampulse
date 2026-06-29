import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_providers.dart';

// StreamPulseApp pose le MultiProvider racine (injection de dépendances)
// au-dessus de l'arbre de widgets.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const StreamPulseApp(
      child: App(),
    ),
  );
}
