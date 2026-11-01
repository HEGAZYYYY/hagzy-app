import 'package:flutter/material.dart';

/// Merchant "Hagzy Pro" Upsell Banner Enforcing Principle 5 (Loss Aversion Framing)
class MerchantLossAversionBanner extends StatelessWidget {
  final double estimatedLostRevenueEgp;
  final int noShowCount;
  final VoidCallback onUpgradePro;
  final VoidCallback onDismissAbsorbLosses;
  final bool isArabic;

  const MerchantLossAversionBanner({
    super.key,
    this.estimatedLostRevenueEgp = 0.0,
    this.noShowCount = 0,
    required this.onUpgradePro,
    required this.onDismissAbsorbLosses,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    if (noShowCount <= 0 || estimatedLostRevenueEgp <= 0) {
      return const SizedBox.shrink();
    }
    final lostEgp = estimatedLostRevenueEgp.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: const Color(0xFF261214), // High-urgency deep dark red/burgundy
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
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
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.trending_down_rounded,
                  color: Colors.redAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isArabic
                      ? '⚠️ خسرت ~$lostEgp ج.م هذا الشهر بسبب $noShowCount حجوزات وهمية!'
                      : '⚠️ You lost ~$lostEgp EGP to $noShowCount no-shows & cancellations this month.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isArabic
                ? 'الحجوزات بدون عربون بتكلفك إشغال طاولات فاضية. فعّل "حجزي برو" واستقبل عربون إلكتروني فوري مع تذكيرات واتساب آلية قبل الميعاد بساعة.'
                : 'Turn on Hagzy Pro Automated Deposits & WhatsApp Reminders to protect your slots and eliminate empty tables.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // Primary CTA
              Expanded(
                child: ElevatedButton(
                  onPressed: onUpgradePro,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    isArabic
                        ? 'تفعيل الحماية والإيداع الآلي'
                        : 'Turn On Automated Deposits',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Loss-Aversion Dismiss CTA (never "Cancel" or "Not now")
              TextButton(
                onPressed: onDismissAbsorbLosses,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white.withValues(alpha: 0.6),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(
                  isArabic ? 'سأتحمل الخسائر بنفسي' : 'I\'ll absorb the losses',
                  style: const TextStyle(fontSize: 12.0),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

