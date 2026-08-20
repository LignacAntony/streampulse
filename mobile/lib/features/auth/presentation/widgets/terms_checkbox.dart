import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Case de consentement de l'inscription.
///
/// StatefulWidget et non Stateless : les TapGestureRecognizer des deux liens
/// possèdent des ressources natives et doivent être libérés dans dispose(). Les
/// recréer à chaque build() les fuirait à chaque reconstruction.
class TermsCheckbox extends StatefulWidget {
  const TermsCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.onPrivacyTap,
    this.onTermsTap,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onPrivacyTap;
  final VoidCallback? onTermsTap;
  final bool enabled;

  @override
  State<TermsCheckbox> createState() => _TermsCheckboxState();
}

class _TermsCheckboxState extends State<TermsCheckbox> {
  late final TapGestureRecognizer _privacy;
  late final TapGestureRecognizer _terms;

  @override
  void initState() {
    super.initState();
    // onTap est relu à chaque appui via widget.* : un rappel changé par le
    // parent est pris en compte sans recréer le recognizer.
    _privacy = TapGestureRecognizer()..onTap = () => widget.onPrivacyTap?.call();
    _terms = TapGestureRecognizer()..onTap = () => widget.onTermsTap?.call();
  }

  @override
  void dispose() {
    _privacy.dispose();
    _terms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: 4,
      children: [
        Checkbox(
          key: const Key('register_terms_checkbox'),
          value: widget.value,
          onChanged:
              widget.enabled ? (v) => widget.onChanged(v ?? false) : null,
        ),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: text.bodyMedium?.copyWith(color: colors.onSurface),
              children: [
                const TextSpan(text: "J'accepte la "),
                TextSpan(
                  text: 'politique de confidentialité',
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    // Le soulignement fait la moitié du travail : la couleur
                    // seule ne distingue pas un lien pour qui ne perçoit pas
                    // le contraste de teinte (WCAG 1.4.1).
                    decoration: TextDecoration.underline,
                    decorationColor: colors.primary,
                  ),
                  recognizer: _privacy,
                ),
                const TextSpan(text: ' et les '),
                TextSpan(
                  text: "conditions d'utilisation",
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline,
                    decorationColor: colors.primary,
                  ),
                  recognizer: _terms,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
