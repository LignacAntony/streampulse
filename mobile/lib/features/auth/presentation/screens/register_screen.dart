import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/register_controller.dart';
import '../utils/register_validators.dart';
import '../widgets/auth_tabs.dart';
import '../widgets/auth_text_form_field.dart';
import '../widgets/auth_toasts.dart';
import '../widgets/oauth_buttons.dart';
import '../widgets/password_strength_indicator.dart';
import '../widgets/terms_checkbox.dart';
import 'auth_screen.dart';
import 'register_form_object.dart';

class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AuthScreen(initialTab: AuthTab.register);
}

class RegisterView extends StatefulWidget {
  const RegisterView({super.key, this.onRegistered});

  final VoidCallback? onRegistered;

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _formKey = GlobalKey<FormState>();
  final _form = RegisterFormObject();

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || !_form.acceptedTerms) return;

    try {
      await context.read<RegisterController>().submit(
        email: _form.email.text.trim(),
        username: _form.username.text.trim(),
        password: _form.password.text,
      );
      if (!mounted) return;
      showAuthSuccessToast(context, 'Compte créé. Tu peux te connecter.');
      final cb = widget.onRegistered;
      if (cb != null) {
        cb();
      } else {
        context.go('/login');
      }
    } catch (error) {
      if (!mounted) return;
      showAuthErrorToast(context, _humanReadable(error));
    }
  }

  String _humanReadable(Object error) {
    if (error is ValidationException) return error.message;
    if (error is DuplicateAccountException) return error.message;
    if (error is NetworkException) return error.message;
    if (error is ServerException) return error.message;
    return 'Erreur inattendue';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.read<RegisterController>();

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final isLoading = controller.isLoading;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 24,
          children: [
            Form(
              key: _formKey,
              child: _RegisterFormFields(
                form: _form,
                isLoading: isLoading,
                onSubmit: _submit,
              ),
            ),
            _AlreadyAccountLink(
              onTap: isLoading
                  ? null
                  : () {
                      final cb = widget.onRegistered;
                      if (cb != null) {
                        cb();
                      } else {
                        context.go('/login');
                      }
                    },
            ),
            const _DividerWithLabel(label: "Ou s'inscrire avec"),
            OAuthButtons(enabled: !isLoading),
          ],
        );
      },
    );
  }
}

class _RegisterFormFields extends StatelessWidget {
  const _RegisterFormFields({required this.form, required this.isLoading, required this.onSubmit});

  final RegisterFormObject form;
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
              config: _RegisterField.username.config(form.username),
              enabled: !isLoading,
            ),
            AuthTextFormField(config: _RegisterField.email.config(form.email), enabled: !isLoading),
            AuthTextFormField(
              config: _RegisterField.password.config(form.password),
              enabled: !isLoading,
              obscureText: form.obscurePassword,
              suffixIcon: _PasswordToggle(
                buttonKey: const Key('register_toggle_password'),
                obscured: form.obscurePassword,
                onPressed: isLoading
                    ? null
                    : () => setFormState(() => form.obscurePassword = !form.obscurePassword),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: form.password,
              builder: (context, value, _) => PasswordStrengthIndicator(password: value.text),
            ),
            AuthTextFormField(
              config: _RegisterField.confirmPassword.config(form.confirm),
              enabled: !isLoading,
              obscureText: form.obscureConfirmPassword,
              onFieldSubmitted: (_) => onSubmit(),
              suffixIcon: _PasswordToggle(
                buttonKey: const Key('register_toggle_confirm_password'),
                obscured: form.obscureConfirmPassword,
                onPressed: isLoading
                    ? null
                    : () => setFormState(
                        () => form.obscureConfirmPassword = !form.obscureConfirmPassword,
                      ),
              ),
              validator: form.validateConfirm,
            ),
            const SizedBox(height: 20),
            TermsCheckbox(
              value: form.acceptedTerms,
              enabled: !isLoading,
              onChanged: (v) => setFormState(() => form.acceptedTerms = v),
            ),
            const SizedBox(height: 24),
            ConstrainedBox(
              constraints: const BoxConstraints.tightFor(height: AppConstants.minTouchTarget),
              child: FilledButton(
                key: const Key('register_submit_button'),
                onPressed: (!form.acceptedTerms || isLoading) ? null : onSubmit,
                child: isLoading
                    ? ConstrainedBox(
                        constraints: const BoxConstraints.tightFor(width: 20, height: 20),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Créer mon compte'),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _RegisterField {
  username,
  email,
  password,
  confirmPassword;

  AuthTextFormFieldConfig config(TextEditingController controller) {
    return switch (this) {
      _RegisterField.username => AuthTextFormFieldConfig(
        label: "NOM D'UTILISATEUR",
        fieldKey: const Key('register_username_field'),
        controller: controller,
        hintText: 'votre_pseudo',
        keyboardType: TextInputType.text,
        autofillHints: const [AutofillHints.newUsername],
        textInputAction: TextInputAction.next,
        autocorrect: false,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: RegisterValidators.username,
      ),
      _RegisterField.email => AuthTextFormFieldConfig(
        label: 'E-MAIL',
        fieldKey: const Key('register_email_field'),
        controller: controller,
        hintText: 'contact@exemple.com',
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.next,
        autocorrect: false,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: RegisterValidators.email,
      ),
      _RegisterField.password => AuthTextFormFieldConfig(
        label: 'MOT DE PASSE',
        fieldKey: const Key('register_password_field'),
        controller: controller,
        hintText: '••••••••',
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
        autocorrect: false,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: RegisterValidators.password,
      ),
      _RegisterField.confirmPassword => AuthTextFormFieldConfig(
        label: 'CONFIRMER LE MOT DE PASSE',
        fieldKey: const Key('register_confirm_password_field'),
        controller: controller,
        hintText: '••••••••',
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        autocorrect: false,
        autovalidateMode: AutovalidateMode.onUserInteraction,
      ),
    };
  }
}

class _PasswordToggle extends StatelessWidget {
  const _PasswordToggle({required this.buttonKey, required this.obscured, required this.onPressed});

  final Key buttonKey;
  final bool obscured;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: obscured ? 'Afficher le mot de passe' : 'Masquer le mot de passe',
      icon: Icon(obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: onPressed,
    );
  }
}

class _AlreadyAccountLink extends StatelessWidget {
  const _AlreadyAccountLink({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Text.rich(
          TextSpan(
            style: text.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
            children: [
              const TextSpan(text: 'Vous avez déjà un compte ? '),
              TextSpan(
                text: 'Se connecter',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
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
            style: text.bodySmall?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 0.8),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}
