import 'package:flutter/material.dart';

/// Résultat d'un `PlaylistFormSheet` : nom (obligatoire) + description
/// (optionnelle, `null` si vide).
class PlaylistFormResult {
  const PlaylistFormResult({required this.name, this.description});

  final String name;
  final String? description;
}

/// Feuille modale (bottom sheet) de création/renommage d'une playlist.
///
/// Monte depuis le bas et se ferme par glissement vers le bas (drag handle en
/// haut). Réutilisée pour la création (champs vides) et le renommage (champs
/// pré-remplis). Renvoie un [PlaylistFormResult] via `Navigator.pop`, ou `null`
/// si annulée.
///
/// ⚠️ Le contrôle « Disponible hors ligne » est présent côté UI mais **non
/// branché** : la logique de téléchargement hors ligne fera l'objet d'une PR
/// dédiée.
class PlaylistFormSheet extends StatefulWidget {
  const PlaylistFormSheet({
    super.key,
    required this.title,
    required this.submitLabel,
    this.initialName = '',
    this.initialDescription,
  });

  final String title;
  final String submitLabel;
  final String initialName;
  final String? initialDescription;

  /// Ouvre la feuille modale et renvoie le résultat saisi (ou `null` si fermée).
  static Future<PlaylistFormResult?> show(
    BuildContext context, {
    required String title,
    required String submitLabel,
    String initialName = '',
    String? initialDescription,
  }) {
    return showModalBottomSheet<PlaylistFormResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      // Fermeture au glissement vers le bas (comportement par défaut d'une
      // bottom sheet modale, renforcé par le drag handle).
      builder: (_) => PlaylistFormSheet(
        title: title,
        submitLabel: submitLabel,
        initialName: initialName,
        initialDescription: initialDescription,
      ),
    );
  }

  @override
  State<PlaylistFormSheet> createState() => _PlaylistFormSheetState();
}

class _PlaylistFormSheetState extends State<PlaylistFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  static const _maxNameLen = 120;
  static const _maxDescriptionLen = 500;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController = TextEditingController(
      text: widget.initialDescription ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Le nom est requis';
    if (name.length > _maxNameLen) return 'Nom trop long (max $_maxNameLen)';
    return null;
  }

  String? _validateDescription(String? value) {
    final desc = value?.trim() ?? '';
    if (desc.length > _maxDescriptionLen) {
      return 'Description trop longue (max $_maxDescriptionLen)';
    }
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    final rawDesc = _descriptionController.text.trim();
    Navigator.of(context).pop(
      PlaylistFormResult(
        name: name,
        description: rawDesc.isEmpty ? null : rawDesc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    // La sheet reste fixe à l'ouverture du clavier (pas de padding sur
    // viewInsets) : le contenu est déjà défilable si nécessaire.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('playlist_form_close'),
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _FieldLabel('NOM DE LA PLAYLIST'),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('playlist_name_field'),
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Ma superbe playlist',
              ),
              validator: _validateName,
            ),
            const SizedBox(height: 20),
            const _FieldLabel('DESCRIPTION (OPTIONNEL)'),
            const SizedBox(height: 8),
            TextFormField(
              key: const Key('playlist_description_field'),
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Quel est le mood de cette sélection ?',
              ),
              validator: _validateDescription,
            ),
            const SizedBox(height: 24),
            const Opacity(
              opacity: 0.5,
              child: OfflineToggleCard(
                isOffline: false,
                subtitle: 'Disponible après création',
              ),
            ),
            const SizedBox(height: 24),
            _GradientButton(
              key: const Key('playlist_form_submit'),
              label: widget.submitLabel,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: colors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class OfflineToggleCard extends StatelessWidget {
  const OfflineToggleCard({
    super.key,
    required this.isOffline,
    this.onChanged,
    this.progress,
    this.subtitle,
  });

  final bool isOffline;
  final ValueChanged<bool>? onChanged;
  final double? progress;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDownloading = progress != null && progress! < 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isOffline ? Icons.cloud_done : Icons.download_outlined,
                color: isOffline
                    ? colors.primary
                    : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Disponible hors ligne', style: text.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    else if (isDownloading)
                      Text(
                        'Téléchargement en cours…',
                        style: text.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      )
                    else if (isOffline)
                      Text(
                        'Prêt pour la lecture hors ligne',
                        style: text.bodySmall?.copyWith(
                          color: colors.primary,
                        ),
                      ),
                  ],
                ),
              ),
              Switch(
                key: const Key('playlist_offline_toggle'),
                value: isOffline,
                onChanged: onChanged,
              ),
            ],
          ),
          if (isDownloading) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bouton principal à dégradé (« Créer » / « Enregistrer »).
class _GradientButton extends StatelessWidget {
  const _GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [Color(0xFFB79CF6), Color(0xFF7C4DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
