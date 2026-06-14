import 'package:flutter/material.dart';

/// Avatar du profil : initiales du pseudo si `avatarUrl == null`.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.pseudo,
    this.avatarUrl,
    this.radius = 44,
  });

  final String pseudo;
  final String? avatarUrl;
  final double radius;

  String get _initials {
    final parts = pseudo.trim().split(RegExp(r'\s+'));
    final letters = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = avatarUrl;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colors.primary, width: 2),
      ),
      child: CircleAvatar(
        radius: radius,
        backgroundColor: colors.surfaceContainerHighest,
        backgroundImage: url != null ? NetworkImage(url) : null,
        child: url == null
            ? Text(
                _initials,
                style: TextStyle(
                  fontSize: radius * 0.6,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              )
            : null,
      ),
    );
  }
}
