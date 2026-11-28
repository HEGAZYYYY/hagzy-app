import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import 'common_widgets.dart';

/// Semantic status tone for [HagzyStatusBadge].
enum HagzyStatusTone { success, warning, error, info, neutral, brand, volt, signal }

/// Precision hardware monospace micro-tag (e.g. `01`, `LIVE`, `EGY`).
class HagzyMonoTag extends StatelessWidget {
  const HagzyMonoTag({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.dotColor,
    this.livePulse = false,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;
  final Color? dotColor;
  final bool livePulse;

  @override
  Widget build(BuildContext context) {
    final fg = foregroundColor ?? kInk;
    final bg = backgroundColor ?? kSurfaceSubtle;
    final border = borderColor ?? kBorder;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusXs + 2),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (livePulse) ...[
            LivePulseDot(color: dotColor ?? kSignal, size: 6),
            const SizedBox(width: 6),
          ] else if (dotColor != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hagzyMonoStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: fg,
                letterSpacing: 0.7,
                arabic: isArabicMode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Architectural surface module: crisp hairline frame, machined corners,
/// minimal crisp grounding shadow, optional top-corner index mark.
class HagzySurfaceCard extends StatelessWidget {
  const HagzySurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(HagzyTokens.spacing16),
    this.margin,
    this.radius = HagzyTokens.radiusLarge,
    this.borderColor,
    this.backgroundColor,
    this.gradient,
    this.elevated = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? borderColor;
  final Color? backgroundColor;
  final Gradient? gradient;
  final bool elevated;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: gradient == null ? (backgroundColor ?? kPanel) : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? kBorder,
        width: 1.1,
      ),
      boxShadow: elevated ? HagzyTheme.subtleShadow : null,
    );

    final inner = onTap != null
        ? Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(radius),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: Padding(padding: padding, child: child),
            ),
          )
        : Padding(padding: padding, child: child);

    final card = Container(
      margin: margin,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: inner,
    );

    if (onTap == null) return card;

    return HagzyInteractiveSurface(
      hoverLift: 1.5,
      pressScale: 0.99,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: HagzyMotion.durationMicro,
        curve: HagzyMotion.curveSnappy,
        margin: margin,
        decoration: BoxDecoration(
          color: gradient == null ? (backgroundColor ?? kPanel) : null,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: hovered
                ? (borderColor ?? kBorderStrong)
                : (borderColor ?? kBorder),
            width: 1.1,
          ),
          boxShadow: elevated
              ? (hovered ? HagzyTheme.softShadow : HagzyTheme.subtleShadow)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: inner,
      ),
    );
  }
}

/// Unified precision status tag across bookings, venues, payments, and owner views.
class HagzyStatusBadge extends StatelessWidget {
  const HagzyStatusBadge({
    super.key,
    required this.label,
    this.tone = HagzyStatusTone.brand,
    this.icon,
    this.livePulse = false,
    this.compact = false,
  });

  final String label;
  final HagzyStatusTone tone;
  final IconData? icon;
  final bool livePulse;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;

