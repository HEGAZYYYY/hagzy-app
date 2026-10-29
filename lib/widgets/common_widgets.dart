import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';

bool get isRunningInTest => WidgetsBinding.instance.runtimeType
    .toString()
    .toLowerCase()
    .contains('test');

/// Clean, cohesive Alabaster & Soft Emerald ambient background.
class HagzyAmbientBackground extends StatelessWidget {
  const HagzyAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? const [
                      Color(0xFF0A1622),
                      Color(0xFF0B1120),
                      Color(0xFF0B1120),
                    ]
                  : const [
                      Color(0xFFF4FBF7),
                      Color(0xFFF8FAFC),
                      Color(0xFFF8FAFC),
                    ],
            ),
          ),
        ),
        Positioned(
          top: -120,
          right: -100,
          child: IgnorePointer(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    kGreen.withValues(alpha: isDark ? 0.12 : 0.05),
                    kGreen.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Tactile press-to-scale physics wrapper inspired by Breadfast / Talabat.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final content = AnimatedScale(
      scale: _pressed ? widget.scaleDown : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: widget.child,
    );

    final hasAction = widget.onTap != null || widget.onLongPress != null;

    return Listener(
      onPointerDown:
          hasAction ? (_) => setState(() => _pressed = true) : null,
      onPointerUp:
          hasAction ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          hasAction ? (_) => setState(() => _pressed = false) : null,
      child: hasAction
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              child: content,
            )
          : content,
    );
  }
}

/// Breathing live indicator dot that animates in real app runs and stays static in tests.
class LivePulseDot extends StatefulWidget {
  const LivePulseDot({
    super.key,
    this.color = kGreenLight,
    this.size = 8,
  });

  final Color color;
  final double size;

