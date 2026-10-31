import '../models/models_v2.dart';

/// Time-of-day heuristic vibe for smart defaults (Principle 1)
enum DiscoveryVibe {
  dayProductivity, // 8:00 AM – 4:00 PM (Workspaces & Barbershops)
  eveningHangout, // 4:00 PM – 1:00 AM (PlayStation, Billiards, Ping Pong, Escape Rooms, Courts)
  lateNightAfterHours; // 1:00 AM – 8:00 AM (24/7 Gaming Lounges & Next Day Pre-booking)

  static DiscoveryVibe fromDateTime([DateTime? dt]) {
    final now = dt ?? DateTime.now();
    final hour = now.hour;

    if (hour >= 8 && hour < 16) {
      return DiscoveryVibe.dayProductivity;
    } else if (hour >= 16 || hour <= 1) {
      return DiscoveryVibe.eveningHangout;
    } else {
      return DiscoveryVibe.lateNightAfterHours;
    }
  }

  String get headlineEn => switch (this) {
        DiscoveryVibe.dayProductivity =>
          'Quiet study desks & open barber chairs near you right now',
        DiscoveryVibe.eveningHangout =>
          'Tonight at 9:00 PM • VIP Rooms, Tables & Courts Available',
        DiscoveryVibe.lateNightAfterHours =>
          'Late Night Lounges & Tomorrow Reservations Open',
      };

  String get headlineAr => switch (this) {
        DiscoveryVibe.dayProductivity =>
          'مكاتب مذاكرة هادية وكراسي حلاقة فاضية جنبك دلوقتي',
        DiscoveryVibe.eveningHangout =>
          'الليلة: رومات بلايستيشن، بلياردو، وملاعب جاهزة للشلة',
        DiscoveryVibe.lateNightAfterHours =>
          'سهرات بعد نص الليل وحجوزات بكرة المسبقة',
      };

  List<String> get recommendedCategories => switch (this) {
        DiscoveryVibe.dayProductivity => ['workspace', 'barber'],
        DiscoveryVibe.eveningHangout => [
            'playstation',
            'billiards',
            'ping_pong',
            'escape_room',
            'court',
          ],
        DiscoveryVibe.lateNightAfterHours => [
            'playstation',
            'billiards',
            'workspace',
          ],
      };
}

/// Shilla Group-Size filter chips (Solo | 2 Friends | 3-5 Friends | 6+ Squad)
enum ShillaSizePreset {
  all(labelEn: 'All', labelAr: 'الكل', minCap: 1, maxCap: 99),
  solo(labelEn: 'Solo', labelAr: 'لوحدي (١)', minCap: 1, maxCap: 1),
  duo(labelEn: '2 Friends', labelAr: '٢ صحاب', minCap: 2, maxCap: 2),
  group(labelEn: '3-5 Friends', labelAr: 'شلة ٣-٥', minCap: 3, maxCap: 5),
  squad(labelEn: '6+ Squad', labelAr: 'فريق ٦+', minCap: 6, maxCap: 99);

  final String labelEn;
  final String labelAr;
  final int minCap;
  final int maxCap;

  const ShillaSizePreset({
    required this.labelEn,
    required this.labelAr,
    required this.minCap,
    required this.maxCap,
  });

  /// Check whether a unit accommodates this party size
  bool matchesUnit(BookableUnit unit) {
    if (this == ShillaSizePreset.all) return true;
    if (this == ShillaSizePreset.solo) return unit.minCapacity <= 1;
    if (this == ShillaSizePreset.duo) {
      return unit.minCapacity <= 2 && unit.maxCapacity >= 2;
    }
    if (this == ShillaSizePreset.group) {
      // Overlaps with 3..5 capacity
      return unit.maxCapacity >= 3 && unit.minCapacity <= 5;
    }
    if (this == ShillaSizePreset.squad) {
      return unit.maxCapacity >= 6;
    }
    return true;
  }
}

/// Dynamic Primary CTA Formatter (Principle 1)
/// Never just "Search" — displays live reward count
String buildDynamicCtaText({
  required int availableCount,
  required DiscoveryVibe vibe,
  bool isArabic = false,
}) {
  if (isArabic) {
    if (vibe == DiscoveryVibe.dayProductivity) {
      return availableCount > 0
          ? 'عرض $availableCount مكان مذاكرة وحلاقة متاحين الآن ←'
          : 'استكشف الأماكن المتاحة الآن ←';
    } else {
      return availableCount > 0
          ? 'عرض $availableCount مكان مفتوح الليلة ←'
          : 'استكشف غرف وملاعب الليلة ←';
    }
  } else {
    if (vibe == DiscoveryVibe.dayProductivity) {
      return availableCount > 0
          ? 'Show $availableCount Study & Barber Spots Open Now →'
          : 'Explore Available Spots Now →';
    } else {
      return availableCount > 0
          ? 'Show $availableCount Venues Open Tonight →'
          : 'Explore Available Rooms Tonight →';
    }
  }
}

