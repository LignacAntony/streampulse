import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/app/app.dart';

void main() {
  testWidgets('App démarre sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: App()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
