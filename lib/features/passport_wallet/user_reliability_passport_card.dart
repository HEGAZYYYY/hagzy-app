import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';

/// Visual "Hagzy Lifestyle Passport" card showcasing the user's
/// 100-pt dynamic reliability score, zero-deposit perk unlock, no-show strike counter, and earned badges.
class UserReliabilityPassportCard extends StatelessWidget {
  const UserReliabilityPassportCard({
    super.key,
    required this.profile,
    this.isArabic = false,
    this.onTopUpTap,
  });

  final UserProfile profile;
  final bool isArabic;
  final VoidCallback? onTopUpTap;

  @override
  Widget build(BuildContext context) {
    final unlocksZeroDeposit = profile.hasZeroDepositPerks;
    final isHighRisk = profile.requiresFullDeposit;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: unlocksZeroDeposit
              ? const [Color(0xFF0F3D2E), Color(0xFF062319)]
              : (isHighRisk
                  ? const [Color(0xFF450A0A), Color(0xFF1E0505)]
                  : const [Color(0xFF1E293B), Color(0xFF0F172A)]),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: unlocksZeroDeposit
              ? Colors.greenAccent.withValues(alpha: 0.5)
              : (isHighRisk
                  ? Colors.redAccent.withValues(alpha: 0.5)
                  : Colors.indigoAccent.withValues(alpha: 0.35)),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Passport Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.verified_user_rounded, color: Colors.greenAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'جواز سفر حجزي لايف ستايل' : 'Hagzy Lifestyle Passport',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      isArabic ? 'عضوية لايف ستايل موثوقة' : 'Verified Lifestyle Member',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Reliability Score Circle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: (unlocksZeroDeposit ? Colors.greenAccent : Colors.amber)
                      .withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: unlocksZeroDeposit ? Colors.greenAccent : Colors.amber,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      unlocksZeroDeposit ? Icons.star_rounded : Icons.shield_rounded,
                      size: 16,
                      color: unlocksZeroDeposit ? Colors.greenAccent : Colors.amber,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${profile.reliabilityScore.toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: unlocksZeroDeposit ? Colors.greenAccent : Colors.amber,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Zero-Deposit Perk Badge or High-Risk Notice
          if (unlocksZeroDeposit) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.flash_on_rounded, size: 16, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'مفتوح: حجز مباشر بدون عربون طوال أيام الأسبوع (>95%) 🎉'
                          : 'Unlocked: Zero-Deposit Weekday Booking Perks (>95%) 🎉',
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ] else if (isHighRisk) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.redAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isArabic
                          ? 'تنبيه: يلزم دفع العربون إلكترونياً بالكامل بسبب انخفاض النقاط (<80%)'
                          : 'Notice: 100% upfront digital deposit required due to score (<80%)',
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Stats Counters (Bookings, No-Shows, Wallet)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'حجوزات مكتملة' : 'Completed',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.completedBookingsCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'غياب بدون إلغاء' : 'No-Shows',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${profile.noShowCount}',
                      style: TextStyle(
                        color: profile.noShowCount > 0 ? Colors.redAccent : Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onTopUpTap,
                  borderRadius: BorderRadius.circular(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isArabic ? 'رصيد محفظة حجزي' : 'Hagzy Balance',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11,
                            ),
                          ),
                          if (onTopUpTap != null) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.add_circle_outline_rounded,
                              size: 13,
                              color: Colors.greenAccent,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${profile.hagzyWalletBalance.toStringAsFixed(0)} EGP',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Badges Row
          if (profile.badges.isNotEmpty) ...[
            Text(
              isArabic ? 'الأوسمة والإنجازات' : 'Earned Badges',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: profile.badges.map((badge) {
                final (label, icon, color) = switch (badge) {
                  'shilla_leader' => (
                      isArabic ? 'قائد الشلة 👑' : 'Shilla Leader 👑',
                      Icons.group_rounded,
                      Colors.amber,
                    ),
                  'study_grind' => (
                      isArabic ? 'دحيح المذاكرة 📚' : 'Study Grind 📚',
                      Icons.menu_book_rounded,
                      Colors.lightBlueAccent,
                    ),
                  'gamer_vip' => (
                      isArabic ? 'VIP جيمنج 🎮' : 'Gamer VIP 🎮',
                      Icons.sports_esports_rounded,
                      Colors.purpleAccent,
                    ),
                  _ => (
                      isArabic ? 'عضو موثوق ⭐' : 'Reliable ⭐',
                      Icons.check_circle_rounded,
                      Colors.greenAccent,
                    ),
                };
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 13, color: color),
                      const SizedBox(width: 4),
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
