import 'package:flutter/material.dart';
export 'tokens.dart';
import 'google_fonts_stub.dart' if (dart.library.html) 'google_fonts_web.dart';

// ---------------------------------------------------------------------------
// HAGZY COHESIVE PALETTE — Harmonious Emerald & Clean Slate
// Every surface, gradient, badge, and accent belongs to the same color family
// to match the original Hagzy logo.
// ---------------------------------------------------------------------------

Color get kInk => kDarkMode.value ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
const kDark = Color(0xFF064E3B);

const kGreen = Color(0xFF059669);
const kGreenDark = Color(0xFF047857);
const kGreenLight = Color(0xFF10B981);

const kGold = Color(0xFFD97706);
const kCobalt = Color(0xFF0F766E);
const kTerracotta = Color(0xFFDC2626);

Color get kSuccess => kDarkMode.value ? const Color(0xFF34D399) : const Color(0xFF059669);
Color get kWarning => kDarkMode.value ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
Color get kError => kDarkMode.value ? const Color(0xFFF87171) : const Color(0xFFDC2626);

Color get kPage => kDarkMode.value ? const Color(0xFF090F0D) : const Color(0xFFF8FAFC);
Color get kPanel => kDarkMode.value ? const Color(0xFF111B17) : const Color(0xFFFFFFFF);
Color get kSurfaceTint => kDarkMode.value ? const Color(0xFF162822) : const Color(0xFFECFDF5);
Color get kMuted => kDarkMode.value ? const Color(0xFF94A3B8) : const Color(0xFF475569);
Color get kBorder => kDarkMode.value ? const Color(0xFF1F352D) : const Color(0xFFE2E8F0);

const kStorageKey = 'hagzy_app_data_v1';
const kFavoriteStorageKey = 'hagzy_favorite_venues_v1';
const kLanguageStorageKey = 'hagzy_language_v1';
const kDarkModeStorageKey = 'hagzy_dark_mode_v1';
const kCustomerProfileStorageKey = 'hagzy_customer_profile_v1';
const kAllEgyptAreas = 'All Egypt';
const kWhatsappBusinessNumber = '201024129393';
const kSeedNaderSalon = bool.fromEnvironment(
  'HAGZY_SEED_NADER_SALON',
  defaultValue: false,
);

final ValueNotifier<bool> kDarkMode = ValueNotifier<bool>(false);

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

  static List<BoxShadow> get softShadow => kDarkMode.value ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24, spreadRadius: -3, offset: const Offset(0, 10)), BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))] : [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.06), blurRadius: 24, spreadRadius: -3, offset: const Offset(0, 10)), BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))];

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
    final isDark = kDarkMode.value;
    final textColor = isDark ? const Color(0xFFF8FAFC) : kInk;
    final fontThemed = _isTest
        ? base
        : (arabic
            ? GoogleFonts.cairoTextTheme(base)
            : GoogleFonts.plusJakartaSansTextTheme(base));

    final heightScale = arabic ? 1.32 : 1.24;
    final bodyHeight = arabic ? 1.50 : 1.42;

    return fontThemed
        .copyWith(
          displaySmall: (fontThemed.displaySmall ?? const TextStyle()).copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: arabic ? 0 : -0.6,
            height: heightScale,
          ),
          headlineSmall:
              (fontThemed.headlineSmall ?? const TextStyle()).copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: arabic ? 0 : -0.4,
            height: heightScale,
          ),
          titleMedium: (fontThemed.titleMedium ?? const TextStyle()).copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : -0.2,
            height: heightScale,
          ),
          bodyMedium: (fontThemed.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: bodyHeight,
          ),
          labelLarge: (fontThemed.labelLarge ?? const TextStyle()).copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : 0.1,
          ),
        )
        .apply(
          bodyColor: textColor,
          displayColor: textColor,
          fontFamilyFallback: _isTest ? null : emojiFontFallbacks,
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
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: kInk,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      appBarTheme: AppBarTheme(
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
          side: BorderSide(color: kBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kPage,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: kBorder),
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
          side: BorderSide(color: kBorder),
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

  static ThemeData darkTheme() {
    const darkPage = Color(0xFF090F0D);
    const darkPanel = Color(0xFF111B17);
    const darkInput = Color(0xFF162822);
    const darkBorder = Color(0xFF1F352D);
    const darkText = Color(0xFFF8FAFC);
    final baseScheme = ColorScheme.fromSeed(
      seedColor: kGreen,
      primary: kGreenLight,
      secondary: kGreen,
      tertiary: kGold,
      surface: darkPanel,
      onSurface: darkText,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: darkPage,
      canvasColor: darkPanel,
      dialogTheme: DialogThemeData(
        backgroundColor: darkPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkPanel,
        surfaceTintColor: Colors.transparent,
      ),
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
              bodyColor: darkText,
              displayColor: darkText,
              fontFamilyFallback: emojiFontFallbacks,
            ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPanel,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: darkPanel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInput,
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: kGreenLight, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: kGreen,
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
          backgroundColor: kGreen,
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
        backgroundColor: const Color(0xFF1F352D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, height: 1.35),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF162822),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1F352D)),
        ),
        textStyle: const TextStyle(
          color: Color(0xFFF8FAFC),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: kGreenLight),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkText,
          side: const BorderSide(color: darkBorder),
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
