import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
          blurRadius: 20,
          spreadRadius: -2,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.02),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get emeraldGlowShadow => [
        BoxShadow(
          color: kGreen.withValues(alpha: 0.22),
          blurRadius: 18,
          spreadRadius: -2,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get brandGlowShadow => emeraldGlowShadow;

  static TextTheme buildTextTheme(BuildContext context, bool arabic) {
    final base = Theme.of(context).textTheme;
    if (_isTest) {
      return base.apply(bodyColor: kInk, displayColor: kInk);
    }
    return (arabic
            ? GoogleFonts.cairoTextTheme(base)
            : GoogleFonts.plusJakartaSansTextTheme(base))
        .apply(bodyColor: kInk, displayColor: kInk);
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
      textTheme: _isTest
          ? null
          : GoogleFonts.plusJakartaSansTextTheme().apply(
              bodyColor: kInk,
              displayColor: kInk,
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
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: kBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kPage,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: kGreen, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: kGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kInk,
          side: const BorderSide(color: kBorder),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: kPage,
        side: const BorderSide(color: kBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: kBorder,
        thickness: 1,
      ),
    );
  }
}
