import 'package:flutter/material.dart';

import '../../domain/entities/broadcast_stream.dart';

/// Valeurs saisies dans [CreateStreamSheet], renvoyées à l'appelant via
/// `Navigator.pop`. L'appel réseau reste la responsabilité de l'écran.
class CreateStreamValues {
  const CreateStreamValues({
    required this.title,
    required this.isPublic,
    this.description,
    this.category,
  });

  final String title;
  final bool isPublic;
  final String? description;
  final String? category;
}

/// Formulaire de création d'un flux (US-06-01). Les bornes reprennent celles
/// du backend (`normalizeStreamFields`) pour éviter un aller-retour sur une
/// saisie manifestement invalide : titre 3-120, description <= 500, catégorie
/// dans la liste blanche.
class CreateStreamSheet extends StatefulWidget {
  const CreateStreamSheet({super.key});

  /// Ouvre le formulaire et renvoie les valeurs saisies, ou null si annulé.
  static Future<CreateStreamValues?> show(BuildContext context) {
    return showModalBottomSheet<CreateStreamValues>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CreateStreamSheet(),
    );
  }

  @override
  State<CreateStreamSheet> createState() => _CreateStreamSheetState();
}

class _CreateStreamSheetState extends State<CreateStreamSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _category;
  bool _isPublic = true;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onSubmit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final description = _descriptionController.text.trim();
    Navigator.of(context).pop(
      CreateStreamValues(
        title: _titleController.text.trim(),
        isPublic: _isPublic,
        description: description.isEmpty ? null : description,
        category: _category,
      ),
    );
  }

  String? _validateTitle(String? value) {
    final title = value?.trim() ?? '';
    if (title.length < kStreamTitleMinLength) {
      return 'Au moins $kStreamTitleMinLength caractères';
    }
    if (title.length > kStreamTitleMaxLength) {
      return 'Au plus $kStreamTitleMaxLength caractères';
    }
    return null;
  }

  String? _validateDescription(String? value) {
    final description = value?.trim() ?? '';
    if (description.length > kStreamDescriptionMaxLength) {
      return 'Au plus $kStreamDescriptionMaxLength caractères';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Padding(
      // Remonte le formulaire au-dessus du clavier.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nouveau flux', style: text.titleLarge),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('create_stream_title_field'),
                controller: _titleController,
                autofocus: true,
                textInputAction: TextInputAction.next,
                maxLength: kStreamTitleMaxLength,
                decoration: const InputDecoration(
                  labelText: 'Titre',
                  hintText: 'Le talk du soir',
                ),
                validator: _validateTitle,
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('create_stream_description_field'),
                controller: _descriptionController,
                maxLines: 3,
                maxLength: kStreamDescriptionMaxLength,
                decoration: const InputDecoration(
                  labelText: 'Description (facultatif)',
                ),
                validator: _validateDescription,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const Key('create_stream_category_field'),
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Catégorie (facultatif)',
                ),
                items: [
                  for (final category in kStreamCategories)
                    DropdownMenuItem(
                      value: category,
                      child: Text(streamCategoryLabel(category)),
                    ),
                ],
                onChanged: (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                key: const Key('create_stream_public_switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Flux public'),
                subtitle: Text(
                  _isPublic
                      ? 'Visible de tous dans la découverte'
                      : 'Visible de vous seul',
                ),
                value: _isPublic,
                onChanged: (value) => setState(() => _isPublic = value),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('create_stream_submit_button'),
                onPressed: _onSubmit,
                child: const Text('Créer le flux'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Libellé français d'une catégorie backend. La valeur brute est conservée
/// côté domaine et transmise telle quelle à l'API : seule l'étiquette est
/// traduite.
String streamCategoryLabel(String category) {
  switch (category) {
    case 'music':
      return 'Musique';
    case 'talk':
      return 'Discussion';
    case 'technology':
      return 'Technologie';
    case 'gaming':
      return 'Jeux vidéo';
    case 'news':
      return 'Actualités';
    case 'sport':
      return 'Sport';
    case 'other':
      return 'Autre';
    default:
      return category;
  }
}
