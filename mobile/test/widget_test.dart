import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:streampulse/app/app.dart';
import 'package:streampulse/app/app_providers.dart';

void main() {
  testWidgets('App démarre sans erreur', (WidgetTester tester) async {
    await tester.pumpWidget(
      const StreamPulseApp(child: App()),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
