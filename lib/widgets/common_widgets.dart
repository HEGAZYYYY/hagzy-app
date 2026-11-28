import 'package:flutter/material.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import 'hagzy_brand.dart';
import 'hagzy_components.dart';
import 'hagzy_motion.dart';
export 'hagzy_brand.dart';
export 'hagzy_components.dart';
export 'hagzy_motion.dart';

bool get isRunningInTest => WidgetsBinding.instance.runtimeType
    .toString()
    .toLowerCase()
    .contains('test');

/// Sunlit Archival Paper (#F6F3EC) in light mode or Warm Charcoal Press
/// (#121110) in dark mode — clean, tactile, zero synthetic tech wallpaper.
class HagzyAmbientBackground extends StatelessWidget {
  const HagzyAmbientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: kPage,
      child: child,
    );
  }
}

/// Tactile press-to-scale physics wrapper (`70ms` down, `150ms` spring-like release,
/// subtle opacity shift, and platform-appropriate haptics).
class PressableScale extends StatelessWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleDown = 0.96,
    this.haptic = HagzyHapticStyle.light,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scaleDown;
  final HagzyHapticStyle haptic;

  @override
  Widget build(BuildContext context) {
    return HagzyTap(
      onTap: onTap,
      onLongPress: onLongPress,
      scaleDown: scaleDown,
      haptic: haptic,
      behavior: HitTestBehavior.translucent,
      child: child,
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
    if (ctrl == null || HagzyMotion.reduced(context)) {
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
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFD97706).withValues(alpha: 0.14)
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
        border: Border.all(
          color: isDark
              ? const Color(0xFFFBBF24).withValues(alpha: 0.35)
              : const Color(0xFFFED7AA),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: isDark ? const Color(0xFFFBBF24) : const Color(0xFFEA580C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Local preview mode · Data stays on this device. Configure HAGZY_API_URL to share venues and reservations across phones.',
              style: TextStyle(
                color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF9A3412),
                height: 1.4,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final arabic = isArabicMode;
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
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: arabic ? 0 : -0.4,
                  height: arabic ? 1.3 : 1.2,
                  color: isDark ? const Color(0xFFF8FAFC) : kInk,
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : kMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
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
    return HagzyTap(
      onTap: onTap,
      scaleDown: 0.96,
      haptic: HagzyHapticStyle.selection,
      child: AnimatedContainer(
        duration: HagzyTokens.durationFast,
        curve: HagzyTokens.curveStandard,
        constraints: const BoxConstraints(minHeight: 40),
        decoration: BoxDecoration(
          color: selected ? kAccentSurface : kPanel,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          border: Border.all(
            color: selected ? kAccentSurface : kBorder,
            width: 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected ? kAccentOnSurface : kMuted,
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? kAccentOnSurface : kInk,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 13,
                    letterSpacing: isArabicMode ? 0 : -0.05,
                  ),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected ? kVermilion : kSurfaceSubtle,
                    borderRadius: BorderRadius.circular(HagzyTokens.radiusFull),
                  ),
                  child: Text(
                    badge!,
                    style: hagzyMonoStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : kInk,
                      arabic: isArabicMode,
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
  Widget build(BuildContext context) => HagzyTap(
        onTap: onTap,
        scaleDown: 0.94,
        haptic: HagzyHapticStyle.selection,
        child: AnimatedContainer(
          duration: HagzyTokens.durationFast,
          curve: HagzyTokens.curveStandard,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 34),
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? kAccentSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall - 2),
          ),
          child: Text(
            label,
            style: hagzyMonoStyle(
              color: selected ? kAccentOnSurface : kMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
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
    this.color,
  });

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _VenueControlIconPainter(color: color ?? kGreen),
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
    this.singularPartner = false,
    required this.arabic,
    required this.onDestinationSelected,
    this.badgeCount = 0,
  });

  final int selectedIndex;
  final bool customerMode;
  final bool previewMode;
  final bool singularPartner;
  final bool arabic;
  final ValueChanged<int> onDestinationSelected;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final items = customerMode
        ? const [
            (Icons.explore_rounded, 'Explore'),
            (Icons.calendar_month_rounded, 'Bookings'),
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
                'Bookings' => localized(arabic, 'Bookings', 'حجوزاتي'),
                'Profile' => localized(arabic, 'Profile', 'حسابي'),
                'POS timeline' =>
                  localized(arabic, 'POS timeline', 'المواعيد ونقاط البيع'),
                'Manage Venues' => singularPartner
                    ? localized(arabic, 'My Venue', 'مكاني وملعبي')
                    : localized(arabic, 'Manage Venues', 'إدارة الأماكن والملاعب'),
                'Analytics' =>
                  localized(arabic, 'Analytics', 'الأرباح والتقارير'),
                'Payment Settings' =>
                  localized(arabic, 'Payment Settings', 'إعدادات الدفع'),
                _ => item.$2,
              },
            ))
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: HagzySlidingSelector(
              height: 60,
              padding: const EdgeInsets.all(5),
              itemCount: localizedItems.length,
              selectedIndex: selectedIndex,
              trackDecoration: BoxDecoration(
                color: kPanel,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusXLarge),
                border: Border.all(color: kBorder, width: 1.0),
                boxShadow: HagzyTheme.floatingShadow,
              ),
              indicatorDecoration: BoxDecoration(
                color: kSurfaceTint,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge - 1),
              ),
              itemBuilder: (context, index, selected) {
                final showBadge = index == 1 && badgeCount > 0;
                return HagzyTap(
                  scaleDown: 0.95,
                  haptic: HagzyHapticStyle.selection,
                  onTap: () => onDestinationSelected(index),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                localizedItems[index].$1,
                                size: 20,
                                color: selected ? kBrandAccent : kMuted,
                              ),
                              if (showBadge)
                                PositionedDirectional(
                                  end: -9,
                                  top: -6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: kVermilion,
                                      borderRadius: BorderRadius.circular(
                                          HagzyTokens.radiusFull),
                                    ),
                                    child: Text(
                                      '$badgeCount',
                                      style: hagzyMonoStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
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
                                color: selected ? kInk : kMuted,
                                fontSize: 12.5,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
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
  Widget build(BuildContext context) {
    final arabic = isArabicMode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: isCompleted ? kGreen.withValues(alpha: 0.32) : kBorder,
          width: isCompleted ? 1.3 : 1,
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
                AnimatedContainer(
                  duration: HagzyTokens.durationFast,
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: isCompleted ? kVermilion : kAccentSurface,
                    borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white)
                        : Text(
                            number,
                            style: hagzyMonoStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: arabic ? 0 : -0.25,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: kMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
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
    this.customLeadingIcon,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final String? badgeText;
  final Color? accentColor;
  final Widget? customLeadingIcon;
  final VoidCallback? onTap;

  Color get _resolvedAccent {
    if (accentColor != null) return accentColor!;
    final lower = title.toLowerCase();
    if (lower.contains('wallet') || lower.contains('محفظ')) {
      return kDarkMode.value ? kVolt : kObsidian;
    }
    if (lower.contains('instapay') || lower.contains('إنستاباي')) {
      return const Color(0xFF6B21A8);
    }
    if (lower.contains('vodafone')) {
      return const Color(0xFFE11D48);
    }
    if (lower.contains('paymob')) {
      return const Color(0xFF2563EB);
    }
    return const Color(0xFFD97706);
  }

  Color _brightenForDark(Color c) {
    final v = c.toARGB32();
    if (v == 0xFF171614 ||
        v == 0xFF0B0C0E ||
        v == 0xFF059669 ||
        v == 0xFF047857) {
      return kVermilionBright;
    }
    if (v == 0xFF6366F1 || v == 0xFF6B21A8 || v == 0xFF8B5CF6) {
      return const Color(0xFFA78BFA);
    }
    if (v == 0xFF2563EB || v == 0xFF1D4ED8) {
      return const Color(0xFF60A5FA);
    }
    if (v == 0xFFD97706 || v == 0xFFC26A1B) {
      return const Color(0xFFFBBF24);
    }
    if (v == 0xFFE11D48) {
      return const Color(0xFFFB7185);
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final baseColor = _resolvedAccent;
    final color = isDark ? _brightenForDark(baseColor) : baseColor;
    return HagzyInteractiveSurface(
      enabled: enabled,
      hoverLift: 1.5,
      pressScale: 0.985,
      builder: (context, hovered, _) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: enabled ? kPanel : kSurfaceSubtle,
              borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
              border: Border.all(
                color: enabled
                    ? (hovered
                        ? color.withValues(alpha: 0.65)
                        : color.withValues(alpha: isDark ? 0.35 : 0.25))
                    : kBorder,
                width: enabled ? (hovered ? 1.5 : 1.2) : 1,
              ),
              boxShadow: enabled ? HagzyTheme.subtleShadow : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: enabled
                        ? color.withValues(alpha: isDark ? 0.22 : 0.12)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(14),
                    border: isDark && enabled
                        ? Border.all(color: color.withValues(alpha: 0.35))
                        : null,
                  ),
                  child: Center(
                    child: customLeadingIcon ??
                        Icon(
                          icon,
                          color: enabled ? color : kMuted,
                          size: 24,
                        ),
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
                                  fontSize: 12.0,
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
                  child: enabled
                      ? HagzyDirectionalChevron(size: 17, color: color)
                      : Icon(
                          Icons.lock_outline_rounded,
                          size: 13,
                          color: kMuted,
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
  Widget build(BuildContext context) {
    final arabic = isArabicMode;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: kBorder, width: 1.0),
        ),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kSurfaceTint,
              borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
            ),
            child: Icon(icon, color: kBrandAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: hagzyDisplayStyle(
                    arabic: arabic,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: arabic ? 0 : -0.4,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[const SizedBox(width: 12), action!],
        ],
      ),
    );
  }
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
          borderRadius: BorderRadius.circular(HagzyTokens.radiusXLarge),
          border: Border.all(color: kBorder, width: 1.0),
          boxShadow: HagzyTheme.subtleShadow,
        ),
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            IconBox(icon: icon),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: hagzyDisplayStyle(
                    arabic: isArabicMode,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: isArabicMode ? 0 : -0.3,
                    color: kInk)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: kMuted, height: 1.45, fontWeight: FontWeight.w500)),
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: action,
                icon: Icon(actionIcon, size: 18, color: Colors.white),
                label: Text(actionLabel!),
                style: FilledButton.styleFrom(
                  backgroundColor: kAccentSurface,
                  foregroundColor: kAccentOnSurface,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(HagzyTokens.radiusMedium),
                  ),
                ),
              ),
            ],
            if (secondaryAction != null && secondaryActionLabel != null) ...[
              SizedBox(
                  height: (action != null && actionLabel != null) ? 10 : 18),
              (action == null || actionLabel == null)
                  ? FilledButton.icon(
                      onPressed: secondaryAction,
                      icon: Icon(secondaryIcon, size: 18),
                      label: Text(secondaryActionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentSurface,
                        foregroundColor: kAccentOnSurface,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusMedium),
                        ),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: secondaryAction,
                      icon: Icon(secondaryIcon, size: 18),
                      label: Text(secondaryActionLabel!),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kInk,
                        side: BorderSide(color: kBorder, width: 1.2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusMedium),
                        ),
                      ),
                    ),
            ],
            if (tertiaryAction != null && tertiaryActionLabel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: tertiaryAction,
                style: TextButton.styleFrom(
                  foregroundColor: kMuted,
                ),
                child: Text(
                  tertiaryActionLabel!,
                  style: const TextStyle(
                    fontSize: 13,
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
  const IconBox({super.key, required this.icon, this.color});
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final resolved = color ?? (isDark ? kVolt : kObsidian);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? resolved.withValues(alpha: 0.14)
            : kSurfaceSubtle,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
        border: Border.all(
          color: isDark ? resolved.withValues(alpha: 0.30) : kBorder,
        ),
      ),
      child: Icon(icon, color: resolved, size: 20),
    );
  }
}

