import 'package:flutter/material.dart';

import '../../data/repositories/chat_ban_repository.dart';
import '../../domain/entities/banned_user.dart';

class BannedUsersScreen extends StatefulWidget {
  const BannedUsersScreen({super.key, required this.repository});

  final ChatBanRepository repository;

  @override
  State<BannedUsersScreen> createState() => _BannedUsersScreenState();
}

class _BannedUsersScreenState extends State<BannedUsersScreen> {
  List<BannedUser> _bans = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final bans = await widget.repository.listBans();
      if (!mounted) return;
      setState(() {
        _bans = bans;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Impossible de charger la liste';
        _isLoading = false;
      });
    }
  }

  Future<void> _unban(BannedUser user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Débannir'),
        content: Text('Débannir ${user.username} de vos chats ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Débannir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await widget.repository.unban(user.userId);
      if (!mounted) return;
      setState(() => _bans.removeWhere((b) => b.userId == user.userId));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec du débannissement')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Utilisateurs bannis')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: colors.error)),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: _load,
                        child: const Text('Réessayer'),
                      ),
                    ],
                  ),
                )
              : _bans.isEmpty
                  ? Center(
                      child: Text(
                        'Aucun utilisateur banni',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _bans.length,
                      itemBuilder: (context, index) {
                        final ban = _bans[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colors.surfaceContainerHighest,
                            child: Text(
                              ban.username[0].toUpperCase(),
                              style: TextStyle(color: colors.onSurface),
                            ),
                          ),
                          title: Text(ban.username),
                          subtitle: ban.reason != null
                              ? Text(ban.reason!)
                              : null,
                          trailing: TextButton(
                            onPressed: () => _unban(ban),
                            child: const Text('Débannir'),
                          ),
                        );
                      },
                    ),
    );
  }
}
