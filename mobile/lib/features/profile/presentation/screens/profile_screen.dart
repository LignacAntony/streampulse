import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../domain/entities/user_profile.dart';
import '../providers/profile_controller.dart';
import '../widgets/profile_avatar.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProfileController>().load();
    });
  }

  Future<void> _runSave(Future<void> Function() action) async {
    try {
      await action();
      if (!mounted) return;
      showAuthSuccessToast(context, 'Profil mis à jour');
    } on ValidationException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la mise à jour');
    }
  }

  Future<void> _editPseudo(UserProfile profile) async {
    final newPseudo = await showDialog<String>(
      context: context,
      builder: (_) => _EditPseudoDialog(initial: profile.pseudo),
    );
    if (newPseudo == null || newPseudo == profile.pseudo) return;
    await _runSave(
      () => context.read<ProfileController>().updatePseudo(newPseudo),
    );
  }

  Future<void> _logout() async {
    await context.read<AuthRepository>().logout();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final controller = context.watch<ProfileController>();
    final profile = controller.profile;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'StreamPulse',
          style: text.titleLarge?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: _buildBody(context, controller, profile),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ProfileController controller,
    UserProfile? profile,
  ) {
    if (profile == null) {
      if (controller.loadFailed) {
        return _ErrorView(
          onRetry: () => context.read<ProfileController>().load(),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Profil',
            style: text.headlineSmall?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          _ProfileCard(profile: profile, onEditPseudo: () => _editPseudo(profile)),
          const SizedBox(height: 28),
          Text(
            "PARAMÈTRES DE L'APP",
            style: text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(profile: profile, runSave: _runSave),
          const SizedBox(height: 32),
          ConstrainedBox(
            constraints: const BoxConstraints.tightFor(
              height: AppConstants.minTouchTarget,
            ),
            child: ElevatedButton.icon(
              key: const Key('profile_logout_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.surface,
                foregroundColor: colors.onSurface,
              ),
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('Se déconnecter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile, required this.onEditPseudo});

  final UserProfile profile;
  final VoidCallback onEditPseudo;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileAvatar(pseudo: profile.pseudo, avatarUrl: profile.avatarUrl),
            const SizedBox(height: 20),
            Row(
              children: [
                Flexible(
                  child: Text(
                    profile.pseudo,
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  key: const Key('profile_edit_pseudo'),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit, size: 18, color: colors.primary),
                  onPressed: onEditPseudo,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              profile.email,
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            _RoleBadge(role: profile.role),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                height: AppConstants.minTouchTarget,
              ),
              child: OutlinedButton(
                onPressed: () => showAuthInfoToast(
                  context,
                  'Demande de rôle Diffuseur — bientôt disponible',
                ),
                child: const Text('Demander le rôle Diffuseur'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _roleLabel(role).toUpperCase(),
        style: TextStyle(
          color: colors.secondary,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.profile, required this.runSave});

  final UserProfile profile;
  final Future<void> Function(Future<void> Function()) runSave;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ProfileController>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            _SettingRow(
              icon: Icons.dark_mode_outlined,
              label: 'Thème sombre',
              trailing: Switch(
                key: const Key('profile_theme_switch'),
                value: profile.theme == 'dark',
                onChanged: (v) =>
                    runSave(() => controller.updateTheme(v ? 'dark' : 'light')),
              ),
            ),
            const Divider(height: 1),
            _AudioQualityRow(
              selected: profile.audioQuality,
              onChanged: (q) => runSave(() => controller.updateAudioQuality(q)),
            ),
            const Divider(height: 1),
            _SettingRow(
              icon: Icons.notifications_outlined,
              label: 'Notifications push',
              trailing: Switch(
                key: const Key('profile_notifications_switch'),
                value: profile.notificationsEnabled,
                onChanged: (v) =>
                    runSave(() => controller.updateNotifications(v)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AudioQualityRow extends StatelessWidget {
  const _AudioQualityRow({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, size: 22, color: colors.onSurfaceVariant),
              const SizedBox(width: 14),
              Text('Qualité audio', style: text.bodyLarge),
            ],
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            key: const Key('profile_audio_segment'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 'low', label: Text('Basse')),
              ButtonSegment(value: 'normal', label: Text('Standard')),
              ButtonSegment(value: 'high', label: Text('Ultra HD')),
            ],
            selected: {selected},
            onSelectionChanged: (s) => onChanged(s.first),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colors.onSurfaceVariant),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: text.bodyLarge)),
          trailing,
        ],
      ),
    );
  }
}

class _EditPseudoDialog extends StatefulWidget {
  const _EditPseudoDialog({required this.initial});

  final String initial;

  @override
  State<_EditPseudoDialog> createState() => _EditPseudoDialogState();
}

class _EditPseudoDialogState extends State<_EditPseudoDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);
  final _formKey = GlobalKey<FormState>();

  static final _pseudoRe = RegExp(r'^[a-zA-Z0-9_ ]+$');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final v = (value ?? '').trim();
    if (v.length < 3 || v.length > 30) {
      return 'Entre 3 et 30 caractères';
    }
    if (!_pseudoRe.hasMatch(v)) {
      return 'Lettres, chiffres, _ et espaces uniquement';
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le pseudo'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('profile_pseudo_field'),
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Ton pseudo'),
          validator: _validate,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Impossible de charger le profil.'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Administrateur';
    case 'broadcaster':
      return 'Diffuseur';
    case 'user':
      return 'Utilisateur standard';
    default:
      return 'Invité';
  }
}
