import 'package:flutter/material.dart';

/// Case à cocher d'acceptation des CGU + politique de confidentialité.
/// Composant contrôlé : la valeur est portée par le parent.
///
/// Les liens vers les pages légales seront branchés dans une US ultérieure
/// (callbacks `onPrivacyTap` / `onTermsTap` réservés).
class TermsCheckbox extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          key: const Key('register_terms_checkbox'),
          value: value,
          onChanged: enabled ? (v) => onChanged(v ?? false) : null,
        ),
        const SizedBox(width: 4),
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
                  ),
                ),
                const TextSpan(text: ' et les '),
                TextSpan(
                  text: "conditions d'utilisation",
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
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
