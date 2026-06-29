import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Police Inter — charte graphique StreamPulse (Headline / Body / Label).
class AppTypography {
  AppTypography._();

  // Styles de base Inter, à coloriser via Theme.of(context).textTheme
  static TextTheme get textTheme => GoogleFonts.interTextTheme(
        const TextTheme(
          // Titres / headlines
          displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400, letterSpacing: -0.25),
          displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400),
          displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400),
          headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.3),
          headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),

          // Titres de section
          titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.1),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),

          // Corps de texte
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.15),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 0.1),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.3),

          // Labels / boutons
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.4),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),
        ),
      );
}
