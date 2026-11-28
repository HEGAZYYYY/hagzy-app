import 'package:flutter/material.dart';
export 'tokens.dart';
import 'google_fonts_stub.dart' if (dart.library.html) 'google_fonts_web.dart';
import 'tokens.dart';

// ---------------------------------------------------------------------------
// HAGZY — WARM HUMAN CONSUMER DESIGN SYSTEM
// Light Mode: Warm Alabaster (#F7F5F0) + Crisp White Cards (#FFFFFF) +
//             Deep Espresso Ink (#171614) + Warm Vermilion (#E8381C)
// Dark Mode:  Warm Charcoal (#121110) + Elevated Stone (#1C1A18) +
//             Warm Ivory (#F5F2EB) + Luminous Vermilion (#FF5236)
// ---------------------------------------------------------------------------

Color get kInk =>
    kDarkMode.value ? const Color(0xFFF5F2EB) : const Color(0xFF171614);

// Preserved high-contrast contract for floating SnackBars
Color get kSnackBarBg =>
    kDarkMode.value ? const Color(0xFF1F352D) : const Color(0xFF0F172A);

const kDark = Color(0xFF171614);
const kObsidian = Color(0xFF171614);
const kObsidianSoft = Color(0xFF24211E);

// Warm Brand Vermilion & Neutral Palette
const kVermilion = Color(0xFFE8381C);
const kVermilionBright = Color(0xFFFF5C40);
const kPaperLight = Color(0xFFF7F5F0);
const kPaperCream = Color(0xFFFAF8F4);

// Unified adaptive brand & accent aliases across all screens (WCAG AA in Light & Dark)
Color get kSignal => kDarkMode.value ? kVermilionBright : kVermilion;
Color get kVolt => kDarkMode.value ? kVermilionBright : kVermilion;
const kVoltMuted = Color(0xFFC42B12);
Color get kGreen =>
    kDarkMode.value ? kVermilionBright : const Color(0xFF171614);
Color get kGreenDark =>
    kDarkMode.value ? const Color(0xFFD93016) : const Color(0xFF171614);
const kGreenLight = Color(0xFFFF6B52);
Color get kEmeraldDeep =>
    kDarkMode.value ? const Color(0xFF4ADE80) : const Color(0xFF171614);

// Adaptive High-Contrast Action Surfaces (4.8:1 white text contrast in dark mode)
Color get kAccentSurface =>
    kDarkMode.value ? const Color(0xFFD93016) : const Color(0xFF171614);
Color get kAccentOnSurface => const Color(0xFFFFFFFF);
Color get kBrandAccent =>
    kDarkMode.value ? kVermilionBright : kVermilion;
Color get kDotGridColor =>
    kDarkMode.value ? const Color(0xFF24221F) : const Color(0xFFE7E2D8);

// Semantic Status Hues (WCAG AA compliant in both Light and Dark)
Color get kGold =>
    kDarkMode.value ? const Color(0xFFFBBF24) : const Color(0xFFC26A1B);
Color get kCobalt =>
    kDarkMode.value ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);
Color get kTerracotta =>
    kDarkMode.value ? const Color(0xFFFB7185) : const Color(0xFFD92D20);
Color get kInfoBlue =>
    kDarkMode.value ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8);

Color get kSuccess =>
    kDarkMode.value ? const Color(0xFF4ADE80) : const Color(0xFF157347);
Color get kWarning =>
    kDarkMode.value ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
Color get kError =>
    kDarkMode.value ? const Color(0xFFFB7185) : const Color(0xFFD92D20);

// Warm Layered Neutral Surfaces
Color get kPage =>
    kDarkMode.value ? const Color(0xFF121110) : const Color(0xFFF7F5F0);
Color get kPanel =>
    kDarkMode.value ? const Color(0xFF1C1A18) : const Color(0xFFFFFFFF);
Color get kPanelElevated =>
    kDarkMode.value ? const Color(0xFF25221F) : const Color(0xFFFFFFFF);
