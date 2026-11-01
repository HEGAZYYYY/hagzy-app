import 'package:flutter/material.dart';
import '../../core/utils/smart_defaults.dart';

/// Dynamic Smart Defaults Header Banner enforcing Principle 1
class VibeSmartBanner extends StatelessWidget {
  final DiscoveryVibe vibe;
  final int openVenuesCount;
  final VoidCallback onCtaPressed;
  final ValueChanged<String>? onCategoryQuickTap;
  final bool isArabic;

  const VibeSmartBanner({
    super.key,
    required this.vibe,
    required this.openVenuesCount,
    required this.onCtaPressed,
    this.onCategoryQuickTap,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    final headline = isArabic ? vibe.headlineAr : vibe.headlineEn;
    final ctaText = buildDynamicCtaText(
      availableCount: openVenuesCount,
      vibe: vibe,
      isArabic: isArabic,
    );

    final isDay = vibe == DiscoveryVibe.dayProductivity;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: isDay
              ? [
                  const Color(0xFF0F172A),
                  const Color(0xFF064E3B),
                ]
              : [
                  const Color(0xFF0F172A),
                  const Color(0xFF1E1B4B),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isDay ? Icons.wb_sunny_rounded : Icons.nightlife_rounded,
                      size: 13,
                      color: isDay ? Colors.amberAccent : Colors.purpleAccent,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isDay
                          ? (isArabic ? 'صباح التركيز والإنجاز' : 'Daytime Focus')
                          : (isArabic ? 'سهرة الشلة واللعب' : 'Night Hangout'),
                      style: const TextStyle(
                        fontSize: 12.0,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (openVenuesCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isArabic ? '$openVenuesCount متاح الآن' : '$openVenuesCount Open Now',
                    style: const TextStyle(
                      fontSize: 12.0,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            headline,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              onPressed: onCtaPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                ctaText,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

