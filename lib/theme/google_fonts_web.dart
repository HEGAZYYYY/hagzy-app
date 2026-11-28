import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart' as gf;

/// Clean humanist font pairing for Web & native:
/// - English UI & headings: `Plus Jakarta Sans` (warm, crisp, highly legible)
/// - Arabic UI & headings: `Readex Pro` (balanced modern Arabic geometry)
class GoogleFonts {
  static TextTheme cairoTextTheme(TextTheme base) =>
      gf.GoogleFonts.readexProTextTheme(base);

  static TextTheme plusJakartaSansTextTheme(TextTheme base) =>
      gf.GoogleFonts.plusJakartaSansTextTheme(base);

  static TextTheme spaceGroteskTextTheme(TextTheme base) =>
      gf.GoogleFonts.plusJakartaSansTextTheme(base);

  static TextTheme alexandriaTextTheme(TextTheme base) =>
      gf.GoogleFonts.readexProTextTheme(base);

  static TextTheme readexProTextTheme(TextTheme base) =>
      gf.GoogleFonts.readexProTextTheme(base);

  static TextStyle plusJakartaSans({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) =>
      gf.GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: fontFeatures,
      );

  /// Retained symbol alias — routes to `Plus Jakarta Sans` so dense titles
  /// and bilingual venue names remain crisp and legible without wide stretching.
  static TextStyle syne({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) =>
      gf.GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: fontFeatures,
      );

  static TextStyle readexPro({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) =>
      gf.GoogleFonts.readexPro(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures: fontFeatures,
      );

  /// Tabular numeric style using `Plus Jakarta Sans` with `tabularFigures`
  /// so prices, times, and counters align cleanly without harsh typewriter mono.
  static TextStyle jetBrainsMono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    List<FontFeature>? fontFeatures,
  }) =>
      gf.GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
        fontFeatures:
            fontFeatures ?? const [FontFeature.tabularFigures()],
      );
}