Color get kSurfaceSubtle =>
    kDarkMode.value ? const Color(0xFF262320) : const Color(0xFFF0ECE4);
Color get kSurfaceTint =>
    kDarkMode.value ? const Color(0xFF2C1B18) : const Color(0xFFFDF0ED);
Color get kMuted =>
    kDarkMode.value ? const Color(0xFFBEB7AD) : const Color(0xFF6B655C);
Color get kBorder =>
    kDarkMode.value ? const Color(0xFF35312C) : const Color(0xFFE5E0D7);
Color get kBorderStrong =>
    kDarkMode.value ? const Color(0xFF4F4A43) : const Color(0xFFCFC8BC);

const kStorageKey = 'hagzy_app_data_v1';
const kArchivedVenuesStorageKey = 'hagzy_archived_venues_v1';
const kDeletedVenueIdsStorageKey = 'hagzy_deleted_venue_ids_v1';
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
final ValueNotifier<String> kAppLanguage = ValueNotifier<String>('EN');
bool get isArabicMode => kAppLanguage.value == 'AR';

const List<String> _bilingualFallbacks = [
  'Readex Pro',
  'Plus Jakarta Sans',
  'Apple Color Emoji',
  'Segoe UI Emoji',
  'Noto Color Emoji',
  'sans-serif',
];

/// Clean, warm display typography (`Plus Jakarta Sans` for EN, `Readex Pro` for AR)
/// with graceful bilingual fallback so mixed titles never stretch or clip.
TextStyle hagzyDisplayStyle({
  required bool arabic,
  double fontSize = HagzyTokens.font2Xl,
  FontWeight fontWeight = FontWeight.w800,
  Color? color,
  double? letterSpacing,
  double? height,
}) {
  final resolvedColor = color ?? kInk;
  if (HagzyTheme._isTest) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: resolvedColor,
      letterSpacing: arabic ? 0.0 : (letterSpacing ?? -0.4),
      height: height ?? (arabic ? 1.32 : 1.16),
    );
  }
  if (arabic) {
    return GoogleFonts.readexPro(
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      color: resolvedColor,
      height: height ?? 1.32,
    ).copyWith(fontFamilyFallback: _bilingualFallbacks);
  }
  return GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: resolvedColor,
    letterSpacing: letterSpacing ?? -0.45,
    height: height ?? 1.16,
  ).copyWith(fontFamilyFallback: _bilingualFallbacks);
}

/// Primary UI body and title typography.
TextStyle hagzyTextStyle({
  required bool arabic,
  double fontSize = HagzyTokens.fontBase,
  FontWeight fontWeight = FontWeight.w600,
  Color? color,
  double? letterSpacing,
  double? height,
  bool tabularFigures = false,
}) {
  final features =
      tabularFigures ? const [FontFeature.tabularFigures()] : null;
  if (HagzyTheme._isTest) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? kInk,
      letterSpacing: arabic ? 0.0 : (letterSpacing ?? 0.0),
      height: height ?? (arabic ? 1.44 : 1.32),
      fontFeatures: features,
    );
  }
  if (arabic) {
    return GoogleFonts.readexPro(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? kInk,
      height: height ?? 1.44,
      fontFeatures: features,
    ).copyWith(fontFamilyFallback: _bilingualFallbacks);
  }
  return GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? kInk,
    letterSpacing: letterSpacing ?? -0.1,
    height: height ?? 1.32,
    fontFeatures: features,
  ).copyWith(fontFamilyFallback: _bilingualFallbacks);
}