    final (fg, bg, border) = switch (tone) {
      HagzyStatusTone.volt => (
          Colors.white,
          kVermilion,
          kVermilion,
        ),
      HagzyStatusTone.signal => (
          isDark ? kVermilionBright : kVermilion,
          kVermilion.withValues(alpha: isDark ? 0.18 : 0.09),
          kVermilion.withValues(alpha: isDark ? 0.42 : 0.30),
        ),
      HagzyStatusTone.success => (
          isDark ? const Color(0xFF4ADE80) : const Color(0xFF157347),
          isDark
              ? const Color(0xFF157347).withValues(alpha: 0.22)
              : const Color(0xFFE6F4EC),
          isDark
              ? const Color(0xFF4ADE80).withValues(alpha: 0.35)
              : const Color(0xFF9ED5B5),
        ),
      HagzyStatusTone.warning => (
          isDark ? const Color(0xFFFBBF24) : const Color(0xFF9A4E04),
          isDark
              ? const Color(0xFFD97706).withValues(alpha: 0.20)
              : const Color(0xFFFEF3C7),
          isDark
              ? const Color(0xFFFBBF24).withValues(alpha: 0.36)
              : const Color(0xFFFCD34D),
        ),
      HagzyStatusTone.error => (
          isDark ? const Color(0xFFFB7185) : const Color(0xFFB91C1C),
          isDark
              ? const Color(0xFFDC2626).withValues(alpha: 0.20)
              : const Color(0xFFFEE2E2),
          isDark
              ? const Color(0xFFFB7185).withValues(alpha: 0.36)
              : const Color(0xFFFCA5A5),
        ),
      HagzyStatusTone.info => (
          isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
          isDark
              ? const Color(0xFF2563EB).withValues(alpha: 0.20)
              : const Color(0xFFDBEAFE),
          isDark
              ? const Color(0xFF60A5FA).withValues(alpha: 0.36)
              : const Color(0xFF93C5FD),
        ),
      HagzyStatusTone.brand => (
          isDark ? kVermilionBright : kObsidian,
          isDark ? kVermilion.withValues(alpha: 0.16) : kSurfaceSubtle,
          isDark
              ? kVermilionBright.withValues(alpha: 0.36)
              : kObsidian.withValues(alpha: 0.22),
        ),
      HagzyStatusTone.neutral => (
          kMuted,
          kSurfaceSubtle,
          kBorder,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (livePulse) ...[
            LivePulseDot(color: tone == HagzyStatusTone.volt ? kSignal : fg, size: 6),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Direction-aware trailing chevron (auto-mirrors for Arabic RTL).
class HagzyDirectionalChevron extends StatelessWidget {
  const HagzyDirectionalChevron({
    super.key,
    this.size = 16,
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    // Pin textDirection: TextDirection.ltr so Flutter does not double-flip
    // Icons.chevron_left_rounded (which has matchTextDirection: true).
    return Icon(
      isRtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
      textDirection: TextDirection.ltr,
      size: size,
      color: color ?? kMuted,
    );
  }
}

/// Tactile machined segmented switch (Teenage Engineering × Linear aesthetic).
class HagzySegmentedTabBar extends StatelessWidget {
  const HagzySegmentedTabBar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<({String label, IconData? icon, int? count})> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return HagzySlidingSelector(
      padding: const EdgeInsets.all(4),
      itemCount: items.length,
      selectedIndex: selectedIndex,
      trackDecoration: BoxDecoration(
        color: kSurfaceSubtle,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
        border: Border.all(color: kBorder),
      ),
      indicatorDecoration: BoxDecoration(
        color: kAccentSurface,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
      ),
      itemBuilder: (context, index, selected) {
        final item = items[index];
        return HagzyTap(
          scaleDown: 0.96,
          haptic: HagzyHapticStyle.selection,
          onTap: () => onChanged(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.icon != null) ...[
                  Icon(
                    item.icon,
                    size: 16,
                    color: selected ? kAccentOnSurface : kMuted,
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? kAccentOnSurface : kMuted,
                    ),
                  ),
                ),
                if (item.count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : kPanel,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusFull),
                    ),
                    child: Text(
                      '${item.count}',
                      style: hagzyMonoStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : kMuted,
                        arabic: isArabicMode,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Precision Mission-Control KPI Instrument Tile (Owner Dashboard & Analytics).
class HagzyKpiCard extends StatelessWidget {
  const HagzyKpiCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.subtitle,
    this.accent,
    this.trendLabel,
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final String? subtitle;
  final Color? accent;
  final String? trendLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final accentColor = accent ?? (isDark ? kVolt : kGreenDark);

    return HagzySurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hagzyMonoStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: kMuted,
                    letterSpacing: 0.35,
                    arabic: isArabicMode,
                  ),
                ),
              ),
              if (trendLabel != null)
                HagzyStatusBadge(
                  label: trendLabel!,
                  tone: HagzyStatusTone.brand,
                  compact: true,
                )
              else
                Icon(icon, size: 16, color: kMuted),
            ],
          ),
          const SizedBox(height: 14),
          HagzyAnimatedValue(
            valueKey: value,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: hagzyMonoStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: kInk,
                letterSpacing: -0.6,
                arabic: isArabicMode,
              ),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: kMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Standard modal bottom sheet wrapper with grab handle, subtle dark-mode
/// top edge highlight, soft borders, and keyboard-safe insets.
class HagzySheetShell extends StatelessWidget {
  const HagzySheetShell({
    super.key,
    required this.child,
    this.maxWidth = 580,
    this.maxHeightFactor = 0.90,
    this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 20),
    this.includeKeyboardInset = true,
  });

  final Widget child;
  final double maxWidth;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;
  final bool includeKeyboardInset;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final bottomInset =
        includeKeyboardInset ? MediaQuery.viewInsetsOf(context).bottom : 0.0;
    final topHairline =
        isDark ? Colors.white.withValues(alpha: 0.10) : kBorder;
    final sideHairline =
        isDark ? Colors.white.withValues(alpha: 0.08) : kBorder;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Center(
        heightFactor: 1.0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: screenHeight * maxHeightFactor,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                top: BorderSide(color: topHairline, width: 1.0),
                left: BorderSide(color: sideHairline, width: 1.0),
                right: BorderSide(color: sideHairline, width: 1.0),
              ),
              boxShadow: HagzyTheme.floatingShadow,
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: padding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4.5,
                        margin: const EdgeInsets.only(bottom: 14),
                        decoration: BoxDecoration(
                          color: kMuted.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Adaptive modal presentation helper:
/// - Mobile (`width < 600`): swipeable [HagzySheetShell] bottom sheet (`isSheet: true`).
/// - Tablet/Desktop (`width >= 600`): centered frosted-scrim floating card (`isSheet: false`).
Future<T?> showHagzyAdaptiveModal<T>({
  required BuildContext context,
  required Widget Function(BuildContext context, bool isSheet) builder,
  bool barrierDismissible = true,
  bool enableDrag = true,
  double maxWidth = 440,
  double maxHeightFactor = 0.90,
  EdgeInsetsGeometry sheetPadding = const EdgeInsets.fromLTRB(20, 8, 20, 20),
  RouteSettings? routeSettings,
}) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) {
    return showHagzySheet<T>(
      context: context,
      isDismissible: barrierDismissible,
      enableDrag: enableDrag,
      routeSettings: routeSettings,
      builder: (ctx) => HagzySheetShell(
        maxWidth: maxWidth,
        maxHeightFactor: maxHeightFactor,
        padding: sheetPadding,
        child: builder(ctx, true),
      ),
    );
  }
  return showHagzyDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    routeSettings: routeSettings,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: MediaQuery.sizeOf(ctx).height * maxHeightFactor,
        ),
        child: builder(ctx, false),
      ),
    ),
  );
}

