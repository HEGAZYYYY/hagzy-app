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
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
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
                      kGreen.withValues(alpha: 0.05),
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

/// Tactile press-to-scale physics wrapper inspired by Breadfast / Talabat.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
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

    return Listener(
      onPointerDown:
          widget.onTap != null ? (_) => setState(() => _pressed = true) : null,
      onPointerUp:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      onPointerCancel:
          widget.onTap != null ? (_) => setState(() => _pressed = false) : null,
      child: widget.onTap != null
          ? GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: widget.onTap,
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
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.45,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: kMuted,
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

class CustomPill extends StatelessWidget {
  const CustomPill({
    super.key,
    required this.label,
    this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: selected ? HagzyTheme.brandGradient : null,
            color: selected ? null : kPanel,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? kGreen : kBorder,
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
            padding:
                const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 16,
                        color: selected ? Colors.white : kGreen,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? Colors.white : kInk,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w700,
                          fontSize: 12.5,
                          letterSpacing: -0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
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

class FloatingDock extends StatelessWidget {
  const FloatingDock({
    super.key,
    required this.selectedIndex,
    required this.customerMode,
    required this.arabic,
    required this.onDestinationSelected,
    this.badgeCount = 0,
  });

  final int selectedIndex;
  final bool customerMode;
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
        : const [
            (Icons.explore_rounded, 'Explore'),
            (Icons.calendar_month_rounded, 'My Bookings'),
            (Icons.storefront_rounded, 'Manage Venues'),
            (Icons.account_balance_wallet_rounded, 'Payment Settings'),
            (Icons.person_rounded, 'Profile'),
          ];
    final localizedItems = items
        .map((item) => (
              item.$1,
              switch (item.$2) {
                'Explore' => localized(arabic, 'Explore', 'استكشف'),
                'My Bookings' => localized(arabic, 'My Bookings', 'حجوزاتي'),
                'Profile' => localized(arabic, 'Profile', 'حسابي'),
                'Manage Venues' =>
                  localized(arabic, 'Manage Venues', 'إدارة الأماكن'),
                'Payment Settings' =>
                  localized(arabic, 'Payment Settings', 'إعدادات الدفع'),
                _ => item.$2,
              },
            ))
        .toList();
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              height: 58,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: kPanel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: kBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: kInk.withValues(alpha: 0.09),
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
                                    color: selected ? Colors.white : kMuted,
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
                                    color: selected ? Colors.white : kMuted,
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
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.3,
                              color: kInk),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style: const TextStyle(
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
              color: enabled ? kPanel : const Color(0xFFF5F2EC),
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
                        : Colors.black.withValues(alpha: 0.04),
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
                          Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: enabled ? kInk : kMuted,
                              letterSpacing: -0.2,
                            ),
                          ),
                          if (badgeText != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                badgeText!,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: color,
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
                        style: const TextStyle(
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
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                          color: kInk)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
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
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: kInk)),
            const SizedBox(height: 6),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
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

/// Precision architectural assembling logo painter:
/// Draws the bespoke Hagzy "H" mark piece-by-piece:
/// 1. Left pillar draws downwards
/// 2. Right pillar draws downwards with subtle organic delay
/// 3. Stadium arch sweeps and bridges across, locking the emblem
/// 4. Diamond light gleam sweeps across the finished emblem
class _AssemblingHagzyLogoPainter extends CustomPainter {
  _AssemblingHagzyLogoPainter({
    required this.pillarProgress,
    required this.archProgress,
    required this.glowProgress,
    required this.shimmerProgress,
  });

  final double pillarProgress;
  final double archProgress;
  final double glowProgress;
  final double shimmerProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40.0;
    final rect = Offset.zero & size;

    // 1. Pristine architectural squircle canvas
    final bgPaint = Paint()
      ..isAntiAlias = true
      ..color = Colors.white;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(11 * scale));
    canvas.drawRRect(rrect, bgPaint);

    // 2. Monogram Paint Setup
    final strokeWidth = 3.8 * scale;
    final glyphPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0xFF059669);

    // 4. Assembling Left Vertical Pillar (draws top -> bottom: 11 to 29)
    if (pillarProgress > 0.01) {
      final startY = 11.0 * scale;
      final totalH = (29.0 - 11.0) * scale;
      final currentY = startY + totalH * pillarProgress.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(12.5 * scale, startY),
        Offset(12.5 * scale, currentY),
        glyphPaint,
      );
    }

    // 5. Assembling Right Vertical Pillar (draws top -> bottom with slight offset)
    if (pillarProgress > 0.08) {
      final adjustedProg = ((pillarProgress - 0.08) / 0.92).clamp(0.0, 1.0);
      final startY = 11.0 * scale;
      final totalH = (29.0 - 11.0) * scale;
      final currentY = startY + totalH * adjustedProg;
      canvas.drawLine(
        Offset(27.5 * scale, startY),
        Offset(27.5 * scale, currentY),
        glyphPaint,
      );
    }

    // 6. Assembling Stadium Arch Bridge (draws across from left to right)
    if (archProgress > 0.01) {
      final fullArchPath = Path()
        ..moveTo(12.5 * scale, 21 * scale)
        ..quadraticBezierTo(
          20.0 * scale,
          14.5 * scale,
          27.5 * scale,
          21 * scale,
        );

      final metrics = fullArchPath.computeMetrics().toList();
      if (metrics.isNotEmpty) {
        final metric = metrics.first;
        final extractLength = metric.length * archProgress.clamp(0.0, 1.0);
        final segment = metric.extractPath(0.0, extractLength);
        canvas.drawPath(segment, glyphPaint);
      }
    }

    // 7. Light Shimmer / Gleam Sweep over the assembled H
    if (shimmerProgress > 0.05 && shimmerProgress < 0.95) {
      canvas.save();
      canvas.clipRRect(rrect);
      final pos = -0.5 + shimmerProgress * 2.0;
      final shimmerPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment(pos - 0.5, -1.0),
          end: Alignment(pos + 0.5, 1.0),
          colors: [
            Colors.transparent,
            Colors.white.withValues(alpha: 0.65),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect);
      canvas.drawPaint(shimmerPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _AssemblingHagzyLogoPainter oldDelegate) {
    return oldDelegate.pillarProgress != pillarProgress ||
        oldDelegate.archProgress != archProgress ||
        oldDelegate.glowProgress != glowProgress ||
        oldDelegate.shimmerProgress != shimmerProgress;
  }
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

  // Assembling logo mechanics
  late final Animation<double> _containerScale;
  late final Animation<double> _containerOpacity;
  late final Animation<double> _pillarProgress;
  late final Animation<double> _archProgress;
  late final Animation<double> _glowProgress;
  late final Animation<double> _shimmerProgress;

  // Modern luxury typography
  late final Animation<double> _textSlide;
  late final Animation<double> _textOpacity;
  late final Animation<double> _sloganSlide;
  late final Animation<double> _sloganOpacity;

  // Cinematic exit
  late final Animation<double> _zoomExit;
  late final Animation<double> _overlayOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    // Subtle breathing ambient bloom in deep emerald
    _ambientBloom = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.15, end: 0.38)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.38, end: 0.28)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 50,
      ),
    ]).animate(_ctrl);

    // Squircle container slowly materializing
    _containerScale = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
      ),
    );
    _containerOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.22, curve: Curves.easeOut),
    );

    // Assembling left and right vertical pillars (16% -> 44%)
    _pillarProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.16, 0.44, curve: Curves.easeOutCubic),
    );

    // Assembling stadium arch bridge (30% -> 58%)
    _archProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.30, 0.58, curve: Curves.easeInOutCubic),
    );

    // Completion glow pulse (50% -> 72%)
    _glowProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.50, 0.72, curve: Curves.easeOut),
    );

    // Diamond light shimmer sweep across finished mark (58% -> 78%)
    _shimmerProgress = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.58, 0.78, curve: Curves.easeInOut),
    );

    // Clean modern title entrance (44% -> 66%)
    _textSlide = Tween<double>(begin: 14.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.44, 0.66, curve: Curves.easeOutCubic),
      ),
    );
    _textOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.44, 0.62, curve: Curves.easeOut),
    );

    // Slogan entrance (56% -> 78%)
    _sloganSlide = Tween<double>(begin: 10.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.56, 0.78, curve: Curves.easeOutCubic),
      ),
    );
    _sloganOpacity = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.56, 0.74, curve: Curves.easeOut),
    );

    // Cinematic zoom exit (82% -> 100%)
    _zoomExit = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.82, 1.0, curve: Curves.easeInOutCubic),
      ),
    );

    // Smooth cross-dissolve directly into the app
    _overlayOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.84, 1.0, curve: Curves.easeInOutCubic),
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
          return Opacity(
            opacity: _overlayOpacity.value,
            child: Transform.scale(
              scale: _zoomExit.value,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.12),
                      radius: 1.35,
                      colors: [
                        Color(0xFF065F46), // Radiant emerald center
                        Color(0xFF044E3B),
                        Color(0xFF022C22), // Deep luxury forest perimeter
                        Color(0xFF011A14), // Near obsidian edge
                      ],
                      stops: [0.0, 0.36, 0.76, 1.0],
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
                              const Color(0xFF34D399)
                                  .withValues(alpha: _ambientBloom.value),
                              const Color(0xFF10B981)
                                  .withValues(alpha: _ambientBloom.value * 0.4),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.45, 1.0],
                          ),
                        ),
                      ),
                      // 2. Central Hero Content (Zero rings, pure luxury assembling mark)
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Assembling Monogram Container
                            Opacity(
                              opacity: _containerOpacity.value,
                              child: Transform.scale(
                                scale: _containerScale.value,
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(27),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.32),
                                        blurRadius: 28,
                                        offset: const Offset(0, 12),
                                      ),
                                      BoxShadow(
                                        color: const Color(0xFF34D399)
                                            .withValues(
                                          alpha: 0.35 * _glowProgress.value,
                                        ),
                                        blurRadius: 36,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(27),
                                    child: CustomPaint(
                                      size: const Size(100, 100),
                                      painter: _AssemblingHagzyLogoPainter(
                                        pillarProgress: _pillarProgress.value,
                                        archProgress: _archProgress.value,
                                        glowProgress: _glowProgress.value,
                                        shimmerProgress: _shimmerProgress.value,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Clean Luxury Title (Montserrat for EN, Almarai for AR)
                            Opacity(
                              opacity: _textOpacity.value,
                              child: Transform.translate(
                                offset: Offset(0, _textSlide.value),
                                child: Text(
                                  widget.arabic ? 'حجزي' : 'Hagzy',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontFamily: widget.arabic
                                        ? 'Almarai'
                                        : 'Montserrat',
                                    fontFamilyFallback: widget.arabic
                                        ? const [
                                            'Tajawal',
                                            'Alexandria',
                                            'Cairo',
                                            'sans-serif'
                                          ]
                                        : const [
                                            'Poppins',
                                            'Plus Jakarta Sans',
                                            'Inter',
                                            'sans-serif'
                                          ],
                                    fontSize: widget.arabic ? 34 : 33,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing:
                                        widget.arabic ? 0.0 : 1.2,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Clean, Human Slogan (Plus Jakarta Sans for EN, Almarai for AR)
                            Opacity(
                              opacity: _sloganOpacity.value,
                              child: Transform.translate(
                                offset: Offset(0, _sloganSlide.value),
                                child: Text(
                                  widget.arabic
                                      ? 'احجز مكانك.. في ثواني'
                                      : 'Your spot, booked in seconds',
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.85),
                                    fontFamily: widget.arabic
                                        ? 'Almarai'
                                        : 'Plus Jakarta Sans',
                                    fontFamilyFallback: widget.arabic
                                        ? const [
                                            'Tajawal',
                                            'Alexandria',
                                            'Cairo',
                                            'sans-serif'
                                          ]
                                        : const [
                                            'Montserrat',
                                            'Poppins',
                                            'sans-serif'
                                          ],
                                    fontSize: widget.arabic ? 13.5 : 12.5,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing:
                                        widget.arabic ? 0.2 : 0.8,
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
