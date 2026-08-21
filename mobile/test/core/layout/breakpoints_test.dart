import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/layout/breakpoints.dart';

void main() {
  group('Breakpoints', () {
    test('une colonne sur téléphone, plus au-delà', () {
      expect(Breakpoints.columnsFor(375), 1); // iPhone portrait
      expect(Breakpoints.columnsFor(599), 1);
      expect(Breakpoints.columnsFor(600), 2); // rupture medium
      expect(Breakpoints.columnsFor(839), 2);
      expect(Breakpoints.columnsFor(840), 3); // rupture expanded
      // Trois au maximum : au-delà les cartes deviennent trop étroites.
      expect(Breakpoints.columnsFor(2000), 3);
    });

    test('la largeur de contenu est bornée, jamais étirée', () {
      // Téléphone en portrait : la contrainte ne mord pas, rien ne change là où
      // l'application passe l'essentiel de son temps.
      expect(Breakpoints.contentMaxWidth(375), 375);
      // Téléphone en paysage : c'est exactement le cas qui donnait un portrait
      // étiré, une ligne de trois mots traversant tout l'écran.
      expect(Breakpoints.contentMaxWidth(812), Breakpoints.medium);
      expect(Breakpoints.contentMaxWidth(1200), Breakpoints.medium);
    });

    test('isWide s\'aligne sur la rupture medium', () {
      expect(Breakpoints.isWide(599), isFalse);
      expect(Breakpoints.isWide(600), isTrue);
    });
  });

  group('ResponsiveContent', () {
    Future<double> widthAt(WidgetTester tester, Size surface) async {
      await tester.binding.setSurfaceSize(surface);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ResponsiveContent(
              child: SizedBox.expand(child: Placeholder(key: Key('contenu'))),
            ),
          ),
        ),
      );
      return tester.getSize(find.byKey(const Key('contenu'))).width;
    }

    testWidgets('laisse le contenu pleine largeur sur téléphone portrait', (
      tester,
    ) async {
      expect(await widthAt(tester, const Size(375, 812)), 375);
    });

    testWidgets('borne le contenu en paysage', (tester) async {
      expect(await widthAt(tester, const Size(812, 375)), Breakpoints.medium);
    });

    testWidgets('borne le contenu sur tablette', (tester) async {
      expect(await widthAt(tester, const Size(1024, 768)), Breakpoints.medium);
    });

    // Un parent non borné (ListView horizontal, Row libre) : contraindre y
    // lèverait une exception. Le widget doit s'effacer, pas casser.
    testWidgets('se retire quand la largeur n\'est pas bornée', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ResponsiveContent(
                child: SizedBox(width: 2000, height: 50, child: Placeholder()),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
