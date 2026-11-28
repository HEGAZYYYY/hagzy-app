import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../theme/hagzy_theme.dart';

/// Shared test-runtime detector (used across motion & brand components so
/// continuous tickers never block `tester.pumpAndSettle()`).
bool get isHagzyTestRuntime => WidgetsBinding.instance.runtimeType
    .toString()
    .toLowerCase()
    .contains('test');

/// Subtle, platform-appropriate tactile haptics guarded safely for Web & tests.
enum HagzyHapticStyle { none, selection, light, medium }

abstract class HagzyHaptics {
  static void trigger(HagzyHapticStyle style) {
    if (style == HagzyHapticStyle.none || kIsWeb || isHagzyTestRuntime) return;
    try {
      switch (style) {
        case HagzyHapticStyle.none:
          break;
        case HagzyHapticStyle.selection:
          HapticFeedback.selectionClick();
        case HagzyHapticStyle.light:
          HapticFeedback.lightImpact();
        case HagzyHapticStyle.medium:
          HapticFeedback.mediumImpact();
      }
    } catch (_) {}
  }

  static void selection() => trigger(HagzyHapticStyle.selection);
  static void light() => trigger(HagzyHapticStyle.light);
  static void medium() => trigger(HagzyHapticStyle.medium);
}

/// Motion system configuration & accessibility helpers.
abstract class HagzyMotion {
  static const Duration durationPress = Duration(milliseconds: 65);
  static const Duration durationRelease = Duration(milliseconds: 180);
  static const Duration durationMicro = Duration(milliseconds: 120);
  static const Duration durationDialogExit = Duration(milliseconds: 150);
  static const Duration durationDialogEnter = Duration(milliseconds: 240);
  static const Duration durationSnappy = Duration(milliseconds: 220);
  static const Duration durationSheetEnter = Duration(milliseconds: 280);
  static const Duration durationSheetExit = Duration(milliseconds: 200);
  static const Duration durationFluid = Duration(milliseconds: 300);
  static const Duration durationChoreo = Duration(milliseconds: 400);

  static const Curve curvePress = Curves.easeOutQuad;
  static const Curve curveRelease = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Curve curveDialogEnter = Cubic(0.16, 1.0, 0.3, 1.0);
  static const Curve curveDialogExit = Curves.easeInCubic;
  static const Curve curveSnappy = Curves.easeOutCubic;
  static const Curve curveDecel = Curves.easeOutQuart;
  static const Curve curveSpring = Curves.easeOutBack;
  static const Curve curveSmooth = Curves.easeInOutCubic;

  /// Critically damped spring for crisp, zero-overshoot tactile press release.
  static const SpringDescription releaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 32.0,
  );

  /// Returns `true` in Flutter widget tests or whenever the user has enabled
  /// OS-level Reduce Motion / Disable Animations.
  static bool reduced(BuildContext context) =>
      isHagzyTestRuntime || MediaQuery.disableAnimationsOf(context);
}

/// Unified Dialog & Popup Transition Engine.
///
/// - Entrance: `240ms` crisp ease-out (`Cubic(0.16, 1, 0.3, 1)`), subtle scale
///   `0.94 → 1.0`, gentle `12px` upward drift + smooth fade + frosted scrim.
/// - Exit: faster `150ms` ease-in (`1.0 → 0.96` scale + fade).
/// - Respects `MediaQuery.disableAnimationsOf(context)` and test runtimes.
Future<T?> showHagzyDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color? barrierColor,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
}) {
  final reduced = HagzyMotion.reduced(context);
  final resolvedLabel = barrierLabel ??
      MaterialLocalizations.of(context).modalBarrierDismissLabel;
  final defaultBarrier = kDarkMode.value
      ? Colors.black.withValues(alpha: 0.62)
      : const Color(0xFF0F0E0C).withValues(alpha: 0.42);

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierDismissible ? resolvedLabel : null,
    barrierColor: barrierColor ?? defaultBarrier,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    transitionDuration:
        reduced ? Duration.zero : HagzyMotion.durationDialogEnter,
    pageBuilder: (dialogContext, _, __) => builder(dialogContext),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      if (reduced) return child;
      final isReversing = animation.status == AnimationStatus.reverse;
      final anim = CurvedAnimation(
        parent: animation,
        curve: isReversing
            ? const Interval(0.375, 1.0, curve: HagzyMotion.curveDialogExit)
            : HagzyMotion.curveDialogEnter,
      );
      return AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (context, inner) {
          final t = anim.value.clamp(0.0, 1.0);
          final blurSigma = 6.0 * t;
          final scale = isReversing ? (0.96 + 0.04 * t) : (0.94 + 0.06 * t);
          final dy = isReversing ? 0.0 : (12.0 * (1.0 - t));
          final content = Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(
                scale: scale,
                child: inner,
              ),
            ),
          );
          if (blurSigma <= 0.05) return content;
          return Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: BackdropFilter(
                    filter:
                        ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
              ),
              content,
            ],
          );
        },
      );
    },
  );
}

/// Unified Silky Modal Bottom Sheet Engine.
///
/// Standardizes deceleration physics (`280ms` `Cubic(0.16, 1, 0.3, 1)`),
/// swipe-to-dismiss, safe areas, warm dark scrim, keyboard-safe insets, and
/// reduced motion support.
Future<T?> showHagzySheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useSafeArea = true,
  bool isScrollControlled = true,
  Color? barrierColor,
  Color? backgroundColor,
  ShapeBorder? shape,
  RouteSettings? routeSettings,
}) {
  final reduced = HagzyMotion.reduced(context);
  final defaultBarrier = kDarkMode.value
      ? Colors.black.withValues(alpha: 0.62)
      : const Color(0xFF0F0E0C).withValues(alpha: 0.42);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useSafeArea: useSafeArea,
    backgroundColor: backgroundColor ?? Colors.transparent,
    barrierColor: barrierColor ?? defaultBarrier,
    shape: shape,
    routeSettings: routeSettings,
    sheetAnimationStyle: reduced
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: HagzyMotion.durationSheetEnter,
            reverseDuration: HagzyMotion.durationSheetExit,
            curve: HagzyMotion.curveDialogEnter,
            reverseCurve: HagzyMotion.curveDialogExit,
          ),
    builder: builder,
  );
}

/// Platform-native & fluid page route: Cupertino swipe-back on iOS/macOS,
/// crisp ease-out slide + fade on Android/Web, instant when animations disabled.
Route<T> hagzyPageRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
}) {
  if (!kIsWeb &&
      !isHagzyTestRuntime &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    return CupertinoPageRoute<T>(builder: builder, settings: settings);
  }
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration:
        isHagzyTestRuntime ? Duration.zero : const Duration(milliseconds: 230),
    reverseTransitionDuration:
        isHagzyTestRuntime ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      if (HagzyMotion.reduced(context)) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: HagzyMotion.curveDialogEnter,
        reverseCurve: HagzyMotion.curveDialogExit,
      );
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.03),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// Spring-Damped Tactile Click & Press Feedback Wrapper (`65ms` press-in,
/// critically damped spring release, subtle opacity compression & desktop hover
/// tint, plus optional platform haptics).
///
/// Use [HagzyTap] directly around non-button containers/cards/pills/rows.
/// Do NOT attach duplicate `onTap` callbacks both here and on an inner
/// `FilledButton` or `InkWell`.
class HagzyTap extends StatefulWidget {
  const HagzyTap({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.965,
    this.pressedOpacity = 0.94,
    this.haptic = HagzyHapticStyle.light,
    this.enabled = true,
    this.behavior = HitTestBehavior.opaque,
    this.borderRadius,
    this.hoverColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final double pressedOpacity;
  final HagzyHapticStyle haptic;
  final bool enabled;
  final HitTestBehavior behavior;
  final BorderRadius? borderRadius;
  final Color? hoverColor;

  @override
  State<HagzyTap> createState() => _HagzyTapState();
}

class _HagzyTapState extends State<HagzyTap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  bool _hovered = false;

  bool get _hasAction =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  void _pressIn() {
    if (!mounted || !_hasAction || HagzyMotion.reduced(context)) return;
    _pressCtrl.animateTo(
      1.0,
      duration: HagzyMotion.durationPress,
      curve: HagzyMotion.curvePress,
    );
  }

  void _springOut() {
    if (!mounted) return;
    if (HagzyMotion.reduced(context)) {
      _pressCtrl.value = 0.0;
      return;
    }
    _pressCtrl.animateWith(
      SpringSimulation(HagzyMotion.releaseSpring, _pressCtrl.value, 0.0, 0.0),
    );
  }

  void _handleTap() {
    if (!_hasAction) return;
    HagzyHaptics.trigger(widget.haptic);
    widget.onTap?.call();
  }

  void _handleLongPress() {
    if (!widget.enabled || widget.onLongPress == null) return;
    HagzyHaptics.medium();
    widget.onLongPress?.call();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = HagzyMotion.reduced(context);
    if (!_hasAction) return widget.child;

    final resolvedHoverColor = widget.hoverColor ??
        (kDarkMode.value
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFF171614).withValues(alpha: 0.035));

    Widget content = widget.child;
    if (widget.borderRadius != null || widget.hoverColor != null) {
      content = AnimatedContainer(
        duration: HagzyMotion.durationMicro,
        curve: HagzyMotion.curveSnappy,
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          color: _hovered ? resolvedHoverColor : Colors.transparent,
        ),
        child: content,
      );
    }

    if (!reduced) {
      content = AnimatedBuilder(
        animation: _pressCtrl,
        child: content,
        builder: (context, child) {
          final t = _pressCtrl.value.clamp(0.0, 1.0);
          final scale = 1.0 - (1.0 - widget.scaleDown) * t;
          final opacity = 1.0 - (1.0 - widget.pressedOpacity) * t;
          return Opacity(
            opacity: opacity,
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          );
        },
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: GestureDetector(
        behavior: widget.behavior,
        onTapDown: (_) => _pressIn(),
        onTapUp: (_) => _springOut(),
        onTapCancel: _springOut,
        onTap: widget.onTap != null ? _handleTap : null,
        onLongPress: widget.onLongPress != null ? _handleLongPress : null,
        child: content,
      ),
    );
  }
}

/// Choreographed one-shot entrance animation (fade + directional slide + micro-scale).
///
/// Uses a single `AnimationController` with an `Interval` (zero `Future.delayed`
/// timers), and renders [child] immediately with zero animation cost when
/// [HagzyMotion.reduced] is true.
class HagzyReveal extends StatefulWidget {
  const HagzyReveal({
    super.key,
    required this.child,
    this.index = 0,
    this.stepMs = 40,
    this.durationMs = 280,
    this.slideOffset = const Offset(0, 10),
    this.scaleFrom = 0.985,
  });

  final Widget child;
  final int index;
  final int stepMs;
  final int durationMs;
  final Offset slideOffset;
  final double scaleFrom;

  @override
  State<HagzyReveal> createState() => _HagzyRevealState();
}