/// Modern iOS/Airbnb/Linear-grade modal shell used across both floating desktop
/// dialogs and mobile bottom sheets.
class HagzyModalCard extends StatelessWidget {
  const HagzyModalCard({
    super.key,
    required this.title,
    this.subtitle,
    this.content,
    this.icon,
    this.iconColor,
    this.iconBackgroundColor,
    this.destructive = false,
    this.centerHeader = false,
    this.showCloseButton = true,
    this.onClose,
    this.primaryLabel,
    this.primaryKey,
    this.onPrimary,
    this.primaryUseFilledButton = false,
    this.primaryLoading = false,
    this.secondaryLabel,
    this.onSecondary,
    this.customActions,
    this.isSheet = false,
    this.scrollable = true,
    this.maxWidth = 440,
  });

  final String title;
  final String? subtitle;
  final Widget? content;
  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final bool destructive;
  final bool centerHeader;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final String? primaryLabel;
  final Key? primaryKey;
  final VoidCallback? onPrimary;
  final bool primaryUseFilledButton;
  final bool primaryLoading;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final Widget? customActions;
  final bool isSheet;
  final bool scrollable;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final arabic = isArabicMode;
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final resolvedIconColor =
        iconColor ?? (destructive ? kError : kBrandAccent);
    final resolvedIconBg = iconBackgroundColor ??
        (destructive ? kError.withValues(alpha: 0.12) : kSurfaceTint);

