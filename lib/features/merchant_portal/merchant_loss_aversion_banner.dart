import 'package:flutter/material.dart';
import '../../theme/hagzy_theme.dart';

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
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final lostEgp = estimatedLostRevenueEgp.toStringAsFixed(0);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF231215) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: isDark
              ? const Color(0xFFF87171).withValues(alpha: 0.35)
              : const Color(0xFFFECACA),
          width: 1,
        ),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kError.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.trending_down_rounded,
                  color: kError,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic
                          ? 'خسرت ~$lostEgp ج.م هذا الشهر بسبب $noShowCount حجوزات ملغاة'
                          : 'You lost ~$lostEgp EGP to $noShowCount no-shows & cancellations',
                      style: hagzyTextStyle(
                        arabic: isArabic,
                        color: isDark ? Colors.white : const Color(0xFF991B1B),
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        tabularFigures: true,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isArabic
                          ? 'الحجوزات بدون عربون تكلفك إشغال مواعيد فارغة. فعّل الإيداع الآلي وتذكيرات واتساب لحماية أرباحك.'
                          : 'Turn on Hagzy Pro Automated Deposits & WhatsApp Reminders to protect your slots and eliminate empty tables.',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.78)
                            : const Color(0xFF7F1D1D),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onUpgradePro,
                style: FilledButton.styleFrom(
                  backgroundColor:
                      isDark ? const Color(0xFFDC2626) : const Color(0xFFB91C1C),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 42),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(HagzyTokens.radiusMedium),
                  ),
                ),
                icon: const Icon(Icons.shield_rounded, size: 16),
                label: Text(
                  isArabic
                      ? 'تفعيل الحماية والإيداع الآلي'
                      : 'Turn On Automated Deposits',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                onPressed: onDismissAbsorbLosses,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : const Color(0xFF991B1B),
                ),
                child: Text(
                  isArabic ? 'سأتحمل الخسائر بنفسي' : 'I\'ll absorb the losses',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
