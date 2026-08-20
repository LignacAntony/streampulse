import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/features/auth/presentation/widgets/terms_checkbox.dart';

void main() {
  Future<void> monter(
    WidgetTester tester, {
    VoidCallback? onPrivacyTap,
    VoidCallback? onTermsTap,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TermsCheckbox(
            value: false,
            onChanged: (_) {},
            enabled: enabled,
            onPrivacyTap: onPrivacyTap,
            onTermsTap: onTermsTap,
          ),
        ),
      ),
    );
  }

  /// Appuie sur un fragment précis du Text.rich. Les deux libellés vivent dans
  /// le même widget : viser le widget entier ne dirait pas lequel a été touché.
  Future<void> appuyerSur(WidgetTester tester, String fragment) async {
    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(TermsCheckbox),
        matching: find.byType(RichText),
      ),
    );
    var trouve = false;
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.text == fragment) {
        (span.recognizer as TapGestureRecognizer?)?.onTap?.call();
        trouve = true;
        return false;
      }
      return true;
    });
    expect(trouve, isTrue, reason: 'fragment « $fragment » introuvable');
    await tester.pump();
  }

  testWidgets('le lien de politique de confidentialité est cliquable',
      (tester) async {
    var appels = 0;
    await monter(tester, onPrivacyTap: () => appels++);

    await appuyerSur(tester, 'politique de confidentialité');

    expect(appels, 1);
  });

  testWidgets("le lien de conditions d'utilisation est cliquable",
      (tester) async {
    var appels = 0;
    await monter(tester, onTermsTap: () => appels++);

    await appuyerSur(tester, "conditions d'utilisation");

    expect(appels, 1);
  });

  testWidgets('les deux libellés portent un recognizer', (tester) async {
    // Le défaut corrigé ici : les libellés étaient stylés en lien — couleur et
    // graisse — sans aucun recognizer. Ils avaient l'apparence d'un lien sans
    // en être un, et les documents visés n'existaient pas.
    await monter(tester);

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(TermsCheckbox),
        matching: find.byType(RichText),
      ),
    );
    final liens = <String>[];
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null && span.text != null) {
        liens.add(span.text!);
      }
      return true;
    });

    expect(liens, containsAll(<String>[
      'politique de confidentialité',
      "conditions d'utilisation",
    ]));
  });

  testWidgets('les liens sont soulignés, pas seulement colorés',
      (tester) async {
    // WCAG 1.4.1 : la couleur seule ne doit pas être le seul indice.
    await monter(tester);

    final richText = tester.widget<RichText>(
      find.descendant(
        of: find.byType(TermsCheckbox),
        matching: find.byType(RichText),
      ),
    );
    richText.text.visitChildren((span) {
      if (span is TextSpan && span.recognizer != null) {
        expect(span.style?.decoration, TextDecoration.underline,
            reason: 'le libellé « ${span.text} » doit être souligné');
      }
      return true;
    });
  });
}
