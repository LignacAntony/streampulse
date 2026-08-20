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

/// Un fragment de texte, éventuellement porteur d'un renvoi vers un autre
/// document légal embarqué.
///
/// [target] ne vaut que pour les renvois **ouvrables dans l'application**. Les
/// liens vers des documents qui ne sont pas embarqués — le dossier RGPD, le
/// schéma de sécurité, qui vivent dans le dépôt — restent du texte : afficher
/// un lien qui ne mène nulle part serait pire que de n'en pas afficher.
class LegalSpan {
  const LegalSpan(this.text, {this.target});

  final String text;

  /// Nom de fichier de l'asset visé, ou null pour du texte ordinaire.
  final String? target;

  bool get isLink => target != null;
}

/// Un bloc de document. [cells] n'est renseigné que pour les lignes de tableau.
class LegalBlock {
  const LegalBlock(this.kind, this.text, {this.cells = const [], this.spans = const []});

  final LegalBlockKind kind;

  /// Texte complet du bloc, gras et liens réduits à leur libellé. Reste la
  /// représentation de référence : c'est elle que lisent les tests et tout
  /// rendu qui n'a que faire des renvois.
  final String text;

  /// Cellules d'une ligne de tableau, dans l'ordre des colonnes.
  final List<String> cells;

  /// Découpage du bloc en fragments, dont certains portent un renvoi. Vide
  /// quand le bloc ne contient aucun renvoi ouvrable — la présentation retombe
  /// alors sur [text].
  final List<LegalSpan> spans;

  @override
  String toString() => '$kind($text)';
}

/// Les documents légaux embarqués, par nom de fichier. Un renvoi vers l'un
/// d'eux est ouvrable ; tout autre reste inerte.
const embeddedLegalDocuments = {
  'politique-confidentialite.md',
  'cgu.md',
};

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
/// Découpe [source] en fragments, en ne conservant comme renvoi que les liens
/// vers un document légal **embarqué**.
///
/// Rend une liste vide quand aucun renvoi ouvrable n'est présent : la
/// présentation retombe alors sur le texte simple, sans construire d'arbre de
/// spans pour rien — ce qui est le cas de la quasi-totalité des paragraphes.
List<LegalSpan> _spans(String source) {
  final matches = _link.allMatches(source).where(
        (m) => embeddedLegalDocuments.contains(_targetOf(m)),
      );
  if (matches.isEmpty) return const [];

  final out = <LegalSpan>[];
  var curseur = 0;
  for (final m in matches) {
    if (m.start > curseur) {
      out.add(LegalSpan(_inline(source.substring(curseur, m.start))));
    }
    out.add(LegalSpan(m[1]!, target: _targetOf(m)));
    curseur = m.end;
  }
  if (curseur < source.length) {
    out.add(LegalSpan(_inline(source.substring(curseur))));
  }
  return out;
}

/// Cible d'un lien, réduite à son nom de fichier : les documents se référencent
/// entre eux par chemin relatif, et seul le nom identifie l'asset.
String _targetOf(RegExpMatch m) {
  final url = m[0]!;
  final debut = url.lastIndexOf('(') + 1;
  final cible = url.substring(debut, url.length - 1);
  return cible.split('/').last;
}

List<LegalBlock> parseLegalDocument(String source) {
  final blocks = <LegalBlock>[];
  final paragraph = StringBuffer();

  void flushParagraph() {
    final brut = paragraph.toString();
    paragraph.clear();
    final text = _inline(brut);
    if (text.isEmpty) return;
    blocks.add(LegalBlock(
      LegalBlockKind.paragraph,
      text,
      spans: _spans(brut),
    ));
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
