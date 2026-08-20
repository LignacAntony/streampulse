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
}
