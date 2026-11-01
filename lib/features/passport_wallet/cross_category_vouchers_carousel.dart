import 'package:flutter/material.dart';

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
      unlockedByDescription: 'Unlocked by 5+ study hours in Workspaces 📚',
      icon: Icons.sports_esports_rounded,
      color: Colors.purpleAccent,
    ),
    CrossCategoryVoucher(
      id: 'v_barber_sports',
      title: 'Barbershop Fade + Beard',
      targetCategory: 'barber',
      discountLabel: '50 EGP OFF',
      unlockedByDescription: 'Unlocked by booking Padel / Football match ⚽',
      icon: Icons.content_cut_rounded,
      color: Colors.tealAccent,
    ),
    CrossCategoryVoucher(
      id: 'v_escape_billiards',
      title: 'Escape Room Squad Pass',
      targetCategory: 'escape_room',
      discountLabel: '100 EGP OFF',
      unlockedByDescription: 'Unlocked by 3+ Billiards lounge sessions 🎱',
      icon: Icons.lock_open_rounded,
      color: Colors.amberAccent,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              const Icon(Icons.loyalty_rounded, size: 18, color: Colors.amber),
              const SizedBox(width: 8),
              Text(
                isArabic ? 'كوبونات الولاء بين الأنشطة' : 'Cross-Vertical Loyalty Perks',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: vouchers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final v = vouchers[index];
              return Container(
                width: 260,
                padding: const EdgeInsets.all(14.0),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      v.color.withValues(alpha: 0.2),
                      const Color(0xFF0F172A),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: v.color.withValues(alpha: 0.4),
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: v.color.withValues(alpha: 0.25),
                          child: Icon(v.icon, size: 16, color: v.color),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: v.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            v.discountLabel,
                            style: TextStyle(
                              color: v.color,
                              fontSize: 12.0,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      v.unlockedByDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12.0,
                      ),
                    ),
                    Align(
                      alignment: isArabic ? Alignment.centerLeft : Alignment.centerRight,
                      child: InkWell(
                        onTap: () {
                          onRedeemVoucher?.call(v);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.green,
                              content: Text(
                                isArabic
                                    ? 'تم تفعيل خصم ${v.discountLabel} على حجزك القادم!'
                                    : 'Applied ${v.discountLabel} discount to your next booking!',
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isArabic ? 'استخدم الخصم ⚡' : 'Use Voucher ⚡',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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

