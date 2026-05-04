import 'package:flutter/material.dart';

// Palette exacte extraite de la charte graphique StreamPulse High-Fidelity.
class AppColors {
  AppColors._();

  // ── Couleurs de marque ──────────────────────────────────────────────────────
  static const Color primary = Color(0xFF6C5CE7); // Violet principal
  static const Color secondary = Color(0xFF00CEC9); // Teal secondaire
  static const Color tertiary = Color(0xFF00B894); // Vert-teal tertiaire
  static const Color error = Color(0xFFFF7675); // Rouge/corail erreur

  // ── Dark mode ───────────────────────────────────────────────────────────────
  // Valeurs extraites pixel par pixel de la charte (Neutral #0D0F14)
  static const Color darkBackground = Color(0xFF0D0F14);
  static const Color darkSurface = Color(0xFF181A23); // Cards légèrement plus claires
  static const Color darkSurfaceVariant = Color(0xFF1F2130); // Hover states, inputs
  static const Color darkOutline = Color(0xFF2E3045);
  static const Color darkOnBackground = Color(0xFFF0F0F5); // Texte principal (quasi-blanc)
  static const Color darkOnSurface = Color(0xFFE2E3EE); // Texte sur cards
  static const Color darkOnSurfaceMuted = Color(0xFF8B8FA8); // Texte secondaire/placeholder

  // ── Light mode ──────────────────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF5F5F7); // Gris Apple ultra-doux
  static const Color lightSurface = Color(0xFFFFFFFF); // Cards blanches
  static const Color lightSurfaceVariant = Color(0xFFEEEEF2); // Hover, inputs
  static const Color lightOutline = Color(0xFFD1D1DB);
  static const Color lightOnBackground = Color(0xFF0D0F14); // Texte quasi-noir
  static const Color lightOnSurface = Color(0xFF1A1B2E); // Texte sur cards
  static const Color lightOnSurfaceMuted = Color(0xFF6B6E82); // Texte secondaire

  // ── Partagés dark/light ─────────────────────────────────────────────────────
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFF0D0F14); // Texte foncé sur teal clair
  static const Color onTertiary = Color(0xFF0D0F14);
  static const Color onError = Color(0xFFFFFFFF);
}
