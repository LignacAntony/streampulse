import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/reset_password_controller.dart';
import '../utils/reset_password_validators.dart';
import '../widgets/auth_text_form_field.dart';
import '../widgets/auth_toasts.dart';
import '../widgets/branded_header.dart';

class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: token.isEmpty
                  ? const _InvalidTokenView()
                  : _ResetPasswordView(token: token),
            ),
          ),
        ),
      ),
    );
  }
}

class _InvalidTokenView extends StatelessWidget {
  const _InvalidTokenView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 32,
      children: [
        const BrandedHeader(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              'Lien invalide',
              style: text.titleLarge?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Ce lien de réinitialisation est invalide ou a expiré. '
              'Veuillez recommencer la procédure.',
              style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(
            height: AppConstants.minTouchTarget,
          ),
          child: FilledButton(
            key: const Key('reset_password_invalid_back_button'),
            onPressed: () => context.go('/login'),
            child: const Text('Retour à la connexion'),
          ),
        ),
      ],
    );
  }
}

class _ResetPasswordFormObject {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool obscurePassword = true;
  bool obscureConfirm = true;

  void dispose() {
    password.dispose();
    confirm.dispose();
  }
}

class _ResetPasswordView extends StatefulWidget {
  const _ResetPasswordView({required this.token});

  final String token;

  @override
  State<_ResetPasswordView> createState() => _ResetPasswordViewState();
}

class _ResetPasswordViewState extends State<_ResetPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _form = _ResetPasswordFormObject();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    try {
      await context.read<ResetPasswordController>().submit(
        token: widget.token,
        newPassword: _form.password.text,
      );
      if (!mounted) return;
      showAuthSuccessToast(
        context,
        'Mot de passe mis à jour. Connectez-vous avec votre nouveau mot de passe.',
      );
      context.go('/login');
    } catch (error) {
      if (!mounted) return;
      showAuthErrorToast(context, _humanReadable(error));
    }
  }

  String _humanReadable(Object error) {
    if (error is ValidationException) return error.message;
    if (error is PasswordResetException) return error.message;
    if (error is NetworkException) return error.message;
    if (error is ServerException) return error.message;
    return 'Erreur inattendue';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<ResetPasswordController>();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLoading = controller.isLoading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 32,
          children: [
            const BrandedHeader(),
            _ResetPasswordHeader(),
            Form(
              key: _formKey,
              child: _ResetPasswordFormFields(
                form: _form,
                isLoading: isLoading,
                onSubmit: _submit,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ResetPasswordHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          'Nouveau mot de passe',
          style: text.titleLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Choisissez un nouveau mot de passe pour votre compte StreamPulse.',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ResetPasswordFormFields extends StatelessWidget {
  const _ResetPasswordFormFields({
    required this.form,
    required this.isLoading,
    required this.onSubmit,
  });

  final _ResetPasswordFormObject form;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setFormState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            AuthTextFormField(
              config: AuthTextFormFieldConfig(
                label: 'NOUVEAU MOT DE PASSE',
                fieldKey: const Key('reset_password_field'),
                controller: form.password,
                hintText: '••••••••',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.next,
                autocorrect: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: ResetPasswordValidators.password,
              ),
              enabled: !isLoading,
              obscureText: form.obscurePassword,
              suffixIcon: _PasswordToggle(
                buttonKey: const Key('reset_password_toggle'),
                obscured: form.obscurePassword,
                onPressed: isLoading
                    ? null
                    : () => setFormState(
                          () =>
                              form.obscurePassword = !form.obscurePassword,
                        ),
              ),
            ),
            AuthTextFormField(
              config: AuthTextFormFieldConfig(
                label: 'CONFIRMER LE MOT DE PASSE',
                fieldKey: const Key('reset_confirm_field'),
                controller: form.confirm,
                hintText: '••••••••',
                autofillHints: const [AutofillHints.newPassword],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                validator: (v) => ResetPasswordValidators.confirmPassword(
                  v,
                  form.password.text,
                ),
              ),
              enabled: !isLoading,
              obscureText: form.obscureConfirm,
              onFieldSubmitted: (_) => onSubmit(),
              suffixIcon: _PasswordToggle(
                buttonKey: const Key('reset_confirm_toggle'),
                obscured: form.obscureConfirm,
                onPressed: isLoading
                    ? null
                    : () => setFormState(
                          () => form.obscureConfirm = !form.obscureConfirm,
                        ),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                height: AppConstants.minTouchTarget,
              ),
              child: FilledButton(
                key: const Key('reset_password_submit_button'),
                onPressed: isLoading ? null : onSubmit,
                child: isLoading
                    ? ConstrainedBox(
                        constraints: const BoxConstraints.tightFor(
                          width: 20,
                          height: 20,
                        ),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Réinitialiser le mot de passe'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({
    required this.buttonKey,
    required this.obscured,
    required this.onPressed,
  });

  final Key buttonKey;
  final bool obscured;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: obscured ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      onPressed: onPressed,
    );
  }
}
