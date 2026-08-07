import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/datasources/track_remote_data_source.dart';
import '../../data/repositories/track_repository_impl.dart';
import '../../domain/repositories/track_repository.dart';
import '../providers/upload_track_controller.dart';

/// Taille maximale acceptée (miroir de la borne serveur, US-05-01). Garde-fou
/// d'UX : le serveur reste la source de vérité (413 sinon).
const _maxUploadBytes = 50 * 1024 * 1024;

/// Extensions audio autorisées (miroir du CHECK MIME côté serveur).
const _allowedExtensions = ['mp3', 'aac', 'ogg'];

/// Écran d'upload d'une piste audio dans la bibliothèque (US-05-01).
///
/// `ChangeNotifierProvider` local (pas de câblage global) : [repository] est
/// injectable pour les tests ; en production il est construit depuis [DioClient].
class UploadTrackScreen extends StatelessWidget {
  const UploadTrackScreen({super.key, this.repository});

  final TrackRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<UploadTrackController>(
      create: (ctx) => UploadTrackController(
        repository ??
            TrackRepositoryImpl(
              TrackRemoteDataSource(ctx.read<DioClient>().trackApi),
            ),
      ),
      child: const _UploadTrackBody(),
    );
  }
}

class _UploadTrackBody extends StatefulWidget {
  const _UploadTrackBody();

  @override
  State<_UploadTrackBody> createState() => _UploadTrackBodyState();
}

class _UploadTrackBodyState extends State<_UploadTrackBody> {
  final _titleController = TextEditingController();
  final _artistController = TextEditingController();

  PlatformFile? _file;

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData: false,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    if (picked.path == null) {
      showAuthErrorToast(context, 'Fichier illisible, réessaie');
      return;
    }
    if (picked.size > _maxUploadBytes) {
      showAuthErrorToast(context, 'Le fichier dépasse la taille maximale de 50 Mo');
      return;
    }

    setState(() {
      _file = picked;
      // Pré-remplit le titre avec le nom du fichier (sans extension) s'il est vide.
      if (_titleController.text.trim().isEmpty) {
        _titleController.text = _titleFromFilename(picked.name);
      }
    });
  }

  Future<void> _submit() async {
    final file = _file;
    final title = _titleController.text.trim();
    if (file == null || file.path == null) {
      showAuthErrorToast(context, 'Choisis d\'abord un fichier audio');
      return;
    }
    if (title.isEmpty) {
      showAuthErrorToast(context, 'Le titre est obligatoire');
      return;
    }

    final artist = _artistController.text.trim();
    final controller = context.read<UploadTrackController>();
    final ok = await controller.upload(
      filePath: file.path!,
      filename: file.name,
      title: title,
      artist: artist.isEmpty ? null : artist,
    );
    if (!mounted) return;
    if (ok) {
      showAuthSuccessToast(context, 'Piste ajoutée à ta bibliothèque');
      context.pop();
    } else {
      showAuthErrorToast(context, controller.error ?? 'Échec de l\'upload');
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<UploadTrackController>();
    final uploading = controller.isUploading;

    return Scaffold(
      appBar: AppBar(title: const Text('Uploader une piste')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _FilePickerCard(
              file: _file,
              enabled: !uploading,
              onPick: _pickFile,
            ),
            const SizedBox(height: 20),
            TextField(
              key: const Key('upload_title_field'),
              controller: _titleController,
              enabled: !uploading,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Titre *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('upload_artist_field'),
              controller: _artistController,
              enabled: !uploading,
              decoration: const InputDecoration(
                labelText: 'Artiste (optionnel)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            if (uploading) ...[
              LinearProgressIndicator(
                key: const Key('upload_progress'),
                value: controller.progress == 0 ? null : controller.progress,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('${(controller.progress * 100).round()} %'),
              ),
              const SizedBox(height: 24),
            ],
            FilledButton.icon(
              key: const Key('upload_submit_button'),
              onPressed: uploading ? null : _submit,
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(uploading ? 'Envoi en cours…' : 'Uploader'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Extrait un titre lisible d'un nom de fichier : retire l'extension, remplace
/// les séparateurs par des espaces.
String _titleFromFilename(String name) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return base.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
}

class _FilePickerCard extends StatelessWidget {
  const _FilePickerCard({
    required this.file,
    required this.enabled,
    required this.onPick,
  });

  final PlatformFile? file;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        key: const Key('upload_pick_button'),
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? onPick : null,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(
                file == null ? Icons.audio_file_outlined : Icons.check_circle,
                size: 40,
                color: file == null ? colors.onSurfaceVariant : colors.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file?.name ?? 'Choisir un fichier audio',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      file == null
                          ? 'MP3, AAC ou OGG · 50 Mo max'
                          : _formatSize(file!.size),
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    const mb = 1024 * 1024;
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} Mo';
    return '${(bytes / 1024).toStringAsFixed(0)} Ko';
  }
}