  @override
  State<LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<LivePulseDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!isRunningInTest) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _controller;
    if (ctrl == null) {
      return Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      );
    }
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final t = ctrl.value;
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55 * (1 - t * 0.5)),
                blurRadius: 4 + 6 * t,
                spreadRadius: 1.5 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class LocalPreviewNotice extends StatelessWidget {
  const LocalPreviewNotice({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFED7AA)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFFEA580C)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Local preview mode · Data stays on this device. Configure HAGZY_API_URL to share venues and reservations across phones.',
                style: TextStyle(
                  color: Color(0xFF9A3412),
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.45,
                  color: isDark ? const Color(0xFFF8FAFC) : kInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : kMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Renders a crisp vector icon in place of legacy in-app emojis.
class SystemEmoji extends StatelessWidget {
  const SystemEmoji(
    this.emoji, {
    super.key,
    this.size = 14,
    this.icon,
    this.color,
  });

  final String emoji;
  final double size;
  final IconData? icon;
  final Color? color;

  static IconData _resolveIcon(String key) {
    switch (key) {
      case 'barbers':
        return Icons.content_cut_rounded;
      case 'salons':
        return Icons.spa_rounded;
      case 'padel':
        return Icons.sports_tennis_rounded;
      case 'soccer':
        return Icons.sports_soccer_rounded;
      case 'playstation':
        return Icons.sports_esports_rounded;
      case 'billiards':
        return Icons.sports_baseball_rounded;
      case 'table_tennis':
        return Icons.sports_cricket_rounded;
      case 'escape_rooms':
        return Icons.vpn_key_rounded;
      default:
        return Icons.auto_awesome_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Icon(
      icon ?? _resolveIcon(emoji),
      size: size + 2,
      color: color ?? kGreen,
    );
  }
}

class CustomPill extends StatelessWidget {
  const CustomPill({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    this.badge,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return PressableScale(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: selected ? HagzyTheme.brandGradient : null,
          color: selected
              ? null
              : (isDark ? const Color(0xFF131C31) : kPanel),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? kGreen
                : (isDark ? const Color(0xFF283552) : kBorder),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: kGreen.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
                ]
              : [
                  BoxShadow(
                    color: kInk.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : (isDark ? kGreenLight : kGreen),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? Colors.white
                        : (isDark ? const Color(0xFFF8FAFC) : kInk),
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    fontSize: 12.5,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : (isDark ? kGreenLight : kGreen),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LanguageOption extends StatelessWidget {
  const LanguageOption({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        scaleDown: 0.92,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              gradient: selected ? HagzyTheme.brandGradient : null,
              color: selected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : kMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ),
      );
}

class HagzyThemeModeIcon extends StatelessWidget {
  const HagzyThemeModeIcon({
    super.key,
    required this.isDark,
    this.size = 20,
    this.color,
  });

  final bool isDark;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final activeColor =
        color ?? (isDark ? kGold : kGreen);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _ThemeModeIconPainter(
          isDark: isDark,
          color: activeColor,
        ),
      ),
    );
  }
}

class _ThemeModeIconPainter extends CustomPainter {
  _ThemeModeIconPainter({required this.isDark, required this.color});

  final bool isDark;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.36;

    if (isDark) {
      // Crescent Moon + Sparkle Star
      final moonPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: r));
      final cutout = Path()
        ..addOval(Rect.fromCircle(
          center: Offset(center.dx + r * 0.48, center.dy - r * 0.32),
          radius: r * 0.85,
        ));
      final crescent = Path.combine(PathOperation.difference, moonPath, cutout);
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawPath(crescent, fillPaint);

      // Small star in upper right
      final starCenter = Offset(center.dx + r * 0.55, center.dy - r * 0.45);
      final sr = size.width * 0.10;
      final starPaint = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(starCenter.dx - sr, starCenter.dy),
        Offset(starCenter.dx + sr, starCenter.dy),
        starPaint,
      );
      canvas.drawLine(
        Offset(starCenter.dx, starCenter.dy - sr),
        Offset(starCenter.dx, starCenter.dy + sr),
        starPaint,
      );
    } else {
      // Sun + 8 Rays
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, size.width * 0.22, fillPaint);

      final rayPaint = Paint()
        ..color = color
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round;
      final innerR = size.width * 0.31;
      final outerR = size.width * 0.44;
      const dirs = [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
        Offset(0.7071, 0.7071),
        Offset(-0.7071, 0.7071),
        Offset(0.7071, -0.7071),
        Offset(-0.7071, -0.7071),
      ];
      for (final d in dirs) {
        canvas.drawLine(
          Offset(center.dx + d.dx * innerR, center.dy + d.dy * innerR),
          Offset(center.dx + d.dx * outerR, center.dy + d.dy * outerR),
          rayPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ThemeModeIconPainter oldDelegate) =>
      oldDelegate.isDark != isDark || oldDelegate.color != color;
}

class HagzyVenueControlIcon extends StatelessWidget {
  const HagzyVenueControlIcon({
    super.key,
    this.size = 20,
    this.color = kGreen,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VenueControlIconPainter(color: color),
      ),
    );
  }
}

class _VenueControlIconPainter extends CustomPainter {
  _VenueControlIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final gap = w * 0.08;
    final boxW = (w - gap * 3) / 2;
    final boxH = (h - gap * 3) / 2;
    final radius = Radius.circular(w * 0.12);

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;

    // Top-left filled tile
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(gap, gap, boxW, boxH), radius),
      fillPaint,
    );
    // Top-right outlined tile
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(gap * 2 + boxW, gap, boxW, boxH), radius),
      strokePaint,
    );
    // Bottom-left outlined tile
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(gap, gap * 2 + boxH, boxW, boxH), radius),
      strokePaint,
    );
    // Bottom-right plus sign (Add/Control Venue)
    final cx = gap * 2 + boxW + boxW / 2;
    final cy = gap * 2 + boxH + boxH / 2;
    final arm = boxW * 0.38;
    final plusPaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), plusPaint);
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), plusPaint);
  }

  @override
  bool shouldRepaint(covariant _VenueControlIconPainter oldDelegate) =>
      oldDelegate.color != color;
}

class FloatingDock extends StatelessWidget {
  const FloatingDock({
    super.key,
    required this.selectedIndex,
    required this.customerMode,
    this.previewMode = false,
    required this.arabic,
    required this.onDestinationSelected,
    this.badgeCount = 0,
  });

