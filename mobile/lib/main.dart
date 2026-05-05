import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

// ProviderScope est le conteneur racine de Riverpod : il intercepte tous les
// providers et permet l'injection de dépendances dans l'arbre de widgets.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const ProviderScope(
      child: App(),
    ),
  );
}