/// Crisp tabular numeric & badge typography (uses humanist sans with tabular
/// figures for warm consumer polish on prices, times, and counters).
TextStyle hagzyMonoStyle({
  double fontSize = 12,
  FontWeight fontWeight = FontWeight.w700,
  Color? color,
  double? letterSpacing,
  double? height,
  bool arabic = false,
}) {
  if (HagzyTheme._isTest) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? kInk,
      letterSpacing: arabic ? 0.0 : (letterSpacing ?? 0.0),
      height: height ?? 1.28,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }
  if (arabic) {
    return GoogleFonts.readexPro(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color ?? kInk,
      height: height ?? 1.32,
      fontFeatures: const [FontFeature.tabularFigures()],
    ).copyWith(fontFamilyFallback: _bilingualFallbacks);
  }
  return GoogleFonts.plusJakartaSans(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color ?? kInk,
    letterSpacing: letterSpacing ?? 0.05,
    height: height ?? 1.28,
    fontFeatures: const [FontFeature.tabularFigures()],
  ).copyWith(fontFamilyFallback: _bilingualFallbacks);
}

class HagzyTheme {
  static bool get _isTest => WidgetsBinding.instance.runtimeType
      .toString()
      .toLowerCase()
      .contains('test');

  static const LinearGradient obsidianGradient = LinearGradient(
    colors: [Color(0xFF1C1A18), Color(0xFF171614)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFFE8381C), Color(0xFFD62E14)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient voltGradient = LinearGradient(
    colors: [Color(0xFFE8381C), Color(0xFFD62E14)],
  );

  static const LinearGradient coralGradient = LinearGradient(
    colors: [Color(0xFFE8381C), Color(0xFFD62E14)],
  );

  static const LinearGradient slateDarkGradient = LinearGradient(
    colors: [Color(0xFF1C1A18), Color(0xFF171614)],
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFC26A1B), Color(0xFFB45309)],
  );

  // Calm, whisper-soft tactile elevation
  static List<BoxShadow> get subtleShadow => kDarkMode.value
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.24),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF171614).withValues(alpha: 0.045),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ];

  static List<BoxShadow> get softShadow => kDarkMode.value
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.36),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF171614).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 5),
          ),
        ];

  static List<BoxShadow> get floatingShadow => kDarkMode.value
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xFF171614).withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ];

  static List<BoxShadow> get emeraldGlowShadow => const [];
  static List<BoxShadow> get brandGlowShadow => const [];

  static const List<String> emojiFontFallbacks = _bilingualFallbacks;

  static TextTheme buildTextTheme(BuildContext context, bool arabic) {
    final base = Theme.of(context).textTheme;
    final isDark = kDarkMode.value;
    final textColor =
        isDark ? const Color(0xFFF5F2EB) : const Color(0xFF171614);
    final fontThemed = _isTest
        ? base
        : (arabic
            ? GoogleFonts.readexProTextTheme(base)
            : GoogleFonts.plusJakartaSansTextTheme(base));

    final heightScale = arabic ? 1.32 : 1.18;
    final bodyHeight = arabic ? 1.54 : 1.46;

    return fontThemed
        .copyWith(
          displaySmall: (fontThemed.displaySmall ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.font3Xl,
            fontWeight: FontWeight.w800,
            letterSpacing: arabic ? 0 : -0.7,
            height: heightScale,
          ),
          headlineMedium:
              (fontThemed.headlineMedium ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.font2Xl,
            fontWeight: FontWeight.w800,
            letterSpacing: arabic ? 0 : -0.5,
            height: heightScale,
          ),
          headlineSmall:
              (fontThemed.headlineSmall ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontXl,
            fontWeight: FontWeight.w800,
            letterSpacing: arabic ? 0 : -0.35,
            height: heightScale,
          ),
          titleLarge: (fontThemed.titleLarge ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontLg,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : -0.3,
            height: heightScale,
          ),
          titleMedium: (fontThemed.titleMedium ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontMd,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : -0.15,
            height: heightScale,
          ),
          titleSmall: (fontThemed.titleSmall ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontBase,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : -0.1,
            height: heightScale,
          ),
          bodyLarge: (fontThemed.bodyLarge ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontMd,
            fontWeight: FontWeight.w500,
            height: bodyHeight,
          ),
          bodyMedium: (fontThemed.bodyMedium ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontBase,
            fontWeight: FontWeight.w500,
            height: bodyHeight,
          ),
          bodySmall: (fontThemed.bodySmall ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontXs,
            fontWeight: FontWeight.w500,
            height: bodyHeight,
          ),
          labelLarge: (fontThemed.labelLarge ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontBase,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : 0.05,
          ),
          labelMedium: (fontThemed.labelMedium ?? const TextStyle()).copyWith(
            fontSize: HagzyTokens.fontXs,
            fontWeight: FontWeight.w700,
            letterSpacing: arabic ? 0 : 0.15,
          ),
        )
        .apply(
          bodyColor: textColor,
          displayColor: textColor,
          fontFamilyFallback: _isTest ? null : emojiFontFallbacks,
        );
  }

  static ThemeData lightTheme() {
    const lightPage = Color(0xFFF7F5F0);
    const lightPanel = Color(0xFFFFFFFF);
    const lightInput = Color(0xFFFFFFFF);
    const lightBorder = Color(0xFFE5E0D7);
    const lightInk = Color(0xFF171614);
    const lightMuted = Color(0xFF6B655C);
    const lightTint = Color(0xFFFDF0ED);

    final baseScheme = ColorScheme.fromSeed(
      seedColor: kVermilion,
      primary: lightInk,
      onPrimary: Colors.white,
      secondary: kVermilion,
      onSecondary: Colors.white,
      tertiary: kVermilion,
      surface: lightPanel,
      onSurface: lightInk,
      outline: lightBorder,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: lightPage,
      dividerColor: lightBorder,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: lightInk.withValues(alpha: 0.05),
      hoverColor: lightInk.withValues(alpha: 0.04),
      focusColor: kVermilion.withValues(alpha: 0.10),
      dividerTheme: const DividerThemeData(
        color: lightBorder,
        thickness: 1,
        space: 1,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: _isTest
          ? null
          : GoogleFonts.plusJakartaSansTextTheme(const TextTheme()).apply(
              bodyColor: lightInk,
              displayColor: lightInk,
              fontFamilyFallback: emojiFontFallbacks,
            ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: lightInk,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightPage,
        foregroundColor: lightInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: lightPanel,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
          side: const BorderSide(color: lightBorder, width: 1.0),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: lightPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HagzyTokens.radiusSheet),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightInput,
        labelStyle: const TextStyle(
          color: lightMuted,
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF938C82),
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: lightBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: lightBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: lightInk, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: Color(0xFFD92D20), width: 1.2),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: lightPanel,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: lightInk,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: lightInk,
          fontSize: 14,
          height: 1.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusXLarge),
          side: const BorderSide(color: lightBorder, width: 1.0),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: lightInput,
        disabledColor: const Color(0xFFEBE7DF),
        selectedColor: lightTint,
        secondarySelectedColor: lightTint,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(
          color: lightInk,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: kVermilion,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: lightBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return lightInk;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return lightInk;
            return lightPanel;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: lightBorder)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: lightInk,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: lightInk,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightInk,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: lightBorder, width: 1.2),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return lightInk.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return lightInk.withValues(alpha: 0.04);
            }
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: lightInk,
          minimumSize: const Size(44, 44),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return lightInk.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return lightInk.withValues(alpha: 0.04);
            }
            return null;
          }),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return lightInk.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.hovered)) {
              return lightInk.withValues(alpha: 0.04);
            }
            return null;
          }),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: const Color(0xFF0F172A),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: kVermilion),
      popupMenuTheme: PopupMenuThemeData(
        color: lightPanel,
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(
          color: lightInk,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          side: const BorderSide(color: lightBorder, width: 1.0),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: lightInk,
        iconColor: lightInk,
      ),
    );
  }

  static ThemeData darkTheme() {
    const darkPage = Color(0xFF121110);
    const darkPanel = Color(0xFF1C1A18);
    const darkInput = Color(0xFF23201D);
    const darkBorder = Color(0xFF302C28);
    const darkText = Color(0xFFF5F2EB);

    final baseScheme = ColorScheme.fromSeed(
      seedColor: kVermilionBright,
      primary: kVermilion,
      onPrimary: Colors.white,
      secondary: kVermilionBright,
      onSecondary: Colors.white,
      tertiary: kVermilionBright,
      surface: darkPanel,
      onSurface: darkText,
      outline: darkBorder,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: baseScheme,
      scaffoldBackgroundColor: darkPage,
      canvasColor: darkPanel,
      dividerColor: darkBorder,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.white.withValues(alpha: 0.07),
      hoverColor: Colors.white.withValues(alpha: 0.06),
      focusColor: kVermilionBright.withValues(alpha: 0.14),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkPanel,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: darkText,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
        contentTextStyle: const TextStyle(
          color: Color(0xFFE4DFD5),
          fontSize: 14,
          height: 1.45,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusXLarge),
          side: const BorderSide(color: darkBorder, width: 1.0),
        ),
      ),
      iconTheme: const IconThemeData(color: darkText),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: const Color(0xFF2B2724),
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
          border: Border.all(color: darkBorder),
        ),
        textStyle: const TextStyle(
          color: darkText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkInput,
        disabledColor: const Color(0xFF24221F),
        selectedColor: const Color(0xFF331C18),
        secondarySelectedColor: const Color(0xFF331C18),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        labelStyle: const TextStyle(
          color: darkText,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(
          color: kVermilionBright,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: darkBorder),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return darkText;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return kVermilion;
            return darkPanel;
          }),
          side: WidgetStateProperty.all(const BorderSide(color: darkBorder)),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HagzyTokens.radiusSheet),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: _isTest
          ? null
          : GoogleFonts.plusJakartaSansTextTheme(ThemeData.dark().textTheme)
              .apply(
              bodyColor: darkText,
              displayColor: darkText,
              fontFamilyFallback: emojiFontFallbacks,
            ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkPage,
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
          borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
          side: const BorderSide(color: darkBorder, width: 1.0),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkInput,
        labelStyle: const TextStyle(
          color: Color(0xFFBEB7AD),
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
        ),
        floatingLabelStyle: const TextStyle(
          color: kVermilionBright,
          fontWeight: FontWeight.w700,
          fontSize: 13.5,
        ),
        hintStyle: const TextStyle(
          color: Color(0xFF9C958B),
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
        helperStyle: const TextStyle(
          color: Color(0xFFBEB7AD),
          fontSize: 12,
        ),
        prefixIconColor: const Color(0xFFBEB7AD),
        suffixIconColor: const Color(0xFFBEB7AD),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: darkBorder, width: 1.0),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: darkBorder, width: 1.0),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          borderSide: const BorderSide(color: kVermilionBright, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFFD93016),
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.07);
            }
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFFD93016),
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.14);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.07);
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkText,
          backgroundColor: Colors.transparent,
          side: const BorderSide(color: darkBorder, width: 1.2),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: kVermilionBright,
          minimumSize: const Size(44, 44),
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return kVermilionBright.withValues(alpha: 0.12);
            }
            if (states.contains(WidgetState.hovered)) {
              return kVermilionBright.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          splashFactory: NoSplash.splashFactory,
        ).copyWith(
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.10);
            }
            if (states.contains(WidgetState.hovered)) {
              return Colors.white.withValues(alpha: 0.06);
            }
            return null;
          }),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: const Color(0xFF1F352D),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: kVermilionBright),
      popupMenuTheme: PopupMenuThemeData(
        color: darkPanel,
        surfaceTintColor: Colors.transparent,
        textStyle: const TextStyle(
          color: darkText,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          side: const BorderSide(color: darkBorder, width: 1.0),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: darkText,
        iconColor: darkText,
      ),
    );
  }
}
