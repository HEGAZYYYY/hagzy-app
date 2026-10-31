import '../../core/models/models_v2.dart';

/// Pre-configured Category Templates for Merchant Onboarding (Goal Gradient Principle 3)
/// Automatically populates standard units, pricing modes, and menus so merchants don't start from scratch
class CategoryTemplates {
  static List<BookableUnit> getTemplateUnitsForCategory({
    required String category,
    required String venueId,
  }) {
    final cat = category.toLowerCase();

    switch (cat) {
      case 'playstation':
        return [
          BookableUnit(
            id: 'unit_ps5_vip',
            venueId: venueId,
            category: 'playstation',
            unitName: 'VIP Room 1 (PS5 & 65" 4K)',
            unitNameAr: 'غرفة VIP 1 (بلايستيشن 5 وشاشة 65 بوصة)',
            pricingMode: PricingMode.hourlyTieredCapacity,
            basePriceEgp: 60.0,
            pricingTiers: {'2': 60, '4': 100},
            addons: const [
              UnitAddon(id: 'add_ctrl', name: 'Extra Controller', nameAr: 'دراع إضافي', price: 20),
              UnitAddon(id: 'add_redbull', name: 'Cold Drink / Energy', nameAr: 'مشروب طاقة / كانز', price: 25),
            ],
            minCapacity: 1,
            maxCapacity: 4,
            specsMetadata: {'console': 'PS5', 'screen_inch': 65, 'ac': true},
          ),
          BookableUnit(
            id: 'unit_ps5_std',
            venueId: venueId,
            category: 'playstation',
            unitName: 'Standard Room 2 (PS5)',
            unitNameAr: 'غرفة عادية 2 (بلايستيشن 5)',
            pricingMode: PricingMode.hourlyFlat,
            basePriceEgp: 50.0,
            minCapacity: 1,
            maxCapacity: 4,
            specsMetadata: {'console': 'PS5', 'screen_inch': 50, 'ac': true},
          ),
        ];

      case 'billiards':
        return [
          BookableUnit(
            id: 'unit_billiard_1',
            venueId: venueId,
            category: 'billiards',
            unitName: 'Star Tournament Billiard Table #1',
            unitNameAr: 'طاولة بلياردو ستار للمحترفين 1',
            pricingMode: PricingMode.hourlyFlat,
            basePriceEgp: 70.0,
            minCapacity: 2,
            maxCapacity: 4,
            specsMetadata: {'table_cloth': 'Tournament Cloth', 'balls': 'Aramith'},
          ),
        ];

      case 'ping_pong':
        return [
          BookableUnit(
            id: 'unit_pingpong_1',
            venueId: venueId,
            category: 'ping_pong',
            unitName: 'Olympic Ping Pong Table #1',
            unitNameAr: 'طاولة بينج بونج أولمبية 1',
            pricingMode: PricingMode.hourlyFlat,
            basePriceEgp: 50.0,
            minCapacity: 2,
            maxCapacity: 4,
          ),
        ];

      case 'workspace':
        return [
          BookableUnit(
            id: 'unit_desk_silent',
            venueId: venueId,
            category: 'workspace',
            unitName: 'Silent Study Desk',
            unitNameAr: 'مكتب مذاكرة في المنطقة الهادئة',
            pricingMode: PricingMode.timePass,
            basePriceEgp: 20.0,
            pricingTiers: {'hourly': 20, 'day_pass': 80, 'weekly': 350},
            minCapacity: 1,
            maxCapacity: 1,
            specsMetadata: {'wifi_mbps': 100, 'power_outlet': true, 'silent_zone': true},
          ),
        ];

      case 'escape_room':
        return [
          BookableUnit(
            id: 'unit_escape_chamber',
            venueId: venueId,
            category: 'escape_room',
            unitName: 'The Secret Chamber Escape',
            unitNameAr: 'غرفة الهروب: الغرفة السرية',
            pricingMode: PricingMode.perPersonTiered,
            basePriceEgp: 220.0,
            pricingTiers: {'3': 220, '4': 200, '5': 180, '6': 160},
            minCapacity: 3,
            maxCapacity: 8,
            specsMetadata: {'difficulty': 'Hard', 'duration_mins': 60},
          ),
        ];

      case 'barber':
        return [
          BookableUnit(
            id: 'unit_barber_chair_1',
            venueId: venueId,
            category: 'barber',
            unitName: 'Master Barber Specialist Chair',
            unitNameAr: 'كرسي الحلاقة الرئيسي (VIP)',
            pricingMode: PricingMode.serviceMenu,
            basePriceEgp: 100.0,
            serviceMenu: const [
              ServiceMenuItem(id: 's_hair', name: 'Haircut & Wash', nameAr: 'قص شعر واستشوار وغسيل', price: 100, durationMins: 30),
              ServiceMenuItem(id: 's_beard', name: 'Beard Contour & Hot Towel', nameAr: 'تحديد ذقن وفوطة سخنة', price: 60, durationMins: 20),
              ServiceMenuItem(id: 's_facial', name: 'Charcoal Deep Facial', nameAr: 'جلسة تنظيف بشرة بالفحم', price: 70, durationMins: 20),
            ],
            minCapacity: 1,
            maxCapacity: 1,
          ),
        ];

      case 'court':
      default:
        return [
          BookableUnit(
            id: 'unit_pitch_5v5',
            venueId: venueId,
            category: 'court',
            unitName: 'Main 5v5 Turf Pitch',
            unitNameAr: 'ملعب خماسي نجيل صناعي رئيسي',
            pricingMode: PricingMode.hourlyFlat,
            basePriceEgp: 300.0,
            minCapacity: 10,
            maxCapacity: 14,
            specsMetadata: {'turf': 'FIFA Certified Artificial Grass', 'floodlights': true},
          ),
        ];
    }
  }
}

