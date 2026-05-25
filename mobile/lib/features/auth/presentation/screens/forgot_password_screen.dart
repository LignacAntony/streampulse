import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/forgot_password_controller.dart';
import '../utils/login_validators.dart';
import '../widgets/auth_text_form_field.dart';
import '../widgets/auth_toasts.dart';
import '../widgets/branded_header.dart';

class ForgotPasswordScreen extends StatelessWidget {
  const ForgotPasswordScreen({super.key});

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
              child: const _ForgotPasswordView(),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForgotPasswordView extends ConsumerStatefulWidget {
  const _ForgotPasswordView();

  @override
  ConsumerState<_ForgotPasswordView> createState() =>
      _ForgotPasswordViewState();
}

class _ForgotPasswordViewState extends ConsumerState<_ForgotPasswordView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    await ref
        .read(forgotPasswordControllerProvider.notifier)
        .submit(email: _email.text.trim());
  }

  void _onStateChanged(
    AsyncValue<void>? previous,
    AsyncValue<void> next,
  ) {
    next.when(
      data: (_) {
        showAuthInfoToast(
          context,
          'Si cet email est enregistré, un lien vous a été envoyé.',
        );
        context.pop();
      },
      loading: () {},
      error: (error, _) {
        showAuthErrorToast(context, _humanReadable(error));
      },
    );
  }

  String _humanReadable(Object error) {
    if (error is ValidationException) return error.message;
    if (error is NetworkException) return error.message;
    if (error is ServerException) return error.message;
    return 'Erreur inattendue';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<void>>(
      forgotPasswordControllerProvider,
      _onStateChanged,
    );

    final state = ref.watch(forgotPasswordControllerProvider);
    final isLoading = state.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 32,
      children: [
        const BrandedHeader(),
        _ForgotPasswordHeader(),
        Form(
          key: _formKey,
          child: _ForgotPasswordFormFields(
            email: _email,
            isLoading: isLoading,
            onSubmit: _submit,
          ),
        ),
        _BackToLoginLink(enabled: !isLoading),
      ],
    );
  }
}

class _ForgotPasswordHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Text(
          'Mot de passe oublié ?',
          style: text.titleLarge?.copyWith(
            color: colors.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          'Saisissez votre email pour recevoir un lien de réinitialisation.',
          style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ForgotPasswordFormFields extends StatelessWidget {
  const _ForgotPasswordFormFields({
    required this.email,
    required this.isLoading,
    required this.onSubmit,
  });

  final TextEditingController email;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        AuthTextFormField(
          config: AuthTextFormFieldConfig(
            label: 'E-MAIL',
            fieldKey: const Key('forgot_password_email_field'),
            controller: email,
            hintText: 'contact@exemple.com',
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.done,
            autocorrect: false,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: LoginValidators.email,
          ),
          enabled: !isLoading,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints.tightFor(
            height: AppConstants.minTouchTarget,
          ),
          child: FilledButton(
            key: const Key('forgot_password_submit_button'),
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? ConstrainedBox(
                    constraints: const BoxConstraints.tightFor(
                      width: 20,
                      height: 20,
                    ),
                    child: const CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Envoyer le lien'),
          ),
        ),
      ],
    );
  }
}

class _BackToLoginLink extends StatelessWidget {
  const _BackToLoginLink({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: TextButton(
        key: const Key('forgot_password_back_to_login'),
        onPressed: enabled ? () => context.pop() : null,
        child: Text(
          'Retour à la connexion',
          style: text.labelLarge?.copyWith(
            color: colors.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