    final closeButton = showCloseButton
        ? IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              fixedSize: const Size(44, 44),
              padding: EdgeInsets.zero,
              backgroundColor: kSurfaceSubtle,
              foregroundColor: kInk,
              shape: const CircleBorder(),
              splashFactory: NoSplash.splashFactory,
            ),
            onPressed: onClose ?? () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 19),
          )
        : null;

    final header = centerHeader
        ? Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: showCloseButton ? 44 : 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: resolvedIconBg,
                          shape: BoxShape.circle,
                        ),
                        child:
                            Icon(icon, color: resolvedIconColor, size: 25),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: hagzyDisplayStyle(
                        arabic: arabic,
                        fontSize: 19.5,
                        fontWeight: FontWeight.w800,
                        color: kInk,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: kMuted,
                          height: 1.48,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (closeButton != null)
                PositionedDirectional(
                  top: -4,
                  end: -4,
                  child: closeButton,
                ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: resolvedIconBg,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: resolvedIconColor, size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: hagzyDisplayStyle(
                          arabic: arabic,
                          fontSize: 18.5,
                          fontWeight: FontWeight.w800,
                          color: kInk,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: kMuted,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (closeButton != null) ...[
                const SizedBox(width: 8),
                closeButton,
              ],
            ],
          );

    Widget? footer;
    if (customActions != null) {
      footer = customActions;
    } else if (primaryLabel != null || secondaryLabel != null) {
      final primaryColor = destructive ? kError : kAccentSurface;
      final primaryFg = destructive ? Colors.white : kAccentOnSurface;
      final primaryBtnStyle = FilledButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: primaryFg,
        minimumSize: const Size(0, 48),
        elevation: 0,
        splashFactory: NoSplash.splashFactory,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
      );
      final primaryChild = primaryLoading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor: AlwaysStoppedAnimation<Color>(primaryFg),
              ),
            )
          : Text(primaryLabel ?? '');

      final primaryButton = primaryLabel == null
          ? null
          : (primaryUseFilledButton
              ? FilledButton(
                  key: primaryKey,
                  onPressed: primaryLoading ? null : onPrimary,
                  style: primaryBtnStyle,
                  child: primaryChild,
                )
              : ElevatedButton(
                  key: primaryKey,
                  onPressed: primaryLoading ? null : onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: primaryFg,
                    minimumSize: const Size(0, 48),
                    elevation: 0,
                    splashFactory: NoSplash.splashFactory,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                  child: primaryChild,
                ));

      final secondaryButton = secondaryLabel == null
          ? null
          : TextButton(
              onPressed: onSecondary ?? () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                backgroundColor: kSurfaceSubtle,
                foregroundColor: kInk,
                minimumSize: const Size(0, 48),
                splashFactory: NoSplash.splashFactory,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: Text(secondaryLabel!),
            );

      footer = LayoutBuilder(
        builder: (context, constraints) {
          final stackVertically = constraints.maxWidth < 360;
          if (stackVertically ||
              primaryButton == null ||
              secondaryButton == null) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (primaryButton != null) primaryButton,
                if (primaryButton != null && secondaryButton != null)
                  const SizedBox(height: 8),
                if (secondaryButton != null) secondaryButton,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: secondaryButton),
              const SizedBox(width: 10),
              Expanded(child: primaryButton),
            ],
          );
        },
      );
    }

    final bodyWidget = content == null
        ? null
        : (scrollable
            ? SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: isSheet
                      ? 0
                      : MediaQuery.viewInsetsOf(context).bottom * 0.15,
                ),
                child: content,
              )
            : content);

    final inner = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        if (bodyWidget != null) ...[
          const SizedBox(height: 16),
          Flexible(child: bodyWidget),
        ],
        if (footer != null) ...[
          const SizedBox(height: 18),
          footer,
        ],
      ],
    );

    if (isSheet) {
      return inner;
    }

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : kBorder,
              width: 1.0,
            ),
            boxShadow: HagzyTheme.floatingShadow,
          ),
          child: inner,
        ),
      ),
    );
  }
}

