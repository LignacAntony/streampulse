import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/exceptions.dart';
import '../providers/register_controller.dart';
import '../utils/register_validators.dart';
import '../widgets/auth_tabs.dart';

/// Écran d'inscription
/// Pose les champs email / pseudo / mot de passe avec validation locale
/// et délègue la création du compte au
/// `registerControllerProvider`.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    await ref.read(registerControllerProvider.notifier).submit(
          email: email,
          username: username,
          password: password,
        );
  }

  void _onStateChanged(
    AsyncValue<dynamic>? previous,
    AsyncValue<dynamic> next,
  ) {
    next.when(
      data: (user) {
        if (user == null) return; // état initial après build()
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
        final message = _humanReadable(error);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
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
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

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
                  // Branding (cohérent avec l'écran /welcome).
                  SizedBox(
                    height: AppConstants.minTouchTarget * 2,
                    child: Icon(
                      Icons.radio,
                      size: AppConstants.minTouchTarget * 1.5,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'StreamPulse',
                    style: text.headlineMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Redéfinissez votre expérience sonore.',
                    style: text.bodyMedium?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  // Onglets Connexion / Inscription.
                  const AuthTabs(active: AuthTab.register),
                  const SizedBox(height: 24),

                  Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('register_email_field'),
                          controller: _emailController,
                          enabled: !isLoading,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'alice@example.com',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: RegisterValidators.email,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('register_username_field'),
                          controller: _usernameController,
                          enabled: !isLoading,
                          keyboardType: TextInputType.text,
                          autofillHints: const [AutofillHints.newUsername],
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Pseudo',
                            hintText: 'alice_42',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: RegisterValidators.username,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('register_password_field'),
                          controller: _passwordController,
                          enabled: !isLoading,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              key: const Key('register_toggle_password'),
                              tooltip: _obscurePassword
                                  ? 'Afficher le mot de passe'
                                  : 'Masquer le mot de passe',
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              onPressed: isLoading
                                  ? null
                                  : () => setState(
                                        () =>
                                            _obscurePassword = !_obscurePassword,
                                      ),
                            ),
                          ),
                          validator: RegisterValidators.password,
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: AppConstants.minTouchTarget,
                          child: FilledButton(
                            key: const Key('register_submit_button'),
                            onPressed: isLoading ? null : _submit,
                            child: isLoading
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text("Créer mon compte"),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
