import 'package:flutter/material.dart';

import '../utils/register_validators.dart';

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
      spacing: 8,
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
        return const Color(0xFFEF4444);
      case 2:
        return const Color(0xFFF59E0B);
      case 3:
        return const Color(0xFF10B981);
      case 4:
      default:
        return const Color(0xFF34D399);
    }
  }
}