  final int selectedIndex;
  final bool customerMode;
  final bool previewMode;
  final bool arabic;
  final ValueChanged<int> onDestinationSelected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final items = customerMode
        ? const [
            (Icons.explore_rounded, 'Explore'),
            (Icons.calendar_month_rounded, 'My Bookings'),
            (Icons.person_rounded, 'Profile'),
          ]
        : previewMode
            ? const [
                (Icons.explore_rounded, 'Explore'),
                (Icons.storefront_rounded, 'Manage Venues'),
                (Icons.view_timeline_rounded, 'POS timeline'),
                (Icons.insights_rounded, 'Analytics'),
                (Icons.account_balance_wallet_rounded, 'Payment Settings'),
              ]
            : const [
                (Icons.view_timeline_rounded, 'POS timeline'),
                (Icons.storefront_rounded, 'Manage Venues'),
                (Icons.insights_rounded, 'Analytics'),
                (Icons.account_balance_wallet_rounded, 'Payment Settings'),
              ];
    final localizedItems = items
        .map((item) => (
              item.$1,
              switch (item.$2) {
                'Explore' => localized(arabic, 'Explore', 'استكشف'),
                'My Bookings' => localized(arabic, 'My Bookings', 'حجوزاتي'),
                'Profile' => localized(arabic, 'Profile', 'حسابي'),
                'POS timeline' =>
                  localized(arabic, 'POS timeline', 'المواعيد ونقاط البيع'),
                'Manage Venues' =>
                  localized(arabic, 'Manage Venues', 'إدارة الأماكن والملاعب'),
                'Analytics' =>
                  localized(arabic, 'Analytics', 'الأرباح والتقارير'),
                'Payment Settings' =>
                  localized(arabic, 'Payment Settings', 'إعدادات الدفع'),
                _ => item.$2,
              },
            ))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Builder(builder: (context) {
              final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
              return Container(
                height: 58,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF131C31) : kPanel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: isDark ? const Color(0xFF283552) : kBorder,
                      width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? Colors.black : kInk)
                          .withValues(alpha: isDark ? 0.35 : 0.09),
                      blurRadius: 24,
                      spreadRadius: -2,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: List.generate(localizedItems.length, (index) {
                    final selected = selectedIndex == index;
                    final showBadge = index == 1 && badgeCount > 0;
                    return Expanded(
                      child: PressableScale(
                        scaleDown: 0.96,
                        onTap: () => onDestinationSelected(index),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () => onDestinationSelected(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected ? kGreen : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: kGreen.withValues(alpha: 0.35),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Icon(
                                      localizedItems[index].$1,
                                      size: 19,
                                      color: selected
                                          ? Colors.white
                                          : (isDark ? const Color(0xFF94A3B8) : kMuted),
                                    ),
                                    if (showBadge)
                                      Positioned(
                                        right: -7,
                                        top: -5,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? Colors.white
                                                : kGreen,
                                            borderRadius:
                                                BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '$badgeCount',
                                            style: TextStyle(
                                              color: selected
                                                  ? kGreen
                                                  : Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    localizedItems[index].$2,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : (isDark ? const Color(0xFF94A3B8) : kMuted),
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class StepPanel extends StatelessWidget {
  const StepPanel({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.isCompleted = false,
  });
  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isCompleted ? kGreen.withValues(alpha: 0.28) : kBorder,
            width: isCompleted ? 1.4 : 1,
          ),
          boxShadow: HagzyTheme.softShadow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      gradient: isCompleted
                          ? HagzyTheme.brandGradient
                          : HagzyTheme.coralGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check_rounded,
                              size: 16, color: Colors.white)
                          : Text(
                              number,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: kInk),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: TextStyle(
                                color: kMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 15),
              child,
            ],
          ),
        ),
      );
}

class PaymentMethodTile extends StatelessWidget {
  const PaymentMethodTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = false,
    this.badgeText,
    this.accentColor,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? badgeText;
  final Color? accentColor;
  final VoidCallback? onTap;

  Color get _resolvedAccent =>
      accentColor ??
      switch (title.toLowerCase()) {
        'instapay' => const Color(0xFF6B21A8),
        'vodafone cash' => const Color(0xFFE11D48),
        'paymob' => const Color(0xFF2563EB),
        _ => const Color(0xFFD97706),
      };

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final color = _resolvedAccent;
    return PressableScale(
      onTap: enabled ? onTap : null,
      scaleDown: 0.98,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: enabled
                  ? kPanel
                  : (isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF5F2EC)),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: enabled ? color.withValues(alpha: 0.25) : kBorder,
                width: enabled ? 1.3 : 1,
              ),
              boxShadow: enabled ? HagzyTheme.softShadow : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: 0.12)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    color: enabled ? color : kMuted,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: enabled ? kInk : kMuted,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: enabled
                                    ? color.withValues(alpha: 0.12)
                                    : kMuted.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText!,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: enabled ? color : kMuted,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: kMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.04),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    enabled
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.lock_outline_rounded,
                    size: 13,
                    color: enabled ? color : kMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class IntroCard extends StatelessWidget {
  const IntroCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kBorder),
          boxShadow: HagzyTheme.softShadow,
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            IconBox(icon: icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: kInk)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: kMuted,
                          height: 1.35,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            if (action != null) ...[const SizedBox(width: 12), action!],
          ],
        ),
      );
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
    this.actionIcon = Icons.add_business_outlined,
    this.secondaryAction,
    this.secondaryActionLabel,
    this.secondaryIcon = Icons.location_on_outlined,
    this.tertiaryAction,
    this.tertiaryActionLabel,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? secondaryAction;
  final String? secondaryActionLabel;
  final IconData secondaryIcon;
  final VoidCallback? tertiaryAction;
  final String? tertiaryActionLabel;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: kBorder),
          boxShadow: HagzyTheme.softShadow,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            IconBox(icon: icon),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: kInk)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: kMuted, height: 1.4, fontWeight: FontWeight.w600)),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: action,
                icon: Icon(actionIcon),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
            if (secondaryAction != null && secondaryActionLabel != null) ...[
              SizedBox(height: (action != null && actionLabel != null) ? 10 : 18),
              (action == null || actionLabel == null)
                  ? FilledButton.icon(
                      onPressed: secondaryAction,
                      icon: Icon(secondaryIcon, size: 18),
                      label: Text(secondaryActionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: kGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: secondaryAction,
                      icon: Icon(secondaryIcon, size: 18),
                      label: Text(secondaryActionLabel!),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGreen,
                        side: const BorderSide(color: kGreen, width: 1.4),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ],
            if (tertiaryAction != null && tertiaryActionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: tertiaryAction,
                style: TextButton.styleFrom(
                  foregroundColor: kGreen,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  tertiaryActionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

class IconBox extends StatelessWidget {
  const IconBox({super.key, required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              kGreen.withValues(alpha: 0.14),
              kGreenLight.withValues(alpha: 0.10),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGreen.withValues(alpha: 0.16)),
        ),
        child: Icon(icon, color: kGreen, size: 22),
      );
}

/// Original Hagzy Logo Mark — Architectural "H" monogram with stadium arch.
class HagzyLogoMark extends StatelessWidget {
  const HagzyLogoMark({
    super.key,
    this.size = 40,
    this.withGlow = false,
    this.inverted = false,
  });

  final double size;
  final bool withGlow;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final radius = 11.0 * (size / 40.0);
    final mark = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _HagzyLogoPainter(inverted: inverted)),
      ),
    );
    if (!withGlow) return mark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (inverted ? Colors.black : const Color(0xFF059669))
                .withValues(alpha: inverted ? 0.18 : 0.25),
            blurRadius: size * 0.28,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _HagzyLogoPainter extends CustomPainter {
  _HagzyLogoPainter({this.inverted = false});

  final bool inverted;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    final paint = Paint()..isAntiAlias = true;
    final rect = Offset.zero & size;

    // 1. Sleek squircle background (zero white corners!)
    if (inverted) {
      paint.color = Colors.white;
    } else {
      paint.shader = const LinearGradient(
        colors: [Color(0xFF047857), Color(0xFF059669)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    }

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(11 * scale));
    canvas.drawRRect(rrect, paint);

    // 2. Bold, bespoke architectural "H" monogram with dynamic stadium arch
    final glyphPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = inverted ? const Color(0xFF059669) : Colors.white;

    // Left vertical pillar
    canvas.drawLine(
      Offset(12.5 * scale, 11 * scale),
      Offset(12.5 * scale, 29 * scale),
      glyphPaint,
    );

    // Right vertical pillar
    canvas.drawLine(
      Offset(27.5 * scale, 11 * scale),
      Offset(27.5 * scale, 29 * scale),
      glyphPaint,
    );

    // Dynamic architectural stadium arch bridge
    final archPath = Path()
      ..moveTo(12.5 * scale, 21 * scale)
      ..quadraticBezierTo(
        20 * scale,
        14.5 * scale,
        27.5 * scale,
        21 * scale,
      );
    canvas.drawPath(archPath, glyphPaint);
  }

  @override
  bool shouldRepaint(covariant _HagzyLogoPainter oldDelegate) =>
      oldDelegate.inverted != inverted;
}

/// Precision architectural wordmark painter constructed from the EXACT geometry
/// of the official Hagzy logo (assets/hagzy_logo.svg):
/// - Stroke width = 24.32 / 256
/// - Rounded line caps & joins (StrokeCap.round, StrokeJoin.round)
/// - Identical stadium arch quadratic beziers
/// - Sequential mechanical line-drawing assembly
class _ExactLogoWordmarkPainter extends CustomPainter {
  _ExactLogoWordmarkPainter({
    required this.hProgress,
    required this.aProgress,
    required this.gProgress,
    required this.zProgress,
    required this.yProgress,
  });

  final double hProgress;
  final double aProgress;
  final double gProgress;
  final double zProgress;
  final double yProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / 256.0;
    final strokeWidth = 24.32 * scale;

    // Unified stadium pill paint: soft rounded caps & joins matching official logo H
    final glyphPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    // ----------------------------------------------------
    // 1. LETTER [ H ] (X: 80 -> 176) - Exactly matches hagzy_logo.svg
    // ----------------------------------------------------
    if (hProgress > 0.01) {
      // Left pillar (80, 70.4) -> (80, 185.6)
      _drawLineSegment(
        canvas,
        Offset(80.0 * scale, 70.4 * scale),
        Offset(80.0 * scale, 185.6 * scale),
        (hProgress / 0.45).clamp(0.0, 1.0),
        glyphPaint,
      );

      // Right pillar (176, 70.4) -> (176, 185.6)
      if (hProgress > 0.15) {
        _drawLineSegment(
          canvas,
          Offset(176.0 * scale, 70.4 * scale),
          Offset(176.0 * scale, 185.6 * scale),
          ((hProgress - 0.15) / 0.45).clamp(0.0, 1.0),
          glyphPaint,
        );
      }

      // Arch bridge (80, 134.4) Q (128, 92.8) (176, 134.4)
      if (hProgress > 0.40) {
        final archPath = Path()
          ..moveTo(80.0 * scale, 134.4 * scale)
          ..quadraticBezierTo(
            128.0 * scale,
            92.8 * scale,
            176.0 * scale,
            134.4 * scale,
          );
        _drawSegment(
          canvas,
          archPath,
          ((hProgress - 0.40) / 0.60).clamp(0.0, 1.0),
          glyphPaint,
        );
      }
    }

    // ----------------------------------------------------
    // 2. LETTER [ A ] (X: 208 -> 320, Apex 264, Wide Inner Triangle)
    // ----------------------------------------------------
    if (aProgress > 0.01) {
      // Continuous architectural legs with wider stance for open inner counter
      final aPath = Path()
        ..moveTo(208.0 * scale, 185.6 * scale)
        ..lineTo(264.0 * scale, 70.4 * scale)
        ..lineTo(320.0 * scale, 185.6 * scale);

      _drawSegment(
        canvas,
        aPath,
        (aProgress / 0.65).clamp(0.0, 1.0),
        glyphPaint,
      );

      // Wider, perfectly placed crossbar opening up the middle triangle
      if (aProgress > 0.45) {
        _drawLineSegment(
          canvas,
          Offset(235.0 * scale, 146.0 * scale),
          Offset(293.0 * scale, 146.0 * scale),
          ((aProgress - 0.45) / 0.55).clamp(0.0, 1.0),
          glyphPaint,
        );
      }
    }

    // ----------------------------------------------------
    // 3. LETTER [ G ] (Pure Geometric Circular Bottom, R=57.6, Center 392, 128)
    // ----------------------------------------------------
    if (gProgress > 0.01) {
      final cx = 392.0 * scale;
      final cy = 128.0 * scale;
      final r = 57.6 * scale;
      final k = 31.8116 * scale; // r * 0.552285 for exact circle

      final gPath = Path()
        // 1. Top-right terminal with smooth stadium cap
        ..moveTo(434.0 * scale, 89.0 * scale)
        // 2. Smoothly curve into top circular tangent
        ..cubicTo(
          424.0 * scale,
          70.4 * scale,
          408.0 * scale,
          70.4 * scale,
          cx,
          70.4 * scale,
        )
        // 3. Top-to-left quadrant (pure circle)
        ..cubicTo(
          cx - k,
          70.4 * scale,
          cx - r,
          cy - k,
          cx - r,
          cy,
        )
        // 4. Left-to-bottom quadrant (pure circle)
        ..cubicTo(
          cx - r,
          cy + k,
          cx - k,
          cy + r,
          cx,
          cy + r,
        )
        // 5. Bottom-to-right quadrant (100% PURE CIRCULAR BOWL)
        ..cubicTo(
          cx + k,
          cy + r,
          cx + r,
          cy + k,
          cx + r,
          cy,
        )
        // 6. Horizontal inward crossbar straight to center
        ..lineTo(cx, cy);

      _drawSegment(canvas, gPath, gProgress.clamp(0.0, 1.0), glyphPaint);
    }

    // ----------------------------------------------------
    // 4. LETTER [ Z ] (X: 476 -> 572)
    // ----------------------------------------------------
    if (zProgress > 0.01) {
      // Continuous smooth stadium path with elegant rounded corners
      final zPath = Path()
        ..moveTo(476.0 * scale, 70.4 * scale)
        ..lineTo(572.0 * scale, 70.4 * scale)
        ..lineTo(476.0 * scale, 185.6 * scale)
        ..lineTo(572.0 * scale, 185.6 * scale);

      _drawSegment(canvas, zPath, zProgress.clamp(0.0, 1.0), glyphPaint);
    }

    // ----------------------------------------------------
    // 5. LETTER [ Y ] (X: 608 -> 704, Center 656)
    // ----------------------------------------------------
    if (yProgress > 0.01) {
      // Continuous left arm down into the vertical stem with smooth rounded join
      final yStemPath = Path()
        ..moveTo(608.0 * scale, 70.4 * scale)
        ..lineTo(656.0 * scale, 134.4 * scale)
        ..lineTo(656.0 * scale, 185.6 * scale);

      _drawSegment(
        canvas,
        yStemPath,
        (yProgress / 0.70).clamp(0.0, 1.0),
        glyphPaint,
      );

      // Right arm branching in smoothly to the junction
      if (yProgress > 0.15) {
        _drawLineSegment(
          canvas,
          Offset(704.0 * scale, 70.4 * scale),
          Offset(656.0 * scale, 134.4 * scale),
          ((yProgress - 0.15) / 0.55).clamp(0.0, 1.0),
          glyphPaint,
        );
      }
    }
  }

  void _drawLineSegment(
    Canvas canvas,
    Offset p1,
    Offset p2,
    double progress,
    Paint paint,
  ) {
    if (progress <= 0.0) return;
    final p = progress.clamp(0.0, 1.0);
    final current = Offset(
      p1.dx + (p2.dx - p1.dx) * p,
      p1.dy + (p2.dy - p1.dy) * p,
    );
    canvas.drawLine(p1, current, paint);
  }

  void _drawSegment(Canvas canvas, Path path, double progress, Paint paint) {
    if (progress <= 0.0) return;
    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      final extractLength = metric.length * progress.clamp(0.0, 1.0);
      if (extractLength > 0.0) {
        final seg = metric.extractPath(0.0, extractLength);
        canvas.drawPath(seg, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExactLogoWordmarkPainter oldDelegate) {
    return oldDelegate.hProgress != hProgress ||
        oldDelegate.aProgress != aProgress ||
        oldDelegate.gProgress != gProgress ||
        oldDelegate.zProgress != zProgress ||
        oldDelegate.yProgress != yProgress;
  }
}

/// Diamond light gleam that sweeps across the entire unified expanding box
class _ShimmerGleamPainter extends CustomPainter {
  _ShimmerGleamPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01 || progress >= 0.99) return;
    final rect = Offset.zero & size;
    final pos = -0.6 + progress * 2.2;
    final shimmerPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment(pos - 0.35, -1.0),
        end: Alignment(pos + 0.35, 1.0),
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.38),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, shimmerPaint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerGleamPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

/// Luxury Opus-grade opening splash animation:
/// Deep architectural emerald gradient canvas with breathing ambient bloom,
/// progressive mechanical/architectural assembly of the "H" monogram,
/// bespoke luxury typography, and smooth cinematic cross-dissolve exit.
class HagzySplashOverlay extends StatefulWidget {
  const HagzySplashOverlay({
    super.key,
    required this.onDismiss,
    required this.arabic,
  });

  final VoidCallback onDismiss;
  final bool arabic;

  @override
  State<HagzySplashOverlay> createState() => _HagzySplashOverlayState();
}

class _HagzySplashOverlayState extends State<HagzySplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Background and ambient atmosphere
  late final Animation<double> _ambientBloom;

  // Squircle container intro
  late final Animation<double> _containerScale;
  late final Animation<double> _containerOpacity;

  // Letter H stroke assembly (matches official logo vector)
  late final Animation<double> _hProgress;

  // Horizontal expansion of the unified emerald plaque
  late final Animation<double> _expandWidth;

  // Progressive vector drawing for A, G, Z, Y matching the logo H
  late final Animation<double> _aProgress;
  late final Animation<double> _gProgress;
  late final Animation<double> _zProgress;
  late final Animation<double> _yProgress;

  // Completion glow pulse
  late final Animation<double> _glowProgress;

  // Diamond light shimmer sweep across the ENTIRE completed plaque
  late final Animation<double> _shimmerProgress;

  // Slogan Liquid wipe and fade
  late final Animation<double> _sloganWipe;
  late final Animation<double> _sloganOpacity;

  // Cinematic exit
  late final Animation<double> _zoomExit;
  late final Animation<double> _overlayOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3100),
    );

    // Subtle breathing ambient bloom in deep emerald
    _ambientBloom = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.16, end: 0.38)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.38, end: 0.24)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 55,
      ),
    ]).animate(_ctrl);

    // Squircle container smoothly materializing (0% -> 20%)
    _containerScale = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.20, curve: Curves.easeOutCubic),
      ),
    );
    _containerOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.15, curve: Curves.easeOut),
    );

    // Assembling letter H monogram (6% -> 30%)
    _hProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.06, 0.30, curve: Curves.easeOutCubic),
    );

    // The unified emerald box smoothly expands horizontally (30% -> 60%)
    _expandWidth = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.30, 0.60, curve: Curves.easeOutCubic),
    );

    // Sequential mechanical assembly for A, G, Z, Y in the EXACT same logo style:
    // Letter A (34% -> 46%)
    _aProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.34, 0.46, curve: Curves.easeOutCubic),
    );

    // Letter G (42% -> 54%)
    _gProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.42, 0.54, curve: Curves.easeOutCubic),
    );

    // Letter Z (50% -> 62%)
    _zProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.50, 0.62, curve: Curves.easeOutCubic),
    );

    // Letter Y (58% -> 70%)
    _yProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.58, 0.70, curve: Curves.easeOutCubic),
    );

    // Completion glow pulse (55% -> 75%)
    _glowProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.55, 0.75, curve: Curves.easeOut),
    );

    // Diamond light shimmer sweep across the ENTIRE completed plaque (68% -> 84%)
    _shimmerProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.68, 0.84, curve: Curves.easeInOut),
    );

    // Liquid light gradient reveal for Slogan underneath (68% -> 88%)
    _sloganWipe = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.68, 0.88, curve: Curves.easeOutCubic),
    );
    _sloganOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.68, 0.80, curve: Curves.easeOut),
    );

    // Cinematic zoom exit (90% -> 100%)
    _zoomExit = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.90, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    // Smooth cross-dissolve directly into the app (92% -> 100%)
    _overlayOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.92, 1.0, curve: Curves.easeInOutCubic),
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
    return GestureDetector(
      onTap: widget.onDismiss,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final sloganText = widget.arabic
              ? 'احجز مكانك.. في ثواني'
              : 'YOUR SPOT, BOOKED IN SECONDS';

          final sloganStyle = TextStyle(
            color: Colors.white.withValues(alpha: 0.70),
            fontFamily: widget.arabic ? 'Almarai' : 'Plus Jakarta Sans',
            fontFamilyFallback: widget.arabic
                ? const ['Alexandria', 'Tajawal', 'sans-serif']
                : const ['Montserrat', 'Inter', 'sans-serif'],
            fontSize: widget.arabic ? 12.5 : 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: widget.arabic ? 0.6 : 2.8,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          );

          // Box geometry: 58px high, starts 58px square, expands to 178px wide
          const boxHeight = 58.0;
          const initialWidth = 58.0;
          const finalWidth = 178.0;
          final currentWidth =
              initialWidth + (finalWidth - initialWidth) * _expandWidth.value;

          return Opacity(
            opacity: _overlayOpacity.value,
            child: Transform.scale(
              scale: _zoomExit.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.15),
                      radius: 1.35,
                      colors: [
                        Color(0xFF042F24), // Radiant deep emerald center
                        Color(0xFF021B14),
                        Color(0xFF010A07), // Deep velvet obsidian edge
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Soft atmospheric bloom in deep emerald (breathes smoothly)
                      Container(
                        width: 320,
                        height: 320,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              const Color(0xFF10B981)
                                   .withValues(alpha: _ambientBloom.value),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.70],
                          ),
                        ),
                      ),
                      // 2. Central Hero Content:
                      // Unified Box starts 58x58 square containing assembling [ H ],
                      // then smoothly expands into full emerald plaque where A, G, Z, Y
                      // assemble in the exact same vector style with matching diamond gleam!
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Opacity(
                              opacity: _containerOpacity.value,
                              child: Transform.scale(
                                scale: _containerScale.value,
                                child: Container(
                                  width: currentWidth,
                                  height: boxHeight,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(14.5),
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF047857),
                                        Color(0xFF059669)
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    border: Border.all(
                                      color: Colors.white
                                          .withValues(alpha: 0.22),
                                      width: 1.2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.40),
                                        blurRadius: 22,
                                        offset: const Offset(0, 8),
                                      ),
                                      BoxShadow(
                                        color: const Color(0xFF059669)
                                            .withValues(
                                          alpha:
                                              0.38 * _glowProgress.value,
                                        ),
                                        blurRadius: 30,
                                        spreadRadius: -1,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14.5),
                                    child: Stack(
                                      alignment: Alignment.centerLeft,
                                      children: [
                                        // Architectural vector wordmark painted on canvas
                                        CustomPaint(
                                          size: Size(currentWidth, boxHeight),
                                          painter: _ExactLogoWordmarkPainter(
                                            hProgress: _hProgress.value,
                                            aProgress: _aProgress.value,
                                            gProgress: _gProgress.value,
                                            zProgress: _zProgress.value,
                                            yProgress: _yProgress.value,
                                          ),
                                        ),
                                        // Diamond light gleam sweeping across the entire plaque!
                                        if (_shimmerProgress.value > 0.01 &&
                                            _shimmerProgress.value < 0.99)
                                          Positioned.fill(
                                            child: CustomPaint(
                                              painter: _ShimmerGleamPainter(
                                                progress:
                                                    _shimmerProgress.value,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Slogan Liquid Wipe in clean geometric tracked-out typography
                            Opacity(
                              opacity: _sloganOpacity.value,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 24),
                                child: ShaderMask(
                                  blendMode: BlendMode.dstIn,
                                  shaderCallback: (Rect bounds) {
                                    final t = _sloganWipe.value;
                                    final start =
                                        (t * 1.30 - 0.30).clamp(0.0, 1.0);
                                    final end = (t * 1.30).clamp(0.0, 1.0);
                                    return LinearGradient(
                                      begin: widget.arabic
                                          ? Alignment.centerRight
                                          : Alignment.centerLeft,
                                      end: widget.arabic
                                          ? Alignment.centerLeft
                                          : Alignment.centerRight,
                                      colors: const [
                                        Colors.white,
                                        Colors.white,
                                        Colors.transparent,
                                        Colors.transparent,
                                      ],
                                      stops: [0.0, start, end, 1.0],
                                    ).createShader(bounds);
                                  },
                                  child: Text(
                                    sloganText,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: sloganStyle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HagzyShimmerBox extends StatefulWidget {
  const HagzyShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 12,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<HagzyShimmerBox> createState() => _HagzyShimmerBoxState();
}

class _HagzyShimmerBoxState extends State<HagzyShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = kDarkMode.value;
    final baseColor =
        isDark ? const Color(0xFF19243D) : const Color(0xFFE2E8F0);
    final highlightColor =
        isDark ? const Color(0xFF283552) : const Color(0xFFF8FAFC);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final slide = _controller.value * 2.0 - 0.5;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(-1.0 + slide, -0.2),
              end: Alignment(0.2 + slide, 0.2),
              colors: [baseColor, highlightColor, baseColor],
              stops: const [0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}

class VenueCardSkeleton extends StatelessWidget {
  const VenueCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = kDarkMode.value;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C31) : kPanel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? const Color(0xFF283552) : kBorder,
        ),
        boxShadow: HagzyTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HagzyShimmerBox(
            width: double.infinity,
            height: 162,
            borderRadius: 0,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 15, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    HagzyShimmerBox(width: 170, height: 18, borderRadius: 6),
                    HagzyShimmerBox(width: 84, height: 22, borderRadius: 999),
                  ],
                ),
                SizedBox(height: 10),
                HagzyShimmerBox(width: 220, height: 13, borderRadius: 5),
                SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    HagzyShimmerBox(width: 100, height: 24, borderRadius: 8),
                    HagzyShimmerBox(width: 110, height: 34, borderRadius: 999),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

