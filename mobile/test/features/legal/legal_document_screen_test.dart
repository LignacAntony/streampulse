import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/legal/presentation/screens/legal_document_screen.dart';

void main() {
  // Ces tests lisent les vrais assets : c'est le seul moyen de vérifier que
  // pubspec.yaml les déclare réellement. Un test sur une chaîne en dur
  // passerait alors même que l'application afficherait une page d'erreur.
  TestWidgetsFlutterBinding.ensureInitialized();

  // rootBundle met en cache le *Future* de chaque asset, pas son contenu. Un
  // Future créé dans la zone asynchrone d'un test précédent ne se recomplète
  // jamais dans un test suivant : sans cette purge, le troisième test du
  // fichier attend indéfiniment un asset que le premier a déjà lu.
  setUp(rootBundle.clear);

  Future<void> ouvrir(WidgetTester tester, LegalDocument document) async {
    await tester.pumpWidget(
      MaterialApp(home: LegalDocumentScreen(document: document)),
    );

    // La lecture de l'asset ne planifie aucune image : pumpAndSettle peut
    // rendre la main avant qu'elle aboutisse. runAsync accorde un vrai tour de
    // boucle d'événements, pump reconstruit avec le résultat.
    for (var i = 0; i < 20 && find.byType(ListView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    // Échoue si pubspec.yaml ne déclare pas l'asset : l'écran resterait vide.
    expect(find.byType(ListView), findsOneWidget,
        reason: "l'asset ${document.assetPath} n'a pas été chargé");
  }

  /// Le document est rendu par un ListView.builder : ce qui est hors écran
  /// n'existe pas encore dans l'arbre. Faire défiler est donc nécessaire, et
  /// prouve au passage que le document ne s'arrête pas au premier écran.
  ///
  /// Défilement à la main plutôt que scrollUntilVisible : ce dernier exige une
  /// correspondance unique et lève dès que le finder en trouve zéro ou
  /// plusieurs — or un libellé peut apparaître deux fois dans un document
  /// légal, et il n'apparaît par construction jamais avant d'avoir défilé.
  Future<void> defilerJusqua(WidgetTester tester, Finder cible) async {
    for (var i = 0; i < 40 && cible.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('la politique de confidentialité est embarquée et lisible',
      (tester) async {
    await ouvrir(tester, LegalDocument.privacy);

    expect(find.text('Politique de confidentialité'), findsWidgets);
    expect(find.textContaining('Ce que nous collectons'), findsOneWidget);

    // Une durée de conservation, tirée du tableau : vérifie que les tableaux
    // sont bien rendus et pas silencieusement avalés par l'analyseur.
    await defilerJusqua(tester, find.textContaining('30 jours'));
    expect(find.textContaining('30 jours'), findsWidgets);
  });

  testWidgets('les CGU sont embarquées et lisibles', (tester) async {
    await ouvrir(tester, LegalDocument.terms);

    expect(find.textContaining("Ce qu'est StreamPulse"), findsOneWidget);

    await defilerJusqua(tester, find.textContaining('clé de diffusion'));
    expect(find.textContaining('clé de diffusion'), findsWidgets);
  });

  testWidgets('le titre du document est annoncé comme titre', (tester) async {
    final handle = tester.ensureSemantics();
    await ouvrir(tester, LegalDocument.terms);

    // Sans header: true, un lecteur d'écran lirait le document d'un bloc, sans
    // permettre d'en parcourir la structure.
    final titre = find.text("Conditions générales d'utilisation");
    expect(titre, findsOneWidget);
    expect(
      tester.getSemantics(titre),
      matchesSemantics(
        isHeader: true,
        label: "Conditions générales d'utilisation",
      ),
    );
    handle.dispose();
  });

  testWidgets('le renvoi des CGU ouvre la politique de confidentialité',
      (tester) async {
    // Le renvoi que la revue de la PR #321 a relevé : les CGU citent la
    // politique de confidentialité, qui est elle aussi embarquée. Le laisser
    // inerte revenait à afficher un lien mort dans un parcours de consentement.
    await ouvrir(tester, LegalDocument.terms);

    final richTexts = tester.widgetList<RichText>(find.byType(RichText));
    TapGestureRecognizer? renvoi;
    for (final rt in richTexts) {
      rt.text.visitChildren((span) {
        if (span is TextSpan &&
            span.text == 'politique de confidentialité' &&
            span.recognizer is TapGestureRecognizer) {
          renvoi = span.recognizer! as TapGestureRecognizer;
          return false;
        }
        return true;
      });
      if (renvoi != null) break;
    }

    expect(renvoi, isNotNull,
        reason: 'le renvoi vers la politique doit porter un recognizer');

    renvoi!.onTap!();
    await tester.pumpAndSettle();

    expect(find.text('Politique de confidentialité'), findsWidgets);
    expect(find.textContaining('Ce que nous collectons'), findsOneWidget);
  });
}
