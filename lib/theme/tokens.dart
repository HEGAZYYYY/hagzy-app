/// HAGZY DESIGN SYSTEM TOKENS
/// Single authoritative source for design dimensions, typography limits, and spacing.
abstract class HagzyTokens {
  // Spacing
  static const double spacing2 = 2.0;
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing12 = 12.0;
  static const double spacing16 = 16.0;
  static const double spacing20 = 20.0;
  static const double spacing24 = 24.0;
  static const double spacing32 = 32.0;
  static const double spacing40 = 40.0;
  static const double spacing48 = 48.0;

  // Corner Radii
  static const double radiusSmall = 8.0;
  static const double radiusMedium = 12.0;
  static const double radiusLarge = 16.0;
  static const double radiusXLarge = 24.0;
  static const double radiusFull = 999.0;

  // Accessibility & WCAG Minimums
  static const double minTapTarget = 48.0; // WCAG 2.5.5 Target Size (Enhanced)
  static const double minAccessibleFontSize = 12.0; // No text below 12px for readability

  // Font Sizes
  static const double fontXs = 12.0;
  static const double fontSm = 13.0;
  static const double fontBase = 14.0;
  static const double fontMd = 16.0;
  static const double fontLg = 18.0;
  static const double fontXl = 20.0;
  static const double font2Xl = 24.0;
  static const double font3Xl = 28.0;

  // Elevation & Blur
  static const double blurLight = 8.0;
  static const double blurMedium = 16.0;
  static const double blurHeavy = 24.0;
}
