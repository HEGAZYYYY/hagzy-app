import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/hagzy_theme.dart';
import 'hagzy_motion.dart';

/// Brand variants for the Free-Standing Hagzy Arena-Sundial Mark.
enum HagzyBrandVariant {
  /// Default adaptive free-standing mark: Espresso Ink arches + Vermilion core
  /// in light mode; Warm Alabaster arches + Luminous Vermilion core in dark mode.
  obsidian,

  /// Inverted poster mark (for dark or Vermilion backgrounds): Warm Paper arches.
  volt,

  /// Framed Paper Seal (for app icon / embossed badge contexts).
  light,

  /// Pure dark monochrome mark (1-color ink).
  monochromeDark,

  /// Pure light monochrome mark (1-color paper white).
  monochromeLight,
}

/// Iconic Free-Standing HAGZY Symbol — "The Interlocking Arena & Chrono-Sun".
///
/// Two rotationally symmetric stadium arches interlock around a suspended
/// International Vermilion sphere at `(128, 128)`:
/// - Needs ZERO outer box to stand in website headers, posters, or passes.
/// - Subliminally echoes both the court/chair portal (`H`) and Arabic `ح` curve.
/// - Animates via continuous `PathMetrics` stroke-sweeps + spring-loaded core.
class HagzyBrandSymbol extends StatelessWidget {
  const HagzyBrandSymbol({
    super.key,
    this.size = 36,
    this.variant = HagzyBrandVariant.obsidian,
    this.withGlow = false,
    this.wingLockProgress = 1.0,
    this.coreScale = 1.0,
    this.coreRotationRadians = 0.0,
    this.sheenProgress = 0.0,
  });

  final double size;
  final HagzyBrandVariant variant;
  final bool withGlow;

  /// `0.0..1.0` stroke-draw progress for the two interlocking stadium arches.
  final double wingLockProgress;

  /// `0.0..1.0` scale of the central suspended Vermilion sphere.
  final double coreScale;

  /// Optional subtle orbital rotation (used by [HagzyBrandLoader]).
  final double coreRotationRadians;

  /// Unused legacy hook retained for API compatibility.
  final double sheenProgress;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _HagzyArenaSundialPainter(
          variant: variant,
          isDarkTheme: isDark,
          archProgress: wingLockProgress,
          coreScale: coreScale,
          orbitalAngle: coreRotationRadians,
        ),
      ),
    );
  }
}

class _HagzyArenaSundialPainter extends CustomPainter {
  const _HagzyArenaSundialPainter({
    required this.variant,
    required this.isDarkTheme,
    required this.archProgress,
    required this.coreScale,
    required this.orbitalAngle,
  });

  final HagzyBrandVariant variant;
  final bool isDarkTheme;
  final double archProgress;
  final double coreScale;
  final double orbitalAngle;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 256.0;
    final rect = Offset.zero & size;

    // Optional framed paper seal only for `light` app-icon variant
    if (variant == HagzyBrandVariant.light) {
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(36 * s));
      canvas.drawRRect(
        rrect,
        Paint()
          ..isAntiAlias = true
          ..color = kPaperLight,
      );
      canvas.drawRRect(
        rrect.deflate(2 * s),
        Paint()
          ..isAntiAlias = true
          ..style = PaintingStyle.stroke
          ..strokeWidth = (3 * s).clamp(1.0, 4.0)
          ..color = kObsidian.withValues(alpha: 0.16),
      );
    }

    final Color archColor;
    final Color sunColor;
    switch (variant) {
      case HagzyBrandVariant.obsidian:
        archColor = isDarkTheme ? const Color(0xFFF5F2EB) : kObsidian;
        sunColor = isDarkTheme ? kVermilionBright : kVermilion;
      case HagzyBrandVariant.volt:
        archColor = kPaperCream;
        sunColor = kPaperCream;
      case HagzyBrandVariant.light:
        archColor = kObsidian;
        sunColor = kVermilion;
      case HagzyBrandVariant.monochromeDark:
        archColor = kObsidian;
        sunColor = kObsidian;
      case HagzyBrandVariant.monochromeLight:
        archColor = Colors.white;
        sunColor = Colors.white;
    }

    canvas.save();
    if (orbitalAngle != 0.0) {
      canvas.translate(128 * s, 128 * s);
      canvas.rotate(orbitalAngle);
      canvas.translate(-128 * s, -128 * s);
    }

    final strokePaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 33.0 * s
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..color = archColor;

    // 1. Upper-Left Interlocking Stadium Arch: (48, 190) -> (48, 92) -> 180° arc to (156, 92)
    final upperArch = Path()
      ..moveTo(48 * s, 190 * s)
      ..lineTo(48 * s, 92 * s)
      ..arcTo(
        Rect.fromCircle(center: Offset(102 * s, 92 * s), radius: 54 * s),
        math.pi,
        math.pi,
        false,
      );

    // 2. Lower-Right Interlocking Stadium Arch: (208, 66) -> (208, 164) -> 180° arc to (100, 164)
    final lowerArch = Path()
      ..moveTo(208 * s, 66 * s)
      ..lineTo(208 * s, 164 * s)
      ..arcTo(
        Rect.fromCircle(center: Offset(154 * s, 164 * s), radius: 54 * s),
        0,
        math.pi,
        false,
      );

    final p = archProgress.clamp(0.0, 1.0);
    if (p >= 0.999) {
      canvas.drawPath(upperArch, strokePaint);
      canvas.drawPath(lowerArch, strokePaint);
    } else if (p > 0.005) {
      for (final metric in upperArch.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * p), strokePaint);
      }
      for (final metric in lowerArch.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * p), strokePaint);
      }
    }

    canvas.restore();

    // 3. Central Suspended Chrono-Sun Sphere
    final cs = coreScale.clamp(0.0, 1.35);
    if (cs > 0.01) {
      canvas.drawCircle(
        Offset(128 * s, 128 * s),
        21.0 * s * cs,
        Paint()
          ..isAntiAlias = true
          ..color = sunColor,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HagzyArenaSundialPainter oldDelegate) =>
      oldDelegate.variant != variant ||
      oldDelegate.isDarkTheme != isDarkTheme ||
      oldDelegate.archProgress != archProgress ||
      oldDelegate.coreScale != coreScale ||
      oldDelegate.orbitalAngle != orbitalAngle;
}

