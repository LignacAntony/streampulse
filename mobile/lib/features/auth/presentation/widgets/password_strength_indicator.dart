import 'package:flutter/material.dart';

import '../utils/register_validators.dart';

/// Indicateur visuel de la force du mot de passe : 4 barres horizontales
/// remplies progressivement et un libellé textuel.
///
/// Le calcul du score est délégué à `RegisterValidators.passwordStrength`
/// pour que la logique reste testable sans widget.
class PasswordStrengthIndicator extends StatelessWidget {
  const PasswordStrengthIndicator({super.key, required this.password});

  final String password;

  static const int _segments = 4;

  @override
  Widget build(BuildContext context) {
    final score = RegisterValidators.passwordStrength(password);
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final filledColor = _scoreColor(score);
    final emptyColor = colors.surfaceContainerHigh;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(_segments, (i) {
            final isFilled = i < score;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == _segments - 1 ? 0 : 6),
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: isFilled ? filledColor : emptyColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Force : ${_scoreLabel(score)}',
          style: text.bodySmall?.copyWith(
            color: score == 0 ? colors.onSurfaceVariant : filledColor,
          ),
        ),
      ],
    );
  }

  static String _scoreLabel(int score) {
    switch (score) {
      case 0:
        return '—';
      case 1:
        return 'Très faible';
      case 2:
        return 'Faible';
      case 3:
        return 'Modérée';
      case 4:
      default:
        return 'Forte';
    }
  }

  Color _scoreColor(int score) {
    switch (score) {
      case 0:
      case 1:
        return const Color(0xFFEF4444); // red-500
      case 2:
        return const Color(0xFFF59E0B); // amber-500
      case 3:
        return const Color(0xFF10B981); // emerald-500
      case 4:
      default:
        return const Color(0xFF34D399); // emerald-400
    }
  }
}
