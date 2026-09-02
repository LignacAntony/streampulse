import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../admin/presentation/screens/admin_global_bans_screen.dart';
import '../../../admin/presentation/screens/admin_streams_screen.dart';
import '../../../admin/presentation/screens/admin_users_screen.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../chat/data/repositories/chat_ban_repository.dart';
import '../../../chat/presentation/providers/chat_controller.dart';
import '../../../chat/presentation/screens/banned_users_screen.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../../broadcaster/presentation/providers/broadcaster_controller.dart';
import '../../../broadcaster/presentation/screens/admin_broadcaster_requests_screen.dart';
import '../../../playlists/presentation/providers/offline_playlist_controller.dart';
import '../../../playlists/presentation/providers/favorite_playlists_controller.dart';
import '../../../streams/presentation/providers/favorites_controller.dart';
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
    context.read<BroadcasterController>().reset();
    context.read<FavoritesController>().reset();
    context.read<FavoritePlaylistsController>().reset();
    context.read<ChatController>().disconnect();
    await context.read<OfflinePlaylistController>().clearCache();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _deleteAccount() async {
    final repo = context.read<AuthRepository>();
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || password.isEmpty) return;

    try {
      await repo.deleteAccount(password: password);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Compte supprimé avec succès');
      context.go('/login');
    } on AuthException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Mot de passe incorrect');
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, 'Échec de la suppression');
    }
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
          if (profile.role == 'broadcaster' || profile.role == 'admin') ...[
            const SizedBox(height: 28),
            const _BroadcasterCard(),
          ],
          if (profile.role == 'admin') ...[
            const SizedBox(height: 28),
            const _AdminCard(),
          ],
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
          const SizedBox(height: 12),
          ConstrainedBox(
            constraints: const BoxConstraints.tightFor(
              height: AppConstants.minTouchTarget,
            ),
            child: OutlinedButton.icon(
              key: const Key('profile_delete_account_button'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error),
              ),
              onPressed: _deleteAccount,
              icon: const Icon(Icons.delete_forever),
              label: const Text('Supprimer mon compte'),
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
            if (profile.role == 'user') ...[
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints.tightFor(
                  height: AppConstants.minTouchTarget,
                ),
                child: OutlinedButton(
                  key: const Key('profile_become_broadcaster'),
                  onPressed: () => context.push('/broadcaster-request'),
                  child: const Text('Demander le rôle Diffuseur'),
                ),
              ),
            ],
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

class _BroadcasterCard extends StatelessWidget {
  const _BroadcasterCard();

  void _openBannedUsers(BuildContext context) {
    final dio = context.read<DioClient>().dio;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BannedUsersScreen(
          repository: ChatBanRepositoryImpl(dio),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: ListTile(
        leading: Icon(Icons.block, color: colors.primary),
        title: const Text('Utilisateurs bannis du chat'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _openBannedUsers(context),
      ),
    );
  }
}

/// Tuiles visibles uniquement pour un profil `role == 'admin'` (cf.
/// `_buildBody`). Entrées de navigation séparées par un `Divider`, chacune
/// ouverte par `Navigator.push` (écrans hors go_router, pas de route nommée,
/// accessibles uniquement depuis cette carte) : gestion des comptes
/// utilisateurs (US-08-01), supervision des flux en direct (US-08-02),
/// demandes de rôle diffuseur et bans globaux du chat.
class _AdminCard extends StatelessWidget {
  const _AdminCard();

  void _openUsers(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminUsersScreen()),
    );
  }

  void _openStreams(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminStreamsScreen()),
    );
  }

  void _openGlobalBans(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AdminGlobalBansScreen()),
    );
  }

  void _openBroadcasterRequests(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AdminBroadcasterRequestsScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        children: [
          ListTile(
            key: const Key('profile_admin_tile'),
            leading: Icon(Icons.admin_panel_settings, color: colors.primary),
            title: const Text('Gestion des utilisateurs'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openUsers(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('profile_admin_streams_tile'),
            leading: Icon(Icons.podcasts, color: colors.primary),
            title: const Text('Supervision des flux'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openStreams(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('profile_admin_broadcaster_requests_tile'),
            leading: Icon(Icons.record_voice_over, color: colors.primary),
            title: const Text('Demandes de diffuseur'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openBroadcasterRequests(context),
          ),
          const Divider(height: 1),
          ListTile(
            key: const Key('profile_admin_chat_bans_tile'),
            leading: Icon(Icons.block, color: colors.primary),
            title: const Text('Bans globaux du chat'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openGlobalBans(context),
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

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _confirmed = false;
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text;
    if (password.isNotEmpty) {
      Navigator.of(context).pop(password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        'Supprimer mon compte',
        style: TextStyle(color: colors.error),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cette action est irréversible. Toutes vos données '
              '(profil, playlists, morceaux, historique) seront '
              'définitivement supprimées.',
            ),
            const SizedBox(height: 16),
            CheckboxListTile(
              key: const Key('delete_account_confirm_checkbox'),
              contentPadding: EdgeInsets.zero,
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              title: const Text('Je comprends que cette action est irréversible'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('delete_account_password_field'),
              controller: _controller,
              obscureText: _obscure,
              enabled: _confirmed,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                hintText: 'Confirmez votre mot de passe',
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: _confirmed ? (_) => _submit() : null,
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
          key: const Key('delete_account_submit_button'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
          ),
          onPressed: _confirmed ? _submit : null,
          child: const Text('Supprimer'),
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
