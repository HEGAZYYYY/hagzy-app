import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';

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
          setState(() => _secondsLeft = 0);
        } else {
          setState(() => _secondsLeft = remaining);
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

    final mins = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final secs = (_secondsLeft % 60).toString().padLeft(2, '0');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F291E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.greenAccent.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.greenAccent.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.greenAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_outlined,
                  color: Colors.greenAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.isArabic
                      ? 'فترة السماح المجانية: $mins:$secs'
                      : '10-Min Grace Period: $mins:$secs',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              TextButton(
                onPressed: widget.onCancelUnderGrace,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  widget.isArabic ? 'إلغاء واسترداد' : 'Cancel & Refund',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            widget.isArabic
                ? 'نسق مع الشلة على واتساب براحتك! لو غيرتوا رأيكم خلال العد التنازلي، بيتم استرداد العربون ١٠٠٪ فوراً في رصيد محفظة حجزي.'
                : 'Coordinate with your squad on WhatsApp! If plans change during the countdown, 100% of your deposit is refunded instantly to your Hagzy Wallet.',
            style: TextStyle(
              fontSize: 11.5,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

