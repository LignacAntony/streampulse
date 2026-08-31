import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../data/datasources/broadcaster_remote_data_source.dart';
import '../../data/repositories/admin_broadcaster_repository_impl.dart';
import '../../domain/entities/admin_broadcaster_request.dart';
import '../../domain/entities/broadcaster_request.dart';
import '../../domain/repositories/admin_broadcaster_repository.dart';
import '../providers/admin_broadcaster_requests_provider.dart';

/// Écran d'administration : demandes de rôle diffuseur (approuver / refuser).
/// Accessible uniquement depuis la carte « Administration » de `ProfileScreen`
/// (rôle admin). L'autorisation réelle est côté serveur (`RequireRole("admin")`
/// sur `/api/admin/broadcaster-requests`) — cet écran ne fait que la refléter.
///
/// `ChangeNotifierProvider` local (pas de câblage global : écran rarement
/// visité, réservé aux admins). [repository] est injectable pour les tests ;
/// en production il est construit depuis [DioClient].
class AdminBroadcasterRequestsScreen extends StatelessWidget {
  const AdminBroadcasterRequestsScreen({super.key, this.repository});

  final AdminBroadcasterRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminBroadcasterRequestsProvider>(
      create: (ctx) => AdminBroadcasterRequestsProvider(
        repository ??
            AdminBroadcasterRepositoryImpl(
              BroadcasterRemoteDataSource(ctx.read<DioClient>().broadcasterApi),
            ),
      ),
      child: const _AdminBroadcasterRequestsBody(),
    );
  }
}

class _AdminBroadcasterRequestsBody extends StatefulWidget {
  const _AdminBroadcasterRequestsBody();

  @override
  State<_AdminBroadcasterRequestsBody> createState() =>
      _AdminBroadcasterRequestsBodyState();
}

class _AdminBroadcasterRequestsBodyState
    extends State<_AdminBroadcasterRequestsBody> {
  static const _filters = <({String? value, String label})>[
    (value: 'pending', label: 'En attente'),
    (value: 'approved', label: 'Approuvées'),
    (value: 'rejected', label: 'Refusées'),
    (value: null, label: 'Toutes'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminBroadcasterRequestsProvider>().load();
    });
  }

  Future<void> _onApprove(AdminBroadcasterRequest request) async {
    final controller = context.read<AdminBroadcasterRequestsProvider>();
    final note = await _promptNote(
      title: 'Approuver la demande',
      message: 'Promouvoir « ${request.username} » au rôle diffuseur ?',
      submitLabel: 'Approuver',
    );
    if (note == null || !mounted) return;
    try {
      await controller.approve(request, note: note.isEmpty ? null : note);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Demande approuvée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  Future<void> _onReject(AdminBroadcasterRequest request) async {
    final controller = context.read<AdminBroadcasterRequestsProvider>();
    final note = await _promptNote(
      title: 'Refuser la demande',
      message: 'Refuser la demande de « ${request.username} » ?',
      submitLabel: 'Refuser',
      destructive: true,
    );
    if (note == null || !mounted) return;
    try {
      await controller.reject(request, note: note.isEmpty ? null : note);
      if (!mounted) return;
      showAuthSuccessToast(context, 'Demande refusée');
    } catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, _mutationMessage(e));
    }
  }

  Future<String?> _promptNote({
    required String title,
    required String message,
    required String submitLabel,
    bool destructive = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => _ReviewNoteDialog(
        title: title,
        message: message,
        submitLabel: submitLabel,
        destructive: destructive,
      ),
    );
  }

  String _mutationMessage(Object error) {
    if (error is ConflictException) return error.message;
    if (error is NetworkException) return 'Pas de connexion réseau';
    return 'Une erreur est survenue';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AdminBroadcasterRequestsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Demandes de diffuseur')),
      body: SafeArea(
        child: Column(
          children: [
            _FilterBar(
              filters: _filters,
              selected: controller.statusFilter,
              onSelected: (v) =>
                  context.read<AdminBroadcasterRequestsProvider>()
                      .setStatusFilter(v),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () =>
                    context.read<AdminBroadcasterRequestsProvider>().load(),
                child: _buildBody(context, controller),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AdminBroadcasterRequestsProvider controller,
  ) {
    if (controller.loading && controller.requests.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.error != null && controller.requests.isEmpty) {
      return _MessageView(
        icon: controller.isNetworkError
            ? Icons.wifi_off_outlined
            : Icons.error_outline,
        message: controller.error!,
        actionLabel: 'Réessayer',
        onAction: () =>
            context.read<AdminBroadcasterRequestsProvider>().load(),
      );
    }

    if (controller.requests.isEmpty) {
      return const _MessageView(
        icon: Icons.inbox_outlined,
        message: 'Aucune demande',
      );
    }

    return ListView.separated(
      key: const Key('broadcaster_requests_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: controller.requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final request = controller.requests[index];
        return _RequestCard(
          request: request,
          onApprove: () => _onApprove(request),
          onReject: () => _onReject(request),
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.filters,
    required this.selected,
    required this.onSelected,
  });

  final List<({String? value, String label})> filters;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final filter in filters) ...[
            ChoiceChip(
              key: Key('broadcaster_filter_${filter.value ?? 'all'}'),
              label: Text(filter.label),
              selected: selected == filter.value,
              onSelected: (_) => onSelected(filter.value),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
  });

  final AdminBroadcasterRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return Card(
      key: Key('broadcaster_request_${request.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.username,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        request.email,
                        style: text.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _StatusBadge(status: request.status),
              ],
            ),
            if (request.message.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(request.message, style: text.bodyMedium),
            ],
            if (!request.isPending && request.reviewNote.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Note : ${request.reviewNote}',
                style: text.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            // Actions réservées aux demandes encore en attente : approuver ou
            // refuser une demande déjà traitée renverrait un 409 côté serveur.
            if (request.isPending) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: Key('broadcaster_reject_${request.id}'),
                    onPressed: onReject,
                    style: TextButton.styleFrom(foregroundColor: colors.error),
                    child: const Text('Refuser'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: Key('broadcaster_approve_${request.id}'),
                    onPressed: onApprove,
                    child: const Text('Approuver'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BroadcasterRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, color) = switch (status) {
      BroadcasterRequestStatus.pending => ('En attente', colors.tertiary),
      BroadcasterRequestStatus.approved => ('Approuvée', colors.primary),
      BroadcasterRequestStatus.rejected => ('Refusée', colors.error),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Dialogue de revue : confirme l'action et permet de joindre une note
/// facultative (transmise en `review_note`). Renvoie la note (`''` si vide) à
/// la validation, `null` à l'annulation.
class _ReviewNoteDialog extends StatefulWidget {
  const _ReviewNoteDialog({
    required this.title,
    required this.message,
    required this.submitLabel,
    required this.destructive,
  });

  final String title;
  final String message;
  final String submitLabel;
  final bool destructive;

  @override
  State<_ReviewNoteDialog> createState() => _ReviewNoteDialogState();
}

class _ReviewNoteDialogState extends State<_ReviewNoteDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            key: const Key('broadcaster_review_note_field'),
            controller: _controller,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Note (facultatif)',
              hintText: 'Visible dans l\'historique de la demande',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          key: const Key('broadcaster_review_submit'),
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.15),
        Icon(icon, size: 64, color: colors.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: text.titleMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          Center(
            child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    );
  }
}