/// Modern inset grouped list row with spring press physics, tonal icon badge,
/// hover tint, and animated selection checkmark (replaces legacy ListTile).
class HagzyGroupedRow extends StatelessWidget {
  const HagzyGroupedRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconWidget,
    this.selected = false,
    this.trailing,
    this.onTap,
    this.accentColor,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? iconWidget;
  final bool selected;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final resolvedAccent = accentColor ?? kBrandAccent;
    final radius = BorderRadius.circular(12);

    return HagzyTap(
      scaleDown: 0.985,
      pressedOpacity: 0.92,
      haptic: HagzyHapticStyle.selection,
      borderRadius: radius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: HagzyMotion.durationMicro,
        curve: HagzyMotion.curveSnappy,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? kSurfaceTint : Colors.transparent,
          borderRadius: radius,
          border: Border.all(
            color: selected
                ? resolvedAccent.withValues(alpha: 0.35)
                : Colors.transparent,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            if (iconWidget != null || icon != null) ...[
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? resolvedAccent.withValues(alpha: 0.14)
                      : kSurfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: iconWidget ??
                    Icon(
                      icon,
                      size: 18,
                      color: selected ? resolvedAccent : kInk,
                    ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: kInk,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: kMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ] else
              AnimatedScale(
                scale: selected ? 1.0 : 0.7,
                duration: HagzyMotion.durationMicro,
                curve: HagzyMotion.curveSnappy,
                child: AnimatedOpacity(
                  opacity: selected ? 1.0 : 0.0,
                  duration: HagzyMotion.durationMicro,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: resolvedAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Persistent desktop / tablet navigation rail item.
class HagzySideNavItem {
  const HagzySideNavItem({
    required this.icon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
}

/// Clean Partner Operations Sidebar Rail (no synthetic numeric prefixes).
class HagzyDesktopSidebar extends StatelessWidget {
  const HagzyDesktopSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    required this.arabic,
    this.headerSubtitle,
    this.footer,
  });

  final List<HagzySideNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool arabic;
  final String? headerSubtitle;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 256,
      decoration: BoxDecoration(
        color: kPanel,
        border: BorderDirectional(
          end: BorderSide(color: kBorder, width: 1.0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerSubtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
              child: Row(
                children: [
                  const LivePulseDot(color: kVermilion, size: 6),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      headerSubtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: hagzyTextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: kMuted,
                        arabic: arabic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Divider(height: 1, color: kBorder),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final item = items[index];
                final selected = index == selectedIndex;
                return HagzyTap(
                  scaleDown: 0.98,
                  haptic: HagzyHapticStyle.selection,
                  onTap: () => onSelect(index),
                  child: AnimatedContainer(
                    duration: HagzyTokens.durationFast,
                    curve: HagzyTokens.curveStandard,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? kSurfaceTint : Colors.transparent,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusMedium),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          item.icon,
                          size: 19,
                          color: selected ? kBrandAccent : kMuted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w600,
                              color: selected ? kInk : kMuted,
                            ),
                          ),
                        ),
                        if (item.badgeCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: kVermilion,
                              borderRadius:
                                  BorderRadius.circular(HagzyTokens.radiusFull),
                            ),
                            child: Text(
                              '${item.badgeCount}',
                              style: hagzyMonoStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: kBorder)),
            ),
            child: footer ??
                Row(
                  children: [
                    Text(
                      localized(arabic, 'Hagzy Partner', 'حجزي للشركاء'),
                      style: hagzyTextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: kMuted,
                        arabic: arabic,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: kSuccess,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }
}

/// Precision Telemetry Horizontal Bar Chart for Owner Revenue & Share.
class HagzyRevenueBarChart extends StatelessWidget {
  const HagzyRevenueBarChart({
    super.key,
    required this.entries,
    required this.unitLabel,
    this.arabic = false,
  });

  final List<({String label, double value, Color? color})> entries;
  final String unitLabel;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final maxValue = entries
        .map((e) => e.value)
        .fold<double>(0.0, (a, b) => a > b ? a : b);
    final safeMax = maxValue <= 0 ? 1.0 : maxValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: entries.map((entry) {
        final fraction = (entry.value / safeMax).clamp(0.05, 1.0);
        final barColor = entry.color ?? (isDark ? kVolt : kObsidian);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kInk,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.toStringAsFixed(0)} $unitLabel',
                    style: hagzyMonoStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                      arabic: arabic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                decoration: BoxDecoration(
                  color: kSurfaceSubtle,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: kBorder, width: 0.8),
                ),
                alignment: AlignmentDirectional.centerStart,
                clipBehavior: Clip.antiAlias,
                child: FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

/// Architectural sundial & arena hairline painter for poster surfaces.
class HagzyCourtBlueprintPainter extends CustomPainter {
  const HagzyCourtBlueprintPainter({
    this.lineColor = const Color(0x1EFFFFFF),
    this.accentColor = const Color(0x55E8381C),
  });

  final Color lineColor;
  final Color accentColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Architectural concentric sundial / stadium arcs anchored on trailing edge
    final anchor = Offset(size.width * 0.78, size.height * 0.50);
    final maxR = size.height * 0.72;
    canvas.drawCircle(anchor, maxR, paint);
    canvas.drawCircle(anchor, maxR * 0.62, paint);
    canvas.drawCircle(anchor, maxR * 0.28, paint);

    // Horizontal & vertical registration hairlines
    canvas.drawLine(
      Offset(0, anchor.dy),
      Offset(size.width, anchor.dy),
      paint,
    );
    canvas.drawLine(
      Offset(anchor.dx, 0),
      Offset(anchor.dx, size.height),
      paint,
    );

    // Crisp Vermilion focal sun-point
    canvas.drawCircle(
      anchor,
      4.5,
      Paint()..color = accentColor.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant HagzyCourtBlueprintPainter oldDelegate) =>
      oldDelegate.lineColor != lineColor ||
      oldDelegate.accentColor != accentColor;
}

/// Reusable, store-compliant Privacy Policy & Terms of Service sheet accessible
/// from both Login and Profile (works offline in-app + opens full web URL).
Future<void> showHagzyLegalSheet(
  BuildContext context, {
  required bool arabic,
  required bool isPrivacy,
  String? apiBaseUrl,
}) {
  Future<void> openWebDoc(BuildContext ctx) async {
    final path = isPrivacy ? 'privacy.html' : 'terms.html';
    final Uri uri = kIsWeb
        ? Uri.base.resolve(path)
        : Uri.parse(
            (apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty)
                ? '${apiBaseUrl.trim()}/$path'
                : 'https://hagzy.app/$path',
          );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: kSnackBarBg,
          content: Text(
            localized(
              arabic,
              'Visit hagzy.app/$path in your browser for the web version.',
              'يمكنك زيارة hagzy.app/$path من المتصفح لعرض النسخة الكاملة.',
            ),
          ),
        ),
      );
    }
  }

  Widget section(String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: kInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 13.5,
                color: kMuted,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  return showHagzySheet<void>(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      child: HagzySheetShell(
        maxHeightFactor: 0.88,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: kSurfaceTint,
                    borderRadius:
                        BorderRadius.circular(HagzyTokens.radiusMedium),
                  ),
                  child: Icon(
                    isPrivacy ? Icons.shield_outlined : Icons.gavel_rounded,
                    color: kBrandAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isPrivacy
                        ? localized(arabic, 'Privacy Policy', 'سياسة الخصوصية')
                        : localized(
                            arabic, 'Terms of Service', 'شروط الاستخدام'),
                    style: hagzyDisplayStyle(
                      arabic: arabic,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: kSurfaceSubtle,
                    foregroundColor: kInk,
                    shape: const CircleBorder(),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: kBorder),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isPrivacy) ...[
                      section(
                        localized(
                          arabic,
                          '1. Data Protection (Egyptian Law No. 151 of 2020)',
                          '١. حماية البيانات وفق القانون المصري رقم ١٥١ لسنة ٢٠٢٠',
                        ),
                        localized(
                          arabic,
                          'Hagzy collects only the details needed to manage your reservations—your name, contact details, and optional location when finding nearby places. We never sell or rent your personal data to advertisers.',
                          'يجمع تطبيق حجزي فقط البيانات اللازمة لإدارة حجوزاتك مثل الاسم وبيانات التواصل والموقع عند البحث عن الأماكن القريبة. لا نبيع أو نشارك بياناتك أبداً مع جهات إعلانية.',
                        ),
                      ),
                      section(
                        localized(
                          arabic,
                          '2. Secure Payments & Escrow',
                          '٢. أمان المدفوعات وحماية العربون',
                        ),
                        localized(
                          arabic,
                          'Card, InstaPay, and mobile wallet payments are processed through certified Egyptian payment providers. Hagzy never stores your bank passwords, PINs, or CVV codes.',
                          'تتم عمليات الدفع عبر مزودي الدفع المعتمدين في مصر، ولا يحتفظ تطبيق حجزي بأرقام بطاقاتك البنكية أو كلمات المرور أو رموز الأمان.',
                        ),
                      ),
                      section(
                        localized(
                          arabic,
                          '3. Account & Data Deletion',
                          '٣. حذف الحساب والبيانات الشخصية',
                        ),
                        localized(
                          arabic,
                          'You can permanently delete your Hagzy account and associated data at any time from Profile → Delete Account & Personal Data, or by emailing support@hagzy.app.',
                          'يمكنك حذف حسابك وكافة بياناتك الشخصية نهائياً في أي وقت من خلال تبويب حسابي ثم اختيار "حذف الحساب والبيانات الشخصية"، أو مراسلة support@hagzy.app.',
                        ),
                      ),
                    ] else ...[
                      section(
                        localized(
                          arabic,
                          '1. 15-Minute Instant Hold',
                          '١. تثبيت الموعد لمدة ١٥ دقيقة',
                        ),
                        localized(
                          arabic,
                          'When you choose a slot, Hagzy holds it exclusively for 15 minutes so you can complete your deposit. Unpaid holds release automatically after 15 minutes.',
                          'عند اختيار الموعد، يتم تثبيته لك لمدة ١٥ دقيقة لإتمام دفع العربون، وفي حال عدم السداد خلال المدة يُتاح الموعد تلقائياً للآخرين.',
                        ),
                      ),
                      section(
                        localized(
                          arabic,
                          '2. Cancellation & Refunds',
                          '٢. الإلغاء والاسترداد',
                        ),
                        localized(
                          arabic,
                          'You can cancel or reschedule according to the venue policy shown before checkout. Eligible refunds are returned to your Hagzy Wallet or original payment method.',
                          'يمكنك إلغاء الحجز أو تعديله وفقاً لسياسة المكان الموضحة قبل التأكيد، وتُضاف المبالغ المستردة مباشرةً إلى محفظة حجزي أو وسيلة الدفع الأصلية.',
                        ),
                      ),
                      section(
                        localized(
                          arabic,
                          '3. Venue Guidelines & Support',
                          '٣. قواعد الأماكن والدعم',
                        ),
                        localized(
                          arabic,
                          'Please arrive on time with your QR check-in pass and follow venue guidelines. For help with any booking, contact support@hagzy.app.',
                          'يرجى الحضور في الموعد المحدد مع إظهار بطاقة الدخول QR والالتزام بتعليمات المكان. لأي مساعدة تواصل معنا عبر support@hagzy.app.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        openWebDoc(context);
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        localized(
                          arabic,
                          'Open Full Web Document',
                          'فتح المستند الرسمي بالمتصفح',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
