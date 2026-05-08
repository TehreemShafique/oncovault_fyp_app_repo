import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class OV {
  static const Color primary          = Color(0xFF635B6E);
  static const Color onPrimary        = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFF3E8FF);
  static const Color secondary        = Color(0xFF50616B);
  static const Color secondaryContainer = Color(0xFFD3E5F1);
  static const Color tertiary         = Color(0xFF52625C);
  static const Color tertiaryContainer  = Color(0xFFDFF0E8);
  static const Color surface          = Color(0xFFF9F9F9);
  static const Color surfaceLowest    = Color(0xFFFFFFFF);
  static const Color surfaceLow       = Color(0xFFF3F3F3);
  static const Color surfaceContainer = Color(0xFFEEEEEE);
  static const Color onSurface        = Color(0xFF1A1C1C);
  static const Color onSurfaceVariant = Color(0xFF49454C);
  static const Color outline          = Color(0xFF7A757C);
  static const Color outlineVariant   = Color(0xFFCAC5CC);
  static const Color error            = Color(0xFFBA1A1A);
  static const Color errorContainer   = Color(0xFFFFDAD6);
  static const Color background       = Color(0xFFF9F9F9);
  static const Color slateDark        = Color(0xFF4A4456);

  static const LinearGradient splashGrad = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEDE8F5), Color(0xFFF5F0FF), Color(0xFFF9F9F9)],
    stops: [0.0, 0.5, 1.0],
  );

  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme(
      brightness: Brightness.light,
      primary: primary, onPrimary: onPrimary,
      primaryContainer: primaryContainer, onPrimaryContainer: Color(0xFF6F677A),
      secondary: secondary, onSecondary: onPrimary,
      secondaryContainer: secondaryContainer, onSecondaryContainer: Color(0xFF566771),
      tertiary: tertiary, onTertiary: onPrimary,
      tertiaryContainer: tertiaryContainer, onTertiaryContainer: Color(0xFF5E6E68),
      error: error, onError: onPrimary,
      errorContainer: errorContainer, onErrorContainer: Color(0xFF93000A),
      surface: surface, onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      outline: outline, outlineVariant: outlineVariant,
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF3F3F3),
      surfaceContainer: Color(0xFFEEEEEE),
    ),
    textTheme: TextTheme(
      displayLarge:  GoogleFonts.manrope(fontSize: 48, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: -0.96, color: onSurface),
      headlineLarge: GoogleFonts.manrope(fontSize: 32, fontWeight: FontWeight.w600, height: 1.3, color: onSurface),
      headlineMedium:GoogleFonts.manrope(fontSize: 24, fontWeight: FontWeight.w500, height: 1.4, color: onSurface),
      bodyLarge:  GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w400, height: 1.6, color: onSurface),
      bodyMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, height: 1.6, color: onSurface),
      labelLarge: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, height: 1.2, letterSpacing: 0.14, color: onSurface),
      labelSmall: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, height: 1.2, color: onSurface),
    ),
  );
}