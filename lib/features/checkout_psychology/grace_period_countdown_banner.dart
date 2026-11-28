import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';
import '../../theme/hagzy_theme.dart';

/// 10-Minute Free Cancellation Grace Period Countdown Banner
/// Gives zero-anxiety booking coordination on WhatsApp with instant Hagzy Wallet refunds
class GracePeriodCountdownBanner extends StatefulWidget {
  final HagzyBooking booking;
  final VoidCallback onCancelUnderGrace;
  final bool isArabic;

  const GracePeriodCountdownBanner({
    super.key,
    required this.booking,
    required this.onCancelUnderGrace,
    this.isArabic = false,
  });

  @override
  State<GracePeriodCountdownBanner> createState() =>
      _GracePeriodCountdownBannerState();
}

class _GracePeriodCountdownBannerState
    extends State<GracePeriodCountdownBanner> {
  Timer? _timer;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.booking.graceSecondsRemaining();
    if (_secondsLeft > 0) {
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        final remaining = widget.booking.graceSecondsRemaining();
        if (remaining <= 0) {
          t.cancel();
          if (mounted) setState(() => _secondsLeft = 0);
        } else {
          if (mounted) setState(() => _secondsLeft = remaining);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_secondsLeft <= 0 ||
        widget.booking.status != BookingStatus.confirmed) {
      return const SizedBox.shrink();
    }

    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final mins = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsLeft % 60).toString().padLeft(2, '0');
    final accent = isDark ? kGreenLight : kGreenDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0E241C) : kSurfaceTint,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.38 : 0.28),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.timer_outlined, color: accent, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.isArabic
                      ? 'فترة السماح المجانية: $mins:$secs'
                      : '10-Min Grace Period: $mins:$secs',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onCancelUnderGrace,
                style: TextButton.styleFrom(
                  foregroundColor: kError,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  widget.isArabic ? 'إلغاء واسترداد' : 'Cancel & Refund',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.isArabic
                ? 'نسق مع الشلة على واتساب براحتك! لو غيرتوا رأيكم خلال العد التنازلي، يُسترد العربون ١٠٠٪ فوراً في محفظة حجزي.'
                : 'Coordinate with your squad on WhatsApp! If plans change during the countdown, 100% of your deposit is refunded instantly to your Hagzy Wallet.',
            style: TextStyle(
              fontSize: 12.0,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.80)
                  : const Color(0xFF065F46),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
