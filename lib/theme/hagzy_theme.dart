import 'package:flutter/material.dart';
import 'google_fonts_stub.dart' if (dart.library.html) 'google_fonts_web.dart';

// ---------------------------------------------------------------------------
// HAGZY COHESIVE PALETTE — Harmonious Emerald & Clean Slate
// Every surface, gradient, badge, and accent belongs to the same color family
// to match the original Hagzy logo.
// ---------------------------------------------------------------------------

const kInk = Color(0xFF0F172A);
const kDark = Color(0xFF064E3B);

const kGreen = Color(0xFF059669);
const kGreenDark = Color(0xFF047857);
const kGreenLight = Color(0xFF10B981);

const kGold = Color(0xFFF59E0B);
const kCobalt = Color(0xFF059669);
const kTerracotta = Color(0xFF047857);

const kPage = Color(0xFFF8FAFC);
const kPanel = Color(0xFFFFFFFF);
const kSurfaceTint = Color(0xFFF0FDF4);
const kMuted = Color(0xFF64748B);
const kBorder = Color(0xFFE2E8F0);

const kStorageKey = 'hagzy_app_data_v1';
const kFavoriteStorageKey = 'hagzy_favorite_venues_v1';
const kLanguageStorageKey = 'hagzy_language_v1';
const kCustomerProfileStorageKey = 'hagzy_customer_profile_v1';
const kAllEgyptAreas = 'All Egypt';
const kWhatsappBusinessNumber = '201024129393';
const kSeedNaderSalon = bool.fromEnvironment(
  'HAGZY_SEED_NADER_SALON',
  defaultValue: false,
);

class HagzyTheme {
  static bool get _isTest => WidgetsBinding.instance.runtimeType
      .toString()
      .toLowerCase()
      .contains('test');

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF047857), Color(0xFF059669)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient coralGradient = LinearGradient(
    colors: [Color(0xFF059669), Color(0xFF10B981)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient obsidianGradient = LinearGradient(
    colors: [Color(0xFF064E3B), Color(0xFF047857)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.06),
          blurRadius: 24,
          spreadRadius: -3,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  static List<BoxShadow> get emeraldGlowShadow => [
        BoxShadow(
          color: kGreen.withValues(alpha: 0.28),
          blurRadius: 22,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get brandGlowShadow => emeraldGlowShadow;

  static const List<String> emojiFontFallbacks = [
    'Apple Color Emoji',
    'Segoe UI Emoji',
    'Noto Color Emoji',
    'Twemoji Mozilla',
    'sans-serif',
  ];

  static TextTheme buildTextTheme(BuildContext context, bool arabic) {
    final base = Theme.of(context).textTheme;
    if (_isTest) {
      return base.apply(bodyColor: kInk, displayColor: kInk);
    }
    return (arabic
            ? GoogleFonts.cairoTextTheme(base)
            : GoogleFonts.plusJakartaSansTextTheme(base))
        .apply(
          bodyColor: kInk,
          displayColor: kInk,
          fontFamilyFallback: emojiFontFallbacks,
        );
  }

  static ThemeData lightTheme() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: kGreen,
      primary: kGreen,
      secondary: kGreenDark,
      tertiary: kGreenLight,
      surface: kPanel,
      brightness: Brightness.light,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: kPage,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: _isTest
          ? null
          : GoogleFonts.plusJakartaSansTextTheme(const TextTheme()).apply(
              bodyColor: kInk,
              displayColor: kInk,
              fontFamilyFallback: emojiFontFallbacks,
            ),
      appBarTheme: const AppBarTheme(
        backgroundColor: kPanel,
        foregroundColor: kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: kPanel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: kBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kPage,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: kGreen, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          // kGreenDark (not kGreen): white text needs >= 4.5:1 contrast (WCAG AA).
          backgroundColor: kGreenDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          // kGreenDark (not kGreen): white text needs >= 4.5:1 contrast (WCAG AA).
          backgroundColor: kGreenDark,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            letterSpacing: -0.2,
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGreenDark),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kInk,
          side: const BorderSide(color: kBorder),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }
}
