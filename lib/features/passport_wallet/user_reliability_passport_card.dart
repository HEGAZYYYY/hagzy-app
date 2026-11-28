import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';
import '../../theme/hagzy_theme.dart';

/// Visual "Hagzy Lifestyle Passport" card — Brushed Obsidian Hardware Pass
/// showcasing 100-pt dynamic reliability score, zero-deposit perks, and wallet balance.
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
    final scoreColor = unlocksZeroDeposit
        ? kSuccess
        : (isHighRisk ? kSignal : kBrandAccent);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: kBorder,
          width: 1.0,
        ),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Passport Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kSurfaceTint,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusMedium),
                      ),
                      child: Icon(Icons.verified_user_rounded,
                          color: kBrandAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic
                                ? 'جواز سفر حجزي لايف ستايل'
                                : 'Hagzy Lifestyle Passport',
                            style: hagzyDisplayStyle(
                              arabic: isArabic,
                              color: kInk,
                              fontWeight: FontWeight.w800,
                              fontSize: 17,
                              letterSpacing: -0.25,
                            ),
                          ),
                          Text(
                            isArabic
                                ? 'عضوية موثوقة'
                                : 'Verified Member',
                            style: TextStyle(
                              color: kMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Reliability Score Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: kSurfaceSubtle,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusFull),
                        border: Border.all(color: kBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            unlocksZeroDeposit
                                ? Icons.star_rounded
                                : Icons.shield_rounded,
                            size: 14,
                            color: scoreColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${profile.reliabilityScore.toStringAsFixed(0)}%',
                            style: hagzyMonoStyle(
                              color: kInk,
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              arabic: isArabic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Zero-Deposit Perk Badge or High-Risk Notice
                if (unlocksZeroDeposit) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kSuccess.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                      border: Border.all(color: kSuccess.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.flash_on_rounded,
                            size: 16, color: kSuccess),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isArabic
                                ? 'مفتوح: حجز مباشر بدون عربون طوال أيام الأسبوع (>95%) 🎉'
                                : 'Unlocked: Zero-Deposit Weekday Booking Perks (>95%) 🎉',
                            style: TextStyle(
                              color: kSuccess,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (isHighRisk) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kSignal.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                      border:
                          Border.all(color: kSignal.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 16, color: kSignal),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isArabic
                                ? 'تنبيه: يلزم دفع العربون إلكترونياً بالكامل بسبب انخفاض النقاط (<80%)'
                                : 'Notice: 100% upfront digital deposit required due to score (<80%)',
                            style: TextStyle(
                              color: kSignal,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else if (profile.completedBookingsCount == 0 &&
                    profile.noShowCount == 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kSurfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.emoji_events_outlined,
                            size: 16, color: kVermilion),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isArabic
                                ? 'أكمل ٣ حجوزات بموثوقية ≥٩٥٪ لفتح ميزة الحجز بدون عربون'
                                : 'Complete 3 bookings with ≥95% score to unlock Zero-Deposit Weekday Perks',
                            style: TextStyle(
                              color: kInk,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                Container(height: 1, color: kBorder),
                const SizedBox(height: 14),

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
                              color: kMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${profile.completedBookingsCount}',
                            style: hagzyMonoStyle(
                              color: kInk,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              arabic: isArabic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 34, color: kBorder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isArabic ? 'غياب بدون إلغاء' : 'No-Shows',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${profile.noShowCount}',
                            style: hagzyMonoStyle(
                              color: profile.noShowCount > 0 ? kSignal : kInk,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              arabic: isArabic,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(width: 1, height: 34, color: kBorder),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: onTopUpTap,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusSmall),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    isArabic
                                        ? 'رصيد المحفظة'
                                        : 'Hagzy Balance',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: kMuted,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (onTopUpTap != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 13,
                                    color: kVermilion,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${profile.hagzyWalletBalance.toStringAsFixed(0)} ${isArabic ? 'ج.م' : 'EGP'}',
                              style: hagzyMonoStyle(
                                color: kVermilion,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                arabic: isArabic,
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
                      color: kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: profile.badges.map((badge) {
                      final isDark = Theme.of(context).brightness ==
                              Brightness.dark ||
                          kDarkMode.value;
                      final (label, icon, color) = switch (badge) {
                        'shilla_leader' => (
                            isArabic ? 'قائد الشلة 👑' : 'Shilla Leader 👑',
                            Icons.group_rounded,
                            isDark ? const Color(0xFFFBBF24) : kGold,
                          ),
                        'study_grind' => (
                            isArabic ? 'دحيح المذاكرة 📚' : 'Study Grind 📚',
                            Icons.menu_book_rounded,
                            isDark
                                ? const Color(0xFF60A5FA)
                                : const Color(0xFF2563EB),
                          ),
                        'gamer_vip' => (
                            isArabic ? 'VIP جيمنج 🎮' : 'Gamer VIP 🎮',
                            Icons.sports_esports_rounded,
                            kVermilion,
                          ),
                        _ => (
                            isArabic ? 'عضو موثوق ⭐' : 'Reliable ⭐',
                            Icons.check_circle_rounded,
                            kSuccess,
                          ),
                      };
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.16 : 0.10),
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusXs),
                          border: Border.all(
                            color: color.withValues(alpha: isDark ? 0.42 : 0.35),
                          ),
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
                                fontSize: 12.0,
                                fontWeight: FontWeight.w800,
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
          ),
        ],
      ),
    );
  }
}
