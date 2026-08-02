import 'package:flutter/material.dart';

/// Résultat d'un `PlaylistFormDialog` : nom (obligatoire) + description
/// (optionnelle, `null` si vide).
class PlaylistFormResult {
  const PlaylistFormResult({required this.name, this.description});

  final String name;
  final String? description;
}

/// Dialog de création/renommage d'une playlist. Réutilisé pour les deux cas :
/// champs vides (création) ou pré-remplis (renommage). Renvoie un
/// [PlaylistFormResult] via `Navigator.pop`, ou `null` si annulé.
class PlaylistFormDialog extends StatefulWidget {
  const PlaylistFormDialog({
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

  @override
  State<PlaylistFormDialog> createState() => _PlaylistFormDialogState();
}

class _PlaylistFormDialogState extends State<PlaylistFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;

  static const _maxNameLen = 120;
  static const _maxDescriptionLen = 500;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController =
        TextEditingController(text: widget.initialDescription ?? '');
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
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              key: const Key('playlist_name_field'),
              controller: _nameController,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nom'),
              validator: _validateName,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('playlist_description_field'),
              controller: _descriptionController,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Description (optionnelle)',
              ),
              validator: _validateDescription,
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('playlist_form_submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