class _HagzyRevealState extends State<HagzyReveal>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  late final int _delayMs;

  @override
  void initState() {
    super.initState();
    _delayMs = (widget.index.clamp(0, 8)) * widget.stepMs;
    if (!isHagzyTestRuntime) {
      final totalMs = _delayMs + widget.durationMs;
      _ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: totalMs),
      )..forward();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null || HagzyMotion.reduced(context)) {
      return widget.child;
    }

    final totalMs = (_delayMs + widget.durationMs).toDouble();
    final start = totalMs > 0 ? (_delayMs / totalMs).clamp(0.0, 0.85) : 0.0;
    final anim = CurvedAnimation(
      parent: ctrl,
      curve: Interval(start, 1.0, curve: HagzyMotion.curveDialogEnter),
    );

    return AnimatedBuilder(
      animation: anim,
      child: widget.child,
      builder: (context, child) {
        final t = anim.value;
        final dx = widget.slideOffset.dx * (1.0 - t);
        final dy = widget.slideOffset.dy * (1.0 - t);
        final scale = widget.scaleFrom + (1.0 - widget.scaleFrom) * t;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(dx, dy),
            child: Transform.scale(
              scale: scale,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Tactile interactive wrapper providing desktop hover choreography + mobile
/// press physics (`70ms` down, `150ms` release) + optional haptics without
/// blocking child `InkWell` / `GestureDetector` taps.
class HagzyInteractiveSurface extends StatefulWidget {
  const HagzyInteractiveSurface({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.hoverLift = 1.5,
    this.pressScale = 0.975,
    this.haptic = HagzyHapticStyle.none,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final VoidCallback? onTap;
  final bool enabled;
  final double hoverLift;
  final double pressScale;
  final HagzyHapticStyle haptic;

  @override
  State<HagzyInteractiveSurface> createState() =>
      _HagzyInteractiveSurfaceState();
}

class _HagzyInteractiveSurfaceState extends State<HagzyInteractiveSurface> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduced = HagzyMotion.reduced(context);
    final active = widget.enabled;
    final lift = (!reduced && active && _hovered && !_pressed)
        ? -widget.hoverLift
        : 0.0;
    final scale = (!reduced && active && _pressed) ? widget.pressScale : 1.0;
    final pressDuration = _pressed
        ? HagzyMotion.durationPress
        : HagzyMotion.durationRelease;
    final pressCurve = _pressed
        ? HagzyMotion.curvePress
        : HagzyMotion.curveRelease;

    Widget content =
        widget.builder(context, active && _hovered, active && _pressed);

    if (!reduced) {
      content = AnimatedContainer(
        duration: HagzyMotion.durationRelease,
        curve: HagzyMotion.curveRelease,
        transform: Matrix4.translationValues(0, lift, 0),
        child: AnimatedScale(
          scale: scale,
          duration: pressDuration,
          curve: pressCurve,
          child: content,
        ),
      );
    }

    return MouseRegion(
      cursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: active ? (_) => setState(() => _hovered = true) : null,
      onExit: active ? (_) => setState(() => _hovered = false) : null,
      child: Listener(
        onPointerDown: active ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: active ? (_) => setState(() => _pressed = false) : null,
        onPointerCancel:
            active ? (_) => setState(() => _pressed = false) : null,
        child: widget.onTap != null && active
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  HagzyHaptics.trigger(widget.haptic);
                  widget.onTap?.call();
                },
                child: content,
              )
            : content,
      ),
    );
  }
}

/// Spatial-continuity equal-slot sliding selector.
///
/// Glides an active capsule physically across equal-width items in
/// both LTR and Arabic RTL layouts (`AnimatedPositionedDirectional`).
class HagzySlidingSelector extends StatelessWidget {
  const HagzySlidingSelector({
    super.key,
    required this.itemCount,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.indicatorDecoration,
    this.padding = const EdgeInsets.all(4),
    this.height,
    this.trackDecoration,
    this.duration = const Duration(milliseconds: 240),
    this.curve = HagzyMotion.curveDialogEnter,
  });

  final int itemCount;
  final int selectedIndex;
  final Widget Function(BuildContext context, int index, bool selected)
      itemBuilder;
  final BoxDecoration indicatorDecoration;
  final EdgeInsetsGeometry padding;
  final double? height;
  final BoxDecoration? trackDecoration;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final safeCount = math.max(1, itemCount);
    final safeIndex = selectedIndex.clamp(0, safeCount - 1);
    final reduced = HagzyMotion.reduced(context);

    return Container(
      height: height,
      padding: padding,
      decoration: trackDecoration,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / safeCount;
          final effectiveDuration = reduced ? Duration.zero : duration;

          return Stack(
            children: [
              AnimatedPositionedDirectional(
                duration: effectiveDuration,
                curve: curve,
                start: slotWidth * safeIndex,
                top: 0,
                bottom: 0,
                width: slotWidth,
                child: IgnorePointer(
                  child: DecoratedBox(decoration: indicatorDecoration),
                ),
              ),
              Row(
                crossAxisAlignment: height != null
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.center,
                children: List.generate(
                  safeCount,
                  (i) => Expanded(
                    child: itemBuilder(context, i, i == safeIndex),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Smooth rolling value transition for dynamic totals, headcounts, and KPIs.
class HagzyAnimatedValue extends StatelessWidget {
  const HagzyAnimatedValue({
    super.key,
    required this.valueKey,
    required this.child,
  });

  final Object valueKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (HagzyMotion.reduced(context)) return child;
    return AnimatedSwitcher(
      duration: HagzyMotion.durationSnappy,
      switchInCurve: HagzyMotion.curveDialogEnter,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (widget, anim) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: offset, child: widget),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<Object>(valueKey),
        child: child,
      ),
    );
  }
}

/// Custom-painted animated confirmation seal for Checkout Success & Instant Hold.
class HagzySuccessSeal extends StatefulWidget {
  const HagzySuccessSeal({
    super.key,
    this.size = 96,
  });

  final double size;

  @override
  State<HagzySuccessSeal> createState() => _HagzySuccessSealState();
}

class _HagzySuccessSealState extends State<HagzySuccessSeal>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    if (!isHagzyTestRuntime) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 720),
      )..forward();
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    if (ctrl == null || HagzyMotion.reduced(context)) {
      return SizedBox.square(
        dimension: widget.size,
        child: const CustomPaint(
          painter: _SuccessSealPainter(progress: 1.0),
        ),
      );
    }

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(
          painter: _SuccessSealPainter(progress: ctrl.value),
        ),
      ),
    );
  }
}

