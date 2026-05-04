import 'package:flutter/material.dart';

// Palette inspirée du streaming audio : tons sombres, accent violet-bleu.
class AppColors {
  AppColors._();

  static const Color primary = Color(0xFF7C3AED); // Violet profond
  static const Color secondary = Color(0xFF3B82F6); // Bleu électrique
  static const Color background = Color(0xFF0F0F0F); // Noir quasi-total
  static const Color surface = Color(0xFF1A1A2E); // Surface sombre bleutée
  static const Color error = Color(0xFFEF4444); // Rouge erreur

  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFFF1F5F9);
  static const Color onSurface = Color(0xFFE2E8F0);
  static const Color onError = Color(0xFFFFFFFF);

  // Nuances supplémentaires
  static const Color surfaceVariant = Color(0xFF252540);
  static const Color outline = Color(0xFF3F3F5F);
}