/// Original Hagzy Locked-Aperture Logo Mark — delegates to [HagzyBrandSymbol].
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
    return HagzyBrandSymbol(
      size: size,
      variant: inverted ? HagzyBrandVariant.volt : HagzyBrandVariant.obsidian,
      withGlow: withGlow,
    );
  }
}

/// Editorial kinetic opening splash animation — delegates to [HagzyBrandSplashOverlay].
class HagzySplashOverlay extends StatelessWidget {
  const HagzySplashOverlay({
    super.key,
    required this.onDismiss,
    required this.arabic,
  });

  final VoidCallback onDismiss;
  final bool arabic;

  @override
  Widget build(BuildContext context) {
    return HagzyBrandSplashOverlay(
      onDismiss: onDismiss,
      arabic: arabic,
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
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!isRunningInTest) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1350),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = kDarkMode.value;
    final baseColor =
        isDark ? const Color(0xFF17171D) : const Color(0xFFE1E0D9);
    final highlightColor =
        isDark ? const Color(0xFF24242E) : const Color(0xFFF4F3EE);
    final ctrl = _controller;

    if (ctrl == null || HagzyMotion.reduced(context)) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: baseColor,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      );
    }

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final slide = ctrl.value * 2.0 - 0.5;
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(color: kBorder, width: 1.1),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HagzyShimmerBox(
            width: double.infinity,
            height: 176,
            borderRadius: 0,
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    HagzyShimmerBox(width: 170, height: 18, borderRadius: 6),
                    HagzyShimmerBox(width: 74, height: 22, borderRadius: 6),
                  ],
                ),
                SizedBox(height: 10),
                HagzyShimmerBox(width: 220, height: 13, borderRadius: 5),
                SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    HagzyShimmerBox(width: 100, height: 24, borderRadius: 6),
                    HagzyShimmerBox(width: 104, height: 34, borderRadius: 10),
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

