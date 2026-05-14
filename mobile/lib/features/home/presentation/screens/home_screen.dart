import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../auth/presentation/providers/login_controller.dart';
import '../../../auth/presentation/providers/register_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<String?> _userIdFuture;

  @override
  void initState() {
    super.initState();
    _userIdFuture = _loadUserId();
  }

  Future<String?> _loadUserId() async {
    final token = await ref.read(secureStorageProvider).getAccessToken();
    if (token == null) return null;
    return _decodeSub(token);
  }

  String? _decodeSub(String jwt) {
    final parts = jwt.split('.');
    if (parts.length != 3) return null;
    try {
      var payload = parts[1];
      payload += '=' * ((4 - payload.length % 4) % 4);
      final json = jsonDecode(utf8.decode(base64Url.decode(payload)));
      if (json is Map && json['sub'] is String) return json['sub'] as String;
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _logout() async {
    await ref.read(authRepositoryProvider).logout();
    ref.invalidate(loginControllerProvider);
    ref.invalidate(registerControllerProvider);
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accueil')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FutureBuilder<String?>(
              future: _userIdFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const CircularProgressIndicator();
                }
                final userId = snapshot.data;
                return userId == null
                    ? const _GuestView()
                    : _AuthenticatedView(
                        userId: userId,
                        onLogout: _logout,
                      );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticatedView extends StatelessWidget {
  const _AuthenticatedView({required this.userId, required this.onLogout});

  final String userId;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        Text(
          'Connecté — userID',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        SelectableText(
          userId,
          key: const Key('home_user_id'),
          textAlign: TextAlign.center,
          style: text.titleMedium,
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(
            height: AppConstants.minTouchTarget,
          ),
          child: OutlinedButton.icon(
            key: const Key('home_logout_button'),
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ),
      ],
    );
  }
}

class _GuestView extends StatelessWidget {
  const _GuestView();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        Text(
          'Mode invité',
          textAlign: TextAlign.center,
          style: text.titleMedium,
        ),
        Text(
          'Connecte-toi pour accéder à toutes les fonctionnalités.',
          textAlign: TextAlign.center,
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(
            height: AppConstants.minTouchTarget,
          ),
          child: FilledButton.icon(
            key: const Key('home_login_button'),
            onPressed: () => context.go('/login'),
            icon: const Icon(Icons.login),
            label: const Text('Se connecter'),
          ),
        ),
      ],
    );
  }
}
