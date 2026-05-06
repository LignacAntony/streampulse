import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/register_controller.dart';
import '../utils/register_validators.dart';
import '../widgets/auth_tabs.dart';
import '../widgets/branded_header.dart';
import '../widgets/oauth_buttons.dart';
import '../widgets/password_strength_indicator.dart';
import '../widgets/terms_checkbox.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate() || !_acceptedTerms) return;

    await ref.read(registerControllerProvider.notifier).submit(
          email: _emailController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
        );
  }

  void _onStateChanged(
    AsyncValue<dynamic>? previous,
    AsyncValue<dynamic> next,
  ) {
    next.when(
      data: (user) {
        if (user == null) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Compte créé. Tu peux te connecter.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        context.go('/login');
      },
      loading: () {},
      error: (error, _) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(_humanReadable(error)),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
      },
    );
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
    ref.listen<AsyncValue<dynamic>>(
      registerControllerProvider,
      _onStateChanged,
    );

    final state = ref.watch(registerControllerProvider);
    final isLoading = state.isLoading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandedHeader(),
                  const SizedBox(height: 32),
                  const AuthTabs(active: AuthTab.register),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _LabeledField(
                          label: "NOM D'UTILISATEUR",
                          child: TextFormField(
                            key: const Key('register_username_field'),
                            controller: _usernameController,
                            enabled: !isLoading,
                            keyboardType: TextInputType.text,
                            autofillHints: const [AutofillHints.newUsername],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            decoration: const InputDecoration(
                              hintText: 'votre_pseudo',
                            ),
                            validator: RegisterValidators.username,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LabeledField(
                          label: 'E-MAIL',
                          child: TextFormField(
                            key: const Key('register_email_field'),
                            controller: _emailController,
                            enabled: !isLoading,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            textInputAction: TextInputAction.next,
                            autocorrect: false,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            decoration: const InputDecoration(
                              hintText: 'contact@exemple.com',
                            ),
                            validator: RegisterValidators.email,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LabeledField(
                          label: 'MOT DE PASSE',
                          child: TextFormField(
                            key: const Key('register_password_field'),
                            controller: _passwordController,
                            enabled: !isLoading,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.next,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: _PasswordToggle(
                                buttonKey:
                                    const Key('register_toggle_password'),
                                obscured: _obscurePassword,
                                onPressed: isLoading
                                    ? null
                                    : () => setState(() => _obscurePassword =
                                        !_obscurePassword),
                              ),
                            ),
                            validator: RegisterValidators.password,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _passwordController,
                          builder: (context, value, _) =>
                              PasswordStrengthIndicator(
                            password: value.text,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _LabeledField(
                          label: 'CONFIRMER LE MOT DE PASSE',
                          child: TextFormField(
                            key: const Key('register_confirm_password_field'),
                            controller: _confirmPasswordController,
                            enabled: !isLoading,
                            obscureText: _obscureConfirmPassword,
                            autofillHints: const [AutofillHints.newPassword],
                            textInputAction: TextInputAction.done,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              hintText: '••••••••',
                              suffixIcon: _PasswordToggle(
                                buttonKey: const Key(
                                  'register_toggle_confirm_password',
                                ),
                                obscured: _obscureConfirmPassword,
                                onPressed: isLoading
                                    ? null
                                    : () => setState(
                                          () => _obscureConfirmPassword =
                                              !_obscureConfirmPassword,
                                        ),
                              ),
                            ),
                            validator: (raw) =>
                                RegisterValidators.confirmPassword(
                              raw,
                              _passwordController.text,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        TermsCheckbox(
                          value: _acceptedTerms,
                          enabled: !isLoading,
                          onChanged: (v) => setState(() => _acceptedTerms = v),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: AppConstants.minTouchTarget,
                          child: FilledButton(
                            key: const Key('register_submit_button'),
                            onPressed:
                                (!_acceptedTerms || isLoading) ? null : _submit,
                            child: isLoading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Créer mon compte'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _AlreadyAccountLink(
                    onTap: isLoading ? null : () => context.go('/login'),
                  ),
                  const SizedBox(height: 16),
                  const _DividerWithLabel(label: "Ou s'inscrire avec"),
                  const SizedBox(height: 16),
                  OAuthButtons(enabled: !isLoading),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            label,
            style: text.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        child,
      ],
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
                style: TextStyle(
                  color: colors.primary,
                  fontWeight: FontWeight.w600,
                ),
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
