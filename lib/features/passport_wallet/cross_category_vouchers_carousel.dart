import 'package:flutter/material.dart';
import '../../theme/hagzy_theme.dart';

/// Voucher model for Cross-Category Loyalty Moat
class CrossCategoryVoucher {
  const CrossCategoryVoucher({
    required this.id,
    required this.title,
    required this.targetCategory,
    required this.discountLabel,
    required this.unlockedByDescription,
    required this.icon,
    required this.color,
  });

  final String id;
  final String title;
  final String targetCategory;
  final String discountLabel;
  final String unlockedByDescription;
  final IconData icon;
  final Color color;
}

/// Carousel rendering earned cross-vertical discount vouchers.
class CrossCategoryVouchersCarousel extends StatelessWidget {
  const CrossCategoryVouchersCarousel({
    super.key,
    this.vouchers = defaultVouchers,
    this.isArabic = false,
    this.onRedeemVoucher,
  });

  final List<CrossCategoryVoucher> vouchers;
  final bool isArabic;
  final ValueChanged<CrossCategoryVoucher>? onRedeemVoucher;

  static const List<CrossCategoryVoucher> defaultVouchers = [
    CrossCategoryVoucher(
      id: 'v_ps5_workspace',
      title: 'PlayStation VIP Room',
      targetCategory: 'playstation',
      discountLabel: '20% OFF',
      unlockedByDescription: 'Unlocked by 5+ study hours in Workspaces',
      icon: Icons.sports_esports_rounded,
      color: Color(0xFF10B981),
    ),
    CrossCategoryVoucher(
      id: 'v_barber_sports',
      title: 'Barbershop Fade + Beard',
      targetCategory: 'barber',
      discountLabel: '50 EGP OFF',
      unlockedByDescription: 'Unlocked by booking a Padel or Football match',
      icon: Icons.content_cut_rounded,
      color: Color(0xFF0F766E),
    ),
    CrossCategoryVoucher(
      id: 'v_escape_billiards',
      title: 'Escape Room Squad Pass',
      targetCategory: 'escape_room',
      discountLabel: '100 EGP OFF',
      unlockedByDescription: 'Unlocked by 3+ Billiards lounge sessions',
      icon: Icons.lock_open_rounded,
      color: Color(0xFFD97706),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) return const SizedBox.shrink();
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: kVermilion,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
              ),
              child: const Icon(Icons.loyalty_rounded,
                  size: 13, color: Colors.white),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isArabic
                    ? 'كوبونات الولاء بين الأنشطة'
                    : 'Cross-Vertical Loyalty Perks',
                style: hagzyTextStyle(
                  arabic: isArabic,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 148,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: vouchers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final v = vouchers[index];
              final localizedTitle = isArabic
                  ? switch (v.id) {
                      'v_ps5_workspace' => 'غرفة بلايستيشن VIP',
                      'v_barber_sports' => 'حلاقة شعر وتحديد لحية',
                      'v_escape_billiards' => 'تذكرة غرفة الهروب للشلة',
                      _ => v.title,
                    }
                  : v.title;
              final localizedDiscount = isArabic
                  ? switch (v.id) {
                      'v_ps5_workspace' => 'خصم ٢٠٪',
                      'v_barber_sports' => 'خصم ٥٠ ج.م',
                      'v_escape_billiards' => 'خصم ١٠٠ ج.م',
                      _ => v.discountLabel,
                    }
                  : v.discountLabel;
              final localizedUnlockDesc = isArabic
                  ? switch (v.id) {
                      'v_ps5_workspace' =>
                        'يُفتح بعد ٥+ ساعات مذاكرة في مساحات العمل',
                      'v_barber_sports' =>
                        'يُفتح بعد حجز مباراة بادل أو كرة قدم',
                      'v_escape_billiards' => 'يُفتح بعد ٣+ جلسات بلياردو',
                      _ => v.unlockedByDescription,
                    }
                  : v.unlockedByDescription;

              return Container(
                width: 272,
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
                  border: Border.all(
                    color: kBorderStrong,
                    width: 1.3,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(height: 3.0, color: kVermilion),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: isDark ? kVermilion : kObsidian,
                                    borderRadius: BorderRadius.circular(
                                        HagzyTokens.radiusXs),
                                  ),
                                  child: Icon(v.icon,
                                      size: 15, color: Colors.white),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    localizedTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: kInk,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kVermilion,
                                    borderRadius: BorderRadius.circular(
                                        HagzyTokens.radiusXs),
                                  ),
                                  child: Text(
                                    localizedDiscount,
                                    style: hagzyMonoStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      arabic: isArabic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              localizedUnlockDesc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: kMuted,
                                fontSize: 12.0,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: InkWell(
                                onTap: () {
                                  onRedeemVoucher?.call(v);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: kSnackBarBg,
                                      behavior: SnackBarBehavior.floating,
                                      content: Text(
                                        isArabic
                                            ? 'تم تفعيل $localizedDiscount على حجزك القادم!'
                                            : 'Applied ${v.discountLabel} discount to your next booking!',
                                      ),
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(
                                    HagzyTokens.radiusXs),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 11, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: kAccentSurface,
                                    borderRadius: BorderRadius.circular(
                                        HagzyTokens.radiusXs),
                                  ),
                                  child: Text(
                                    isArabic ? 'استخدم الخصم ⚡' : 'Use Voucher ⚡',
                                    style: TextStyle(
                                      color: kAccentOnSurface,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