class _SuccessSealPainter extends CustomPainter {
  const _SuccessSealPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;

    // 1. Soft expanding confirmation halo
    final pulseT = ((progress - 0.18) / 0.82).clamp(0.0, 1.0);
    if (pulseT > 0 && pulseT < 0.99) {
      final ringPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - pulseT)
        ..color = kVermilion.withValues(alpha: 0.55 * (1.0 - pulseT));
      canvas.drawCircle(center, r + size.width * 0.14 * pulseT, ringPaint);
    }

    // 2. Dark medallion scaling cleanly
    final discT =
        HagzyMotion.curveDialogEnter.transform((progress / 0.48).clamp(0.0, 1.0));
    final discR = r * discT;
    canvas.drawCircle(
      center,
      discR,
      Paint()
        ..isAntiAlias = true
        ..color = kObsidian,
    );

    // 3. Brand Vermilion precision ring sweeping 360°
    final ringSweep = Curves.easeOutCubic
        .transform(((progress - 0.12) / 0.50).clamp(0.0, 1.0));
    if (ringSweep > 0.01) {
      final arcPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.04
        ..strokeCap = StrokeCap.round
        ..color = kVermilion;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: discR),
        -math.pi / 2,
        2 * math.pi * ringSweep,
        false,
        arcPaint,
      );
    }

    // 4. Clean white checkmark stroke trace
    final checkT = Curves.easeOutCubic
        .transform(((progress - 0.42) / 0.46).clamp(0.0, 1.0));
    if (checkT > 0.01) {
      final checkPath = Path()
        ..moveTo(center.dx - r * 0.34, center.dy + r * 0.02)
        ..lineTo(center.dx - r * 0.07, center.dy + r * 0.28)
        ..lineTo(center.dx + r * 0.38, center.dy - r * 0.22);

      final checkPaint = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.055
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;

      for (final metric in checkPath.computeMetrics()) {
        final seg = metric.extractPath(0, metric.length * checkT);
        canvas.drawPath(seg, checkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessSealPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
