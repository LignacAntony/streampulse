import 'package:flutter_test/flutter_test.dart';
import 'package:streampulse/core/legal/legal_document.dart';

void main() {
  group('parseLegalDocument', () {
    test('reconnaît les deux niveaux de titre', () {
      final blocks = parseLegalDocument('# Titre\n\n## Section\n');
      expect(blocks.map((b) => b.kind), [
        LegalBlockKind.heading1,
        LegalBlockKind.heading2,
      ]);
      expect(blocks.first.text, 'Titre');
      expect(blocks.last.text, 'Section');
    });

    test('recolle les lignes d’un même paragraphe', () {
      // Les documents sont enveloppés à 80 colonnes dans le dépôt ; l'écran
      // d'un téléphone ne doit pas hériter de ces retours à la ligne.
      final blocks = parseLegalDocument('Une phrase\ncoupée en deux.\n');
      expect(blocks, hasLength(1));
      expect(blocks.single.text, 'Une phrase coupée en deux.');
    });

    test('sépare deux paragraphes sur une ligne vide', () {
      final blocks = parseLegalDocument('Premier.\n\nSecond.\n');
      expect(blocks.map((b) => b.text), ['Premier.', 'Second.']);
    });

    test('retire le gras, les liens et le code du texte rendu', () {
      final blocks = parseLegalDocument(
        'Texte **important** avec [un lien](rgpd.md) et `du code`.\n',
      );
      expect(blocks.single.text, 'Texte important avec un lien et du code.');
    });

    test('reconnaît les puces', () {
      final blocks = parseLegalDocument('- premier\n- second\n');
      expect(blocks.map((b) => b.kind),
          [LegalBlockKind.bullet, LegalBlockKind.bullet]);
      expect(blocks.first.text, 'premier');
    });

    test('marque la première ligne de tableau comme en-tête', () {
      final blocks = parseLegalDocument(
        '| Donnée | Durée |\n|---|---|\n| Journaux | 30 jours |\n',
      );
      expect(blocks.map((b) => b.kind), [
        LegalBlockKind.tableHeader,
        LegalBlockKind.tableRow,
      ]);
      expect(blocks.first.cells, ['Donnée', 'Durée']);
      expect(blocks.last.cells, ['Journaux', '30 jours']);
    });

    test('la ligne de séparation ne produit aucun bloc', () {
      final blocks = parseLegalDocument('| a | b |\n|:---|---:|\n');
      expect(blocks, hasLength(1));
      expect(blocks.single.kind, LegalBlockKind.tableHeader);
    });

    test('un document vide ne produit aucun bloc', () {
      expect(parseLegalDocument(''), isEmpty);
      expect(parseLegalDocument('\n\n  \n'), isEmpty);
    });
  });

  group('renvois entre documents', () {
    test('un renvoi vers un document embarqué devient un span cliquable', () {
      // Le cas réel : cgu.md renvoie à la politique de confidentialité, qui
      // est elle aussi embarquée — donc ouvrable dans l'application.
      final blocks = parseLegalDocument(
        'En créant un compte, vous acceptez ces conditions et la '
        '[politique de confidentialité](politique-confidentialite.md).\n',
      );

      final spans = blocks.single.spans;
      expect(spans, isNotEmpty, reason: 'le renvoi doit produire des spans');

      final liens = spans.where((s) => s.isLink).toList();
      expect(liens, hasLength(1));
      expect(liens.single.text, 'politique de confidentialité');
      expect(liens.single.target, 'politique-confidentialite.md');

      // Le texte complet reste la référence, renvoi réduit à son libellé.
      expect(blocks.single.text, contains('politique de confidentialité'));
      expect(blocks.single.text, isNot(contains('.md')));
    });

    test('un renvoi vers un document non embarqué reste inerte', () {
      // rgpd.md et securite.md vivent dans le dépôt, pas dans l'application :
      // afficher un lien qui ne mène nulle part serait pire que du texte.
      final blocks = parseLegalDocument(
        'La version technique complète se trouve dans [le dossier RGPD](rgpd.md).\n',
      );

      expect(blocks.single.spans, isEmpty);
      expect(blocks.single.text, contains('le dossier RGPD'));
    });

    test('les fragments encadrant un renvoi sont conservés dans l’ordre', () {
      final blocks = parseLegalDocument(
        'Avant [le lien](cgu.md) après.\n',
      );

      final spans = blocks.single.spans;
      expect(spans.map((s) => s.text).toList(), ['Avant', 'le lien', 'après.']);
      expect(spans.map((s) => s.isLink).toList(), [false, true, false]);
    });

    test('un chemin relatif est réduit à son nom de fichier', () {
      final blocks = parseLegalDocument('Voir [les CGU](../docs/cgu.md).\n');
      expect(blocks.single.spans.firstWhere((s) => s.isLink).target, 'cgu.md');
    });
  });
}
