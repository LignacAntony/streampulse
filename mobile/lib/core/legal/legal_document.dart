/// Analyse du sous-ensemble Markdown utilisé par les documents légaux
/// (`assets/legal/*.md`, copies exactes de `docs/`).
///
/// Fonction pure, sans dépendance Flutter : c'est ce qui la rend testable sans
/// widget et vérifiable ligne à ligne.
///
/// Le choix de ne pas prendre de dépendance externe est délibéré :
/// `flutter_markdown` est discontinué, et ces deux documents n'utilisent que
/// des titres, des paragraphes, du gras, des listes et un tableau. Un analyseur
/// complet coûterait plus que ce qu'il rendrait.
library;

/// Nature d'un bloc du document, telle que la couche présentation doit la
/// rendre. `heading1` et `heading2` sont annoncés comme titres aux lecteurs
/// d'écran — c'est la raison d'être de la distinction.
enum LegalBlockKind { heading1, heading2, paragraph, bullet, tableRow, tableHeader }

/// Un bloc de document. [cells] n'est renseigné que pour les lignes de tableau.
class LegalBlock {
  const LegalBlock(this.kind, this.text, {this.cells = const []});

  final LegalBlockKind kind;

  /// Texte déjà nettoyé : gras et liens réduits à leur libellé.
  final String text;

  /// Cellules d'une ligne de tableau, dans l'ordre des colonnes.
  final List<String> cells;

  @override
  String toString() => '$kind($text)';
}

/// Motifs inline retirés du texte rendu. Le gras n'est pas restitué : un
/// document légal se lit d'un bout à l'autre, et une emphase perdue coûte
/// moins qu'un analyseur de spans à maintenir.
final _bold = RegExp(r'\*\*(.+?)\*\*');
final _link = RegExp(r'\[([^\]]+)\]\([^)]*\)');
final _code = RegExp(r'`([^`]+)`');

String _inline(String s) => s
    .replaceAllMapped(_bold, (m) => m[1]!)
    .replaceAllMapped(_link, (m) => m[1]!)
    .replaceAllMapped(_code, (m) => m[1]!)
    .trim();

/// Une ligne de séparation de tableau : `|---|---|`, avec ou sans espaces ou
/// deux-points d'alignement.
bool _isTableSeparator(String line) =>
    RegExp(r'^\|[\s:|-]+\|$').hasMatch(line) && line.contains('-');

List<String> _cells(String line) => line
    .substring(1, line.length - 1)
    .split('|')
    .map(_inline)
    .toList();

/// Découpe [source] en blocs affichables.
///
/// Les lignes consécutives d'un même paragraphe sont recollées : les documents
/// sont enveloppés à 80 colonnes dans le dépôt, ce qui n'a pas à se voir à
/// l'écran d'un téléphone.
List<LegalBlock> parseLegalDocument(String source) {
  final blocks = <LegalBlock>[];
  final paragraph = StringBuffer();

  void flushParagraph() {
    final text = _inline(paragraph.toString());
    paragraph.clear();
    if (text.isNotEmpty) {
      blocks.add(LegalBlock(LegalBlockKind.paragraph, text));
    }
  }

  for (final raw in source.split('\n')) {
    final line = raw.trimRight();

    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }
    if (line.startsWith('## ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.heading2, _inline(line.substring(3))));
      continue;
    }
    if (line.startsWith('# ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.heading1, _inline(line.substring(2))));
      continue;
    }
    if (line.startsWith('- ')) {
      flushParagraph();
      blocks.add(LegalBlock(LegalBlockKind.bullet, _inline(line.substring(2))));
      continue;
    }
    if (line.startsWith('|') && line.endsWith('|')) {
      flushParagraph();
      if (_isTableSeparator(line)) {
        // La ligne de tirets ne porte aucune information : elle sert
        // uniquement à marquer que la précédente était l'en-tête.
        if (blocks.isNotEmpty && blocks.last.kind == LegalBlockKind.tableRow) {
          final header = blocks.removeLast();
          blocks.add(LegalBlock(LegalBlockKind.tableHeader, header.text,
              cells: header.cells));
        }
        continue;
      }
      final cells = _cells(line);
      blocks.add(LegalBlock(LegalBlockKind.tableRow, cells.join(' — '),
          cells: cells));
      continue;
    }
    if (paragraph.isNotEmpty) paragraph.write(' ');
    paragraph.write(line.trim());
  }
  flushParagraph();
  return blocks;
}
