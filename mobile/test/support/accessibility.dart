import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vérifications d'accessibilité partagées (STR-246).
///
/// `flutter_test` embarque des vérificateurs conformes aux recommandations des
/// deux plateformes. Les faire tourner en CI vaut mieux qu'une affirmation de
/// conformité dans un document : ils échouent quand la règle est violée, y
/// compris sur du code écrit plus tard.
///
/// Ce qu'ils couvrent :
///
/// - `androidTapTargetGuideline` / `iOSTapTargetGuideline` — taille minimale des
///   zones tactiles (48 px / 44 px).
/// - `labeledTapTargetGuideline` — tout élément tapable porte un texte.
/// - `textContrastGuideline` — contraste texte/fond WCAG AA.
///
/// Ce qu'ils **ne** couvrent pas, et qui reste à vérifier autrement : l'ordre de
/// parcours, la pertinence des libellés, et le comportement réel de TalkBack ou
/// VoiceOver.
Future<void> expectMeetsAccessibilityGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Relève les nœuds tapables dont le texte n'est porté que par un **tooltip**.
///
/// `labeledTapTargetGuideline` les accepte : un tooltip remplit le champ
/// `tooltip` du nœud sémantique, et le vérificateur regarde label **ou**
/// tooltip. Mais les deux champs ne se valent pas côté plateforme — sur iOS le
/// tooltip devient un *hint*, pas un *label*, et VoiceOver annonce alors
/// « bouton » sans nom.
///
/// Cette vérification est donc plus stricte que la garde de Flutter, à dessein.
List<String> tapTargetsLabelledOnlyByTooltip(WidgetTester tester) {
  final found = <String>[];

  void walk(SemanticsNode node) {
    final data = node.getSemanticsData();
    final tappable = data.actions & SemanticsAction.tap.index != 0;
    if (tappable && data.label.isEmpty && data.tooltip.isNotEmpty) {
      found.add(data.tooltip);
    }
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // L'arbre sémantique ne vit pas sur le PipelineOwner racine mais sur ses
  // enfants (un par vue). Chercher seulement à la racine rendait une liste vide
  // — donc « rien à signaler » — alors que rien n'avait été inspecté : un
  // vérificateur qui ne trouve pas son sujet doit échouer, pas rassurer.
  var inspected = 0;
  void visitOwner(PipelineOwner owner) {
    final root = owner.semanticsOwner?.rootSemanticsNode;
    if (root != null) {
      inspected++;
      walk(root);
    }
    owner.visitChildren(visitOwner);
  }

  visitOwner(tester.binding.rootPipelineOwner);
  if (inspected == 0) {
    fail(
      'aucun arbre sémantique trouvé — `tester.ensureSemantics()` a-t-il '
      'bien été appelé avant de monter le widget ?',
    );
  }
  return found;
}

/// Échoue si un élément tapable n'est nommé que par un tooltip.
void expectNoTooltipOnlyTapTargets(WidgetTester tester) {
  final offenders = tapTargetsLabelledOnlyByTooltip(tester);
  expect(
    offenders,
    isEmpty,
    reason:
        'Ces éléments tapables n\'ont qu\'un tooltip, donc aucun nom pour '
        'VoiceOver : ${offenders.join(', ')}. Utiliser AccessibleIconButton, '
        'ou poser un Semantics(label:).',
  );
}