/// Primary horizontal editorial lockup: Free-standing Arena-Sundial symbol +
/// sculptural `HAGZY.` wordmark with Vermilion terminal dot.
class HagzyPrimaryLogo extends StatelessWidget {
  const HagzyPrimaryLogo({
    super.key,
    this.symbolSize = 32,
    this.variant = HagzyBrandVariant.obsidian,
    this.arabic = false,
    this.onDark = false,
    this.showSubtitleTag = true,
    this.compact = false,
  });

  final double symbolSize;
  final HagzyBrandVariant variant;
  final bool arabic;
  final bool onDark;
  final bool showSubtitleTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final textColor = onDark ? kPaperCream : kInk;
    final dotColor = onDark ? kVermilionBright : kVermilion;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HagzyBrandSymbol(
          size: symbolSize,
          variant: onDark ? HagzyBrandVariant.volt : variant,
        ),
        SizedBox(width: compact ? 8 : 10),
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  arabic ? 'حجزي' : 'Hagzy',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hagzyDisplayStyle(
                    arabic: arabic,
                    fontSize: compact ? 18 : 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: arabic ? 0 : -0.5,
                    color: textColor,
                  ),
                ),
              ),
              Text(
                '.',
                style: TextStyle(
                  fontSize: compact ? 20 : 24,
                  fontWeight: FontWeight.w900,
                  height: 0.9,
                  color: dotColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Secondary stacked editorial brand lockup.
class HagzySecondaryLogo extends StatelessWidget {
  const HagzySecondaryLogo({
    super.key,
    this.symbolSize = 64,
    this.variant = HagzyBrandVariant.obsidian,
    this.arabic = false,
    this.onDark = false,
    this.tagline,
  });

  final double symbolSize;
  final HagzyBrandVariant variant;
  final bool arabic;
  final bool onDark;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    final fg = onDark ? kPaperCream : kInk;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HagzyBrandSymbol(
          size: symbolSize,
          variant: onDark ? HagzyBrandVariant.volt : variant,
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              arabic ? 'حجزي' : 'Hagzy',
              style: hagzyDisplayStyle(
                arabic: arabic,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: arabic ? 0 : -0.5,
                color: fg,
              ),
            ),
            Text(
              '.',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: onDark ? kVermilionBright : kVermilion,
              ),
            ),
          ],
        ),
        if (tagline != null && tagline!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            tagline!,
            textAlign: TextAlign.center,
            style: hagzyMonoStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: arabic ? 0.2 : 1.6,
              color: onDark ? kPaperCream.withValues(alpha: 0.72) : kMuted,
              arabic: arabic,
            ),
          ),
        ],
      ],
    );
  }
}

/// Kinetic Arena-Sundial Loader: the two interlocking stadium arches trace and
/// rotate in 180-degree harmonic intervals around the Vermilion sun-core.
class HagzyBrandLoader extends StatefulWidget {
  const HagzyBrandLoader({
    super.key,
    this.size = 42,
    this.label,
    this.variant = HagzyBrandVariant.obsidian,
  });

