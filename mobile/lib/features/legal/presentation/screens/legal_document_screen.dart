import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../../../core/legal/legal_document.dart';

/// Les deux documents que l'utilisateur doit pouvoir lire **avant** de créer un
/// compte. Embarqués comme assets et non servis par l'API : ils doivent
/// s'ouvrir sans réseau et sans session, sinon la case de consentement de
/// l'inscription renverrait à un texte inaccessible.
enum LegalDocument {
  privacy('assets/legal/politique-confidentialite.md', 'Politique de confidentialité'),
  terms('assets/legal/cgu.md', "Conditions d'utilisation");

  const LegalDocument(this.assetPath, this.title);

  final String assetPath;
  final String title;
}

/// Affiche un document légal embarqué.
class LegalDocumentScreen extends StatefulWidget {
  const LegalDocumentScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  State<LegalDocumentScreen> createState() => _LegalDocumentScreenState();
}

class _LegalDocumentScreenState extends State<LegalDocumentScreen> {
  // Chargé une seule fois : un Future recréé dans build() relancerait la
  // lecture de l'asset à chaque reconstruction.
  late final Future<List<LegalBlock>> _blocks = _load();

  Future<List<LegalBlock>> _load() async {
    final source = await rootBundle.loadString(widget.document.assetPath);
    return parseLegalDocument(source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.document.title)),
      body: FutureBuilder<List<LegalBlock>>(
        future: _blocks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _LegalError();
          }
          final blocks = snapshot.data;
          if (blocks == null) {
            // Volontairement rien, et surtout pas d'indicateur de progression :
            // la lecture d'un asset local dure quelques millisecondes, un
            // spinner n'y ferait que clignoter. Il aurait aussi le défaut
            // d'animer sans fin, ce qui rend l'écran impossible à stabiliser
            // en test.
            return const SizedBox.shrink();
          }
          // Pas de Scrollbar explicite : ListView en pose déjà une sur les
          // plateformes qui en veulent, et son animation d'estompage
          // entretient des frames indéfiniment — de quoi faire expirer tout
          // pumpAndSettle en test.
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            itemCount: blocks.length,
            itemBuilder: (context, i) => _LegalBlockView(block: blocks[i]),
          );
        },
      ),
    );
  }
}

class _LegalError extends StatelessWidget {
  const _LegalError();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          "Ce document n'a pas pu être ouvert. Il reste consultable dans le "
          'dépôt du projet, dossier docs.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _LegalBlockView extends StatelessWidget {
  const _LegalBlockView({required this.block});

  final LegalBlock block;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    switch (block.kind) {
      case LegalBlockKind.heading1:
        // header: true fait annoncer « titre » par VoiceOver et TalkBack, et
        // alimente la navigation par titres — ce qui n'arriverait pas avec un
        // simple Text en gros caractères.
        return Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(block.text, style: text.headlineSmall),
          ),
        );
      case LegalBlockKind.heading2:
        return Semantics(
          header: true,
          child: Padding(
            padding: const EdgeInsets.only(top: 24, bottom: 8),
            child: Text(block.text, style: text.titleMedium),
          ),
        );
      case LegalBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(block.text, style: text.bodyMedium),
        );
      case LegalBlockKind.bullet:
        return Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: text.bodyMedium),
              Expanded(child: Text(block.text, style: text.bodyMedium)),
            ],
          ),
        );
      case LegalBlockKind.tableHeader:
      case LegalBlockKind.tableRow:
        // Un tableau à deux colonnes sur un écran de téléphone devient
        // illisible ; les cellules sont empilées, ce qu'un lecteur d'écran
        // restitue aussi correctement qu'une grille.
        final isHeader = block.kind == LegalBlockKind.tableHeader;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cell in block.cells)
                if (cell.isNotEmpty)
                  Text(
                    cell,
                    style: isHeader
                        ? text.labelLarge?.copyWith(color: colors.primary)
                        : text.bodyMedium,
                  ),
              if (!isHeader) Divider(color: colors.outlineVariant, height: 16),
            ],
          ),
        );
    }
  }
}
