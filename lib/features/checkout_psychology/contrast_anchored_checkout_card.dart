import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';

/// Price-Anchored Checkout Card Enforcing Principle 4 (The Contrast Effect)
class ContrastAnchoredCheckoutCard extends StatelessWidget {
  final HagzyBooking booking;
  final bool isArabic;

  const ContrastAnchoredCheckoutCard({
    super.key,
    required this.booking,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = booking.totalPriceEgp.toStringAsFixed(0);
    final perPerson = booking.perPersonShareEgp.toStringAsFixed(0);
    final deposit = booking.depositRequiredEgp.toStringAsFixed(0);
    final perPersonDeposit = booking.perPersonDepositEgp.toStringAsFixed(0);
    final remaining = booking.remainingCashAtVenueEgp.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Hero: Total Booking Value & Per-Person Split (Anchors the brain)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'إجمالي قيمة الحجز' : 'Total Booking Value',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArabic
                          ? '$total ج.م (${booking.headcount} أفراد • $perPerson ج.م/فرد)'
                          : '$total EGP (${booking.headcount} Players • $perPerson EGP/ea)',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isArabic ? 'سعر مميز' : 'Best Rate',
                  style: TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Divider(height: 1),
          ),

          // 2. Deposit Hold Callout (Contrasted against the big total)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_rounded,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isArabic ? 'تثبيت الحجز الآن' : 'Lock Instant Reservation',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      isArabic ? '$deposit ج.م فقط' : '$deposit EGP only',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isArabic
                      ? '($perPersonDeposit ج.م لكل فرد فقط لتأكيد الحجز ومنع إلغاء الميعاد)'
                      : '($perPersonDeposit EGP / player hold to guarantee your time slot)',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // 3. Subtext: Remainder paid at venue
          Row(
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isArabic
                      ? 'المتبقي ($remaining ج.م) يُدفع كاش أو إنستاباي في المكان.'
                      : 'Remaining ($remaining EGP) is paid in cash/Instapay directly at venue.',
                  style: TextStyle(
                    fontSize: 12.0,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