  final double size;
  final String? label;
  final HagzyBrandVariant variant;

  @override
  State<HagzyBrandLoader> createState() => _HagzyBrandLoaderState();
}

class _HagzyBrandLoaderState extends State<HagzyBrandLoader>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (!isHagzyTestRuntime) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1500),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = HagzyMotion.reduced(context);
    final ctrl = _ctrl;

    Widget mark;
    if (reduced || ctrl == null) {
      mark = HagzyBrandSymbol(
        size: widget.size,
        variant: widget.variant,
      );
    } else {
      mark = AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) {
          final t = ctrl.value;
          final eased = Curves.easeInOutCubic.transform(t);
          final sweep = 0.65 + 0.35 * math.sin(t * math.pi);
          final pulse = 0.86 + 0.22 * math.sin(t * math.pi);
          return HagzyBrandSymbol(
            size: widget.size,
            variant: widget.variant,
            wingLockProgress: sweep,
            coreScale: pulse,
            coreRotationRadians: eased * math.pi,
          );
        },
      );
    }

    if (widget.label == null || widget.label!.isEmpty) return mark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        mark,
        const SizedBox(height: 12),
        Text(
          widget.label!,
          textAlign: TextAlign.center,
          style: hagzyMonoStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: kMuted,
            letterSpacing: 0.5,
            arabic: isArabicMode,
          ),
        ),
      ],
    );
  }
}

/// Editorial Archival Paper Brand Opening Reveal:
/// Warm Sunlit Paper stage → dual Espresso Ink stadium arches sweep into
/// lock along `PathMetrics` → International Vermilion sun-disc snaps into
/// center → sculptural `HAGZY.` display wordmark + editorial rule wipe →
/// crisp paper curtain lift into the live application.
class HagzyBrandSplashOverlay extends StatefulWidget {
  const HagzyBrandSplashOverlay({
    super.key,
    required this.onDismiss,
    required this.arabic,
  });

  final VoidCallback onDismiss;
  final bool arabic;

  @override
  State<HagzyBrandSplashOverlay> createState() =>
      _HagzyBrandSplashOverlayState();
}

class _HagzyBrandSplashOverlayState extends State<HagzyBrandSplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _archSweep;
  late final Animation<double> _sunDrop;
  late final Animation<double> _ruleExpand;
  late final Animation<double> _wordmarkOpacity;
  late final Animation<double> _wordmarkSlide;
  late final Animation<double> _exitOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );

    _archSweep = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.04, 0.46, curve: Curves.easeInOutCubic),
    );
    _sunDrop = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.32, 0.58, curve: Curves.easeOutBack),
    );
    _ruleExpand = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.40, 0.68, curve: Curves.easeOutQuart),
    );
    _wordmarkOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.38, 0.64, curve: Curves.easeOut),
    );
    _wordmarkSlide = Tween<double>(begin: 16.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.38, 0.66, curve: Curves.easeOutCubic),
      ),
    );
    _exitOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.86, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    _ctrl.forward().then((_) {
      if (mounted) widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = kDarkMode.value;
    final bg = isDark ? const Color(0xFF121110) : kPaperLight;
    final ink = isDark ? const Color(0xFFF5F2EB) : kObsidian;

    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final slogan = widget.arabic
              ? 'ملاعب · صالونات · مساحات ترفيه في مصر'
              : 'Courts, salons & spaces across Egypt';
          return Opacity(
            opacity: _exitOpacity.value.clamp(0.0, 1.0),
            child: Material(
              color: bg,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HagzyBrandSymbol(
                      size: 82,
                      variant: HagzyBrandVariant.obsidian,
                      wingLockProgress: _archSweep.value,
                      coreScale: _sunDrop.value,
                    ),
                    const SizedBox(height: 20),
                    Opacity(
                      opacity: _wordmarkOpacity.value.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, _wordmarkSlide.value),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              widget.arabic ? 'حجزي' : 'Hagzy',
                              style: hagzyDisplayStyle(
                                arabic: widget.arabic,
                                color: ink,
                                fontSize: widget.arabic ? 34 : 34,
                                fontWeight: FontWeight.w800,
                                letterSpacing: widget.arabic ? 0 : -0.6,
                              ),
                            ),
                            const Text(
                              '.',
                              style: TextStyle(
                                color: kVermilion,
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                height: 0.9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 120 * _ruleExpand.value.clamp(0.0, 1.0),
                      height: 1.5,
                      decoration: BoxDecoration(
                        color: kBorder,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Opacity(
                      opacity: _wordmarkOpacity.value.clamp(0.0, 1.0),
                      child: Text(
                        slogan,
                        style: hagzyTextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: kMuted,
                          arabic: widget.arabic,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
