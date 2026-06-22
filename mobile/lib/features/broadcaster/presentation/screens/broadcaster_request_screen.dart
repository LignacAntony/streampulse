import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../auth/presentation/widgets/auth_toasts.dart';
import '../../domain/entities/broadcaster_request.dart';
import '../providers/broadcaster_controller.dart';

class BroadcasterRequestScreen extends StatefulWidget {
  const BroadcasterRequestScreen({super.key});

  @override
  State<BroadcasterRequestScreen> createState() =>
      _BroadcasterRequestScreenState();
}

class _BroadcasterRequestScreenState extends State<BroadcasterRequestScreen> {
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BroadcasterController>().load();
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = context.read<BroadcasterController>();
    try {
      await controller.submit(_messageController.text.trim());
      if (!mounted) return;
      _messageController.clear();
      showAuthSuccessToast(context, 'Demande envoyée');
    } on ConflictException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on ValidationException catch (e) {
      if (!mounted) return;
      showAuthErrorToast(context, e.message);
    } on NetworkException {
      if (!mounted) return;
      showAuthErrorToast(context, 'Pas de connexion réseau');
    } catch (_) {
      if (!mounted) return;
      showAuthErrorToast(context, "Échec de l'envoi de la demande");
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<BroadcasterController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Devenir diffuseur')),
      body: SafeArea(child: _buildBody(controller)),
    );
  }

  Widget _buildBody(BroadcasterController controller) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadFailed) {
      return _ErrorView(onRetry: () => controller.load());
    }

    final request = controller.request;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _IntroHeader(),
          const SizedBox(height: 24),
          if (request != null) ...[
            _StatusCard(request: request),
            const SizedBox(height: 24),
          ],
          if (!controller.hasPendingRequest)
            _RequestForm(
              controller: _messageController,
              isSubmitting: controller.isSubmitting,
              isResubmit: request != null,
              onSubmit: _submit,
            ),
        ],
      ),
    );
  }
}

class _IntroHeader extends StatelessWidget {
  const _IntroHeader();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Diffuse tes propres streams',
          style: text.headlineSmall?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Le rôle diffuseur te permet de lancer des streams audio en direct. '
          'Explique en quelques mots ton projet : un administrateur examinera '
          'ta demande.',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.request});

  final BroadcasterRequest request;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final (icon, color, label, detail) = _statusVisuals(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  if (request.isRejected && request.reviewNote.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Motif : ${request.reviewNote}',
                      style: text.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String, String) _statusVisuals(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    switch (request.status) {
      case BroadcasterRequestStatus.approved:
        return (
          Icons.verified,
          colors.primary,
          'Demande acceptée',
          'Félicitations, tu es désormais diffuseur ! Reconnecte-toi si le '
              'rôle n\'apparaît pas encore.',
        );
      case BroadcasterRequestStatus.rejected:
        return (
          Icons.cancel_outlined,
          colors.error,
          'Demande refusée',
          'Ta demande n\'a pas été retenue. Tu peux en soumettre une nouvelle.',
        );
      case BroadcasterRequestStatus.pending:
        return (
          Icons.hourglass_top,
          colors.secondary,
          'Demande en cours d\'examen',
          'Un administrateur étudie ta demande. Tu seras notifié de la décision.',
        );
    }
  }
}

class _RequestForm extends StatelessWidget {
  const _RequestForm({
    required this.controller,
    required this.isSubmitting,
    required this.isResubmit,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isSubmitting;
  final bool isResubmit;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Ta motivation (optionnel)', style: text.labelLarge),
        const SizedBox(height: 8),
        TextField(
          key: const Key('broadcaster_message_field'),
          controller: controller,
          maxLines: 4,
          maxLength: 500,
          enabled: !isSubmitting,
          decoration: const InputDecoration(
            hintText: 'Parle-nous de ce que tu veux diffuser…',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(
            height: AppConstants.minTouchTarget,
          ),
          child: FilledButton(
            key: const Key('broadcaster_submit_button'),
            onPressed: isSubmitting ? null : onSubmit,
            child: isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isResubmit ? 'Renvoyer une demande' : 'Envoyer ma demande'),
          ),
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
          const Text('Impossible de charger ta demande.'),
          const SizedBox(height: 16),
          OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
        ],
      ),
    );
  }
}
