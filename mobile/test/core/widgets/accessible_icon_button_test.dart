import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/constants/app_constants.dart';
import 'package:streampulse/core/widgets/accessible_icon_button.dart';

import '../../support/accessibility.dart';

Future<SemanticsHandle> _pump(WidgetTester tester, Widget child) async {
  final handle = tester.ensureSemantics();
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  return handle;
}

void main() {
  testWidgets('expose un LABEL sémantique, pas seulement un tooltip', (
    tester,
  ) async {
    final handle = await _pump(
      tester,
      AccessibleIconButton(
        icon: Icons.pause,
        label: 'Mettre en pause',
        onPressed: () {},
      ),
    );

    // Toute la raison d'être de ce widget. Un IconButton(tooltip:) remplit le
    // champ `tooltip` du nœud sémantique, pas le champ `label` : sur iOS le
    // tooltip devient un hint, et VoiceOver annonce « bouton » sans nom.
    expect(find.bySemanticsLabel('Mettre en pause'), findsOneWidget);
    expectNoTooltipOnlyTapTargets(tester);
    await expectMeetsAccessibilityGuidelines(tester);
    handle.dispose();
  });

  testWidgets('un IconButton nu échoue là où celui-ci passe', (tester) async {
    // Test de contrôle : sans lui, on ne saurait pas si la garde ci-dessus
    // vérifie quelque chose ou passe toujours.
    final handle = await _pump(
      tester,
      IconButton(
        onPressed: () {},
        tooltip: 'Mettre en pause',
        icon: const Icon(Icons.pause),
      ),
    );

    expect(tapTargetsLabelledOnlyByTooltip(tester), ['Mettre en pause']);
    handle.dispose();
  });

  testWidgets('le tooltip peut différer du libellé', (tester) async {
    final handle = await _pump(
      tester,
      AccessibleIconButton(
        icon: Icons.stop_circle_outlined,
        label: 'Interrompre le flux Radio Neon',
        tooltip: 'Interrompre',
        onPressed: () {},
      ),
    );

    expect(
      find.bySemanticsLabel('Interrompre le flux Radio Neon'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('la zone tactile tient les 44 px de WCAG 2.1 AA', (tester) async {
    final handle = await _pump(
      tester,
      AccessibleIconButton(icon: Icons.add, label: 'Ajouter', onPressed: () {}),
    );

    final size = tester.getSize(find.byType(AccessibleIconButton));
    expect(size.width, greaterThanOrEqualTo(AppConstants.minTouchTarget));
    expect(size.height, greaterThanOrEqualTo(AppConstants.minTouchTarget));
    handle.dispose();
  });

  testWidgets('un bouton désactivé garde son nom', (tester) async {
    final handle = await _pump(
      tester,
      const AccessibleIconButton(
        icon: Icons.skip_next,
        label: 'Piste suivante',
        onPressed: null,
      ),
    );

    expect(find.bySemanticsLabel('Piste suivante'), findsOneWidget);
    handle.dispose();
  });

  // Un utilisateur qui grossit le texte ne doit pas voir la mise en page casser.
  testWidgets('survit à un grossissement de texte extrême', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.binding.setSurfaceSize(const Size(375, 812));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                AccessibleIconButton(
                  icon: Icons.add,
                  label: 'Ajouter',
                  onPressed: () {},
                ),
                const Expanded(child: Text('Un titre de flux assez long')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
