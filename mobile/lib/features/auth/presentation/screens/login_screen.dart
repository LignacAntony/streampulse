import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/login_controller.dart';
import '../utils/login_validators.dart';
import '../widgets/auth_tabs.dart';
import '../widgets/auth_text_form_field.dart';
import '../widgets/auth_toasts.dart';
import '../widgets/oauth_buttons.dart';
import 'auth_screen.dart';
import 'login_form_object.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AuthScreen(initialTab: AuthTab.login);
}

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _formKey = GlobalKey<FormState>();
  final _form = LoginFormObject();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    try {
      await context.read<LoginController>().submit(
        email: _form.email.text.trim(),
        password: _form.password.text,
      );
      if (!mounted) return;
      showAuthSuccessToast(context, 'Connexion réussie.');
      context.go('/home');
    } catch (error) {
      if (!mounted) return;
      showAuthErrorToast(context, _humanReadable(error));
    }
  }

  String _humanReadable(Object error) {
    if (error is AuthException) return error.message;
    if (error is ValidationException) return error.message;
    if (error is NetworkException) return error.message;
    if (error is ServerException) return error.message;
    return 'Erreur inattendue';
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<LoginController>().isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 24,
      children: [
        Form(
          key: _formKey,
          child: _LoginFormFields(
            form: _form,
            isLoading: isLoading,
            onSubmit: _submit,
          ),
        ),
        const _DividerWithLabel(label: 'Ou'),
        OAuthButtons(enabled: !isLoading),
        _GuestButton(enabled: !isLoading),
      ],
    );
  }
}

class _LoginFormFields extends StatelessWidget {
  const _LoginFormFields({
    required this.form,
    required this.isLoading,
    required this.onSubmit,
  });

  final LoginFormObject form;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setFormState) {
        return Column(
          spacing: 16,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthTextFormField(
              config: _LoginField.email.config(form.email),
              enabled: !isLoading,
            ),
            AuthTextFormField(
              config: _LoginField.password.config(form.password),
              enabled: !isLoading,
              obscureText: form.obscurePassword,
              onFieldSubmitted: (_) => onSubmit(),
              suffixIcon: _PasswordToggle(
                buttonKey: const Key('login_toggle_password'),
                obscured: form.obscurePassword,
                onPressed: isLoading
                    ? null
                    : () => setFormState(
                          () => form.obscurePassword = !form.obscurePassword,
                        ),
              ),
            ),
            const _ForgotPasswordLink(),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(
                height: AppConstants.minTouchTarget,
              ),
              child: FilledButton(
                key: const Key('login_submit_button'),
                onPressed: isLoading ? null : onSubmit,
                child: isLoading
                    ? ConstrainedBox(
                        constraints: const BoxConstraints.tightFor(
                          width: 20,
                          height: 20,
                        ),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Se connecter'),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _LoginField {
  email,
  password;

  AuthTextFormFieldConfig config(TextEditingController controller) {
    return switch (this) {
      _LoginField.email => AuthTextFormFieldConfig(
          label: 'E-MAIL',
          fieldKey: const Key('login_email_field'),
          controller: controller,
          hintText: 'contact@exemple.com',
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: LoginValidators.email,
        ),
      _LoginField.password => AuthTextFormFieldConfig(
          label: 'MOT DE PASSE',
          fieldKey: const Key('login_password_field'),
          controller: controller,
          hintText: '••••••••',
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: LoginValidators.password,
        ),
    };
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
      tooltip: obscured
          ? 'Afficher le mot de passe'
          : 'Masquer le mot de passe',
      icon: Icon(
        obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
      ),
      onPressed: onPressed,
    );
  }
}

class _ForgotPasswordLink extends StatelessWidget {
  const _ForgotPasswordLink();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        key: const Key('login_forgot_password'),
        onPressed: () => context.push('/forgot-password'),
        child: Text(
          'Mot de passe oublié ?',
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

class _GuestButton extends StatelessWidget {
  const _GuestButton({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints.tightFor(
        height: AppConstants.minTouchTarget,
      ),
      child: OutlinedButton(
        key: const Key('login_guest_button'),
        onPressed: enabled ? () => context.go('/home') : null,
        child: const Text("Continuer en tant qu'invité"),
      ),
    );
  }
}

class _DividerWithLabel extends StatelessWidget {
  const _DividerWithLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: text.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
