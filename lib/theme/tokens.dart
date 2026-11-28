import 'package:flutter/material.dart';

/// HAGZY — DESIGN TOKENS
/// Warm, approachable consumer craft built for iOS, Android, and Web:
/// Calm neutral surfaces, refined 10–14px radii, subtle borders, generous whitespace.
abstract class HagzyTokens {
  // ── Spacing Scale (4px base grid) ─────────────────────────────────────────
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing6 = 6.0;
  static const double spacing8 = 8.0;
  static const double spacing10 = 10.0;
  static const double spacing12 = 12.0;
  static const double spacing14 = 14.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing28 = 28.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;
  static const double spacing64 = 64.0;

  // ── Refined Approachable Radii (10–14px controls/cards, 24px sheets) ──────
  static const double radiusXs = 6.0;
  static const double radiusSmall = 10.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 14.0;
  static const double radiusXLarge = 18.0;
  static const double radiusSheet = 24.0;
  static const double radiusFull = 999.0;

  // ── Accessibility & HIG/Material Minimums ─────────────────────────────────
  static const double minTapTarget = 44.0;
  static const double minAccessibleFontSize = 12.0;

  // ── Consumer Typography Scale ─────────────────────────────────────────────
  static const double fontXs = 12.0;
  static const double fontSm = 13.0;
  static const double fontBase = 14.0;
  static const double fontMd = 16.0;
  static const double fontLg = 18.0;
  static const double fontXl = 22.0;
  static const double font2Xl = 26.0;
  static const double font3Xl = 32.0;
  static const double font4Xl = 40.0;

  // ── Elevation & Blur ──────────────────────────────────────────────────────
  static const double blurLight = 6.0;
  static const double blurMedium = 12.0;
  static const double blurHeavy = 20.0;

  // ── Motion System (Tactile, Crisp, Unhurried) ─────────────────────────────
  static const Duration durationPress = Duration(milliseconds: 70);
  static const Duration durationRelease = Duration(milliseconds: 150);
  static const Duration durationInstant = Duration(milliseconds: 90);
  static const Duration durationFast = Duration(milliseconds: 160);
  static const Duration durationDialogExit = Duration(milliseconds: 160);
  static const Duration durationDialogEnter = Duration(milliseconds: 220);
  static const Duration durationMedium = Duration(milliseconds: 220);
  static const Duration durationSheetEnter = Duration(milliseconds: 260);
  static const Duration durationSlow = Duration(milliseconds: 320);

  static const Curve curveDialogEnter = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve curveRelease = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveEmphasized = Curves.easeInOutCubic;
  static const Curve curveSpring = Curves.easeOutBack;

  // ── Responsive Breakpoints ────────────────────────────────────────────────
  static const double breakpointMobile = 640.0;
  static const double breakpointTablet = 900.0;
  static const double breakpointDesktop = 1200.0;
  static const double maxContentWidth = 1280.0;
  static const double maxFormWidth = 460.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).width < breakpointMobile;

  static bool isTablet(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return w >= breakpointMobile && w < breakpointTablet;
  }

  static bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= breakpointTablet;

  static bool isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= breakpointDesktop;

  static int gridColumnsForWidth(double width) {
    if (width >= 1200) return 3;
    if (width >= 860) return 2;
    return 1;
  }

  static EdgeInsets pagePadding(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w >= breakpointDesktop) {
      return const EdgeInsets.symmetric(horizontal: 32, vertical: 20);
    }
    if (w >= breakpointMobile) {
      return const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    }
    return const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
  }
}
