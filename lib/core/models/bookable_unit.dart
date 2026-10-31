import 'dart:convert';

/// Pricing modes for Hagzy Universal Polymorphic Booking Engine
enum PricingMode {
  /// Sports Courts, Billiards, Ping Pong (flat rate per hour)
  hourlyFlat('hourly_flat'),

  /// PlayStation VIP Rooms (rate increases with capacity, e.g. 2 players = 60 EGP/hr, 4 players = 100 EGP/hr)
  hourlyTieredCapacity('hourly_tiered_capacity'),

  /// Escape Rooms & Group Hangouts (per-person rate DROPS as group size increases)
  perPersonTiered('per_person_tiered'),

  /// Workspaces & Study Zones (Hourly vs Day Pass vs Weekly Pass)
  timePass('time_pass'),

  /// Barbershops & Men's Grooming (Additive service checklist: Haircut + Beard + Facial)
  serviceMenu('service_menu');

  final String value;
  const PricingMode(this.value);

  static PricingMode fromString(String? raw) {
    if (raw == null) return PricingMode.hourlyFlat;
    final normalized = raw.trim().toLowerCase();
    for (final mode in PricingMode.values) {
      if (mode.value == normalized || mode.name.toLowerCase() == normalized) {
        return mode;
      }
    }
    return PricingMode.hourlyFlat;
  }
}

/// Service item for Barbershops, Grooming, and VIP Add-ons
class ServiceMenuItem {
  final String id;
  final String name;
  final String? nameAr;
  final double price;
  final int durationMins;
  final String? category; // e.g., 'hair', 'beard', 'skincare', 'snack'

  const ServiceMenuItem({
    required this.id,
    required this.name,
    this.nameAr,
    required this.price,
    this.durationMins = 30,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (nameAr != null) 'nameAr': nameAr,
        'price': price,
        'duration_mins': durationMins,
        if (category != null) 'category': category,
      };

  factory ServiceMenuItem.fromJson(Map<String, dynamic> json) =>
      ServiceMenuItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nameAr: json['nameAr']?.toString() ?? json['name_ar']?.toString(),
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
        durationMins: (json['duration_mins'] ?? json['durationMinutes'] ?? json['minutes'] ?? 30) as int,
        category: json['category']?.toString(),
      );

  ServiceMenuItem copyWith({
    String? id,
    String? name,
    String? nameAr,
    double? price,
    int? durationMins,
    String? category,
  }) =>
      ServiceMenuItem(
        id: id ?? this.id,
        name: name ?? this.name,
        nameAr: nameAr ?? this.nameAr,
        price: price ?? this.price,
        durationMins: durationMins ?? this.durationMins,
        category: category ?? this.category,
      );
}

/// Optional Snack, Controller, or Equipment Add-on
class UnitAddon {
  final String id;
  final String name;
  final String? nameAr;
  final double price;

  const UnitAddon({
    required this.id,
    required this.name,
    this.nameAr,
    required this.price,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (nameAr != null) 'nameAr': nameAr,
        'price': price,
      };

  factory UnitAddon.fromJson(Map<String, dynamic> json) => UnitAddon(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        nameAr: json['nameAr']?.toString() ?? json['name_ar']?.toString(),
        price: (json['price'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Detailed pricing breakdown for Contrast-Anchored checkout & split calculation
class PricingCalculationResult {
  final double totalPriceEgp;
  final double depositRequiredEgp;
  final double serviceFeeEgp;
  final double perPersonShareEgp;
  final double remainingCashAtVenueEgp;
  final int totalDurationMins;
  final double rateAppliedEgp;
  final String pricingModeSummary;
  final Map<String, dynamic> breakdown;

  const PricingCalculationResult({
    required this.totalPriceEgp,
    required this.depositRequiredEgp,
    required this.serviceFeeEgp,
    required this.perPersonShareEgp,
    required this.remainingCashAtVenueEgp,
    required this.totalDurationMins,
    required this.rateAppliedEgp,
    required this.pricingModeSummary,
    required this.breakdown,
  });
}

/// Polymorphic Universal Bookable Unit (Rooms, Tables, Desks, Chairs, Courts, Escape Rooms)
class BookableUnit {
  final String id;
  final String venueId;
  final String category; // 'playstation', 'billiards', 'ping_pong', 'workspace', 'escape_room', 'barber', 'court'
  final String unitName;
  final String? unitNameAr;
  final PricingMode pricingMode;
  final double basePriceEgp;
  final Map<String, dynamic> pricingTiers; // e.g., {"2": 60, "4": 100} or {"day_pass": 80, "hourly": 20} or {"3": 220, "6": 160}
  final List<ServiceMenuItem> serviceMenu;
  final List<UnitAddon> addons;
  final int minCapacity;
  final int maxCapacity;
  final Map<String, dynamic> specsMetadata; // e.g., {"console": "PS5", "screen_inch": 65, "ac": true, "wifi_mbps": 100}

  const BookableUnit({
    required this.id,
    required this.venueId,
    required this.category,
    required this.unitName,
    this.unitNameAr,
    required this.pricingMode,
    required this.basePriceEgp,
    this.pricingTiers = const {},
    this.serviceMenu = const [],
    this.addons = const [],
    this.minCapacity = 1,
    this.maxCapacity = 4,
    this.specsMetadata = const {},
  });

  /// True if the unit fits a shilla of given [partySize]
  bool fitsPartySize(int partySize) =>
      partySize >= minCapacity && (maxCapacity <= 0 || partySize <= maxCapacity);

  /// Calculate exact pricing, deposit hold, and per-person split across any of the 5 modes
  PricingCalculationResult calculatePricing({
    int headcount = 1,
    double durationHours = 1.0,
    String? timePassType, // 'hourly', 'day_pass', 'weekly'
    List<String> selectedServiceIds = const [],
    List<String> selectedAddonIds = const [],
    double customServiceFee = 15.0,
    double customDepositRate = 0.10, // 10% deposit anchor
    double minDepositEgp = 30.0,
  }) {
    final effectiveHeadcount = headcount <= 0 ? 1 : headcount;
    final effectiveHours = durationHours <= 0 ? 1.0 : durationHours;
    double rawTotal = 0.0;
    int durationMinutes = (effectiveHours * 60).round();
    double appliedRate = basePriceEgp;
    String modeSummary = '';

    switch (pricingMode) {
      case PricingMode.hourlyFlat:
        appliedRate = basePriceEgp;
        rawTotal = appliedRate * effectiveHours;
        modeSummary = '${appliedRate.toStringAsFixed(0)} EGP/hr × ${effectiveHours.toStringAsFixed(effectiveHours.truncateToDouble() == effectiveHours ? 0 : 1)}h';
        break;

      case PricingMode.hourlyTieredCapacity:
        // PlayStation VIP: {"2": 60, "4": 100}
        appliedRate = _resolveTieredHourlyRate(effectiveHeadcount);
        rawTotal = appliedRate * effectiveHours;
        modeSummary = '${appliedRate.toStringAsFixed(0)} EGP/hr ($effectiveHeadcount players) × ${effectiveHours.toStringAsFixed(effectiveHours.truncateToDouble() == effectiveHours ? 0 : 1)}h';
        break;

      case PricingMode.perPersonTiered:
        // Escape Rooms: As headcount increases, per-person cost drops! {"3": 220, "6": 160}
        appliedRate = _resolvePerPersonTieredRate(effectiveHeadcount);
        rawTotal = appliedRate * effectiveHeadcount;
        modeSummary = '${appliedRate.toStringAsFixed(0)} EGP/player × $effectiveHeadcount players';
        break;

      case PricingMode.timePass:
        // Workspace: {"hourly": 20, "day_pass": 80, "weekly": 400}
        final passKey = (timePassType ?? 'hourly').toLowerCase();
        if (passKey == 'day_pass' || passKey == 'day' || passKey == 'full_day') {
          appliedRate = _parseTierValue('day_pass') ?? (basePriceEgp * 4);
          rawTotal = appliedRate * effectiveHeadcount;
          durationMinutes = 8 * 60; // 8-hour day pass default
          modeSummary = 'Full-Day Pass (${appliedRate.toStringAsFixed(0)} EGP × $effectiveHeadcount)';
        } else if (passKey == 'weekly') {
          appliedRate = _parseTierValue('weekly') ?? (basePriceEgp * 20);
          rawTotal = appliedRate * effectiveHeadcount;
          durationMinutes = 40 * 60;
          modeSummary = 'Weekly Pass (${appliedRate.toStringAsFixed(0)} EGP × $effectiveHeadcount)';
        } else {
          appliedRate = _parseTierValue('hourly') ?? basePriceEgp;
          rawTotal = appliedRate * effectiveHours * effectiveHeadcount;
          modeSummary = '${appliedRate.toStringAsFixed(0)} EGP/hr × ${effectiveHours.toStringAsFixed(1)}h × $effectiveHeadcount desks';
        }
        break;

      case PricingMode.serviceMenu:
        // Barbershops: Additive checklist of selected services
        final selectedItems = serviceMenu.where((s) => selectedServiceIds.contains(s.id)).toList();
        if (selectedItems.isEmpty && serviceMenu.isNotEmpty) {
          // Default to first service if none selected
          selectedItems.add(serviceMenu.first);
        }
        appliedRate = selectedItems.fold(0.0, (acc, s) => acc + s.price);
        durationMinutes = selectedItems.fold(0, (acc, s) => acc + s.durationMins);
        rawTotal = appliedRate;
        modeSummary = '${selectedItems.length} services selected ($durationMinutes min total)';
        break;
    }

    // Add selected Add-ons (e.g., extra controllers, drinks, study lockers)
    double addonsTotal = 0.0;
    for (final addonId in selectedAddonIds) {
      final match = addons.where((a) => a.id == addonId).firstOrNull;
      if (match != null) {
        addonsTotal += match.price;
      }
    }
    rawTotal += addonsTotal;

    // Minimum sanity check
    if (rawTotal <= 0) rawTotal = basePriceEgp;

    // Calculate Contrast Anchoring breakdown
    final perPersonShare = rawTotal / effectiveHeadcount;

    // Deposit: Anchored low (default 10% or min 30 EGP, but not exceeding total)
    double deposit = rawTotal * customDepositRate;
    if (deposit < minDepositEgp) deposit = minDepositEgp;
    if (deposit > rawTotal) deposit = rawTotal;

    final remainingAtVenue = (rawTotal - deposit).clamp(0.0, double.infinity);

    return PricingCalculationResult(
      totalPriceEgp: rawTotal,
      depositRequiredEgp: deposit,
      serviceFeeEgp: customServiceFee,
      perPersonShareEgp: perPersonShare,
      remainingCashAtVenueEgp: remainingAtVenue,
      totalDurationMins: durationMinutes,
      rateAppliedEgp: appliedRate,
      pricingModeSummary: modeSummary,
      breakdown: {
        'baseRate': appliedRate,
        'headcount': effectiveHeadcount,
        'durationHours': effectiveHours,
        'addonsTotal': addonsTotal,
        'selectedServiceCount': selectedServiceIds.length,
        'selectedAddonCount': selectedAddonIds.length,
      },
    );
  }

  double _resolveTieredHourlyRate(int headcount) {
    if (pricingTiers.isEmpty) return basePriceEgp;

    // Parse keys as capacity thresholds e.g. {"2": 60, "4": 100}
    final sortedCaps = pricingTiers.keys
        .map((k) => int.tryParse(k))
        .whereType<int>()
        .toList()
      ..sort();

    if (sortedCaps.isEmpty) return basePriceEgp;

    for (final cap in sortedCaps) {
      if (headcount <= cap) {
        return (pricingTiers[cap.toString()] as num?)?.toDouble() ?? basePriceEgp;
      }
    }

    // If exceeding highest cap, return rate for max cap
    final highestCap = sortedCaps.last;
    return (pricingTiers[highestCap.toString()] as num?)?.toDouble() ?? basePriceEgp;
  }

  double _resolvePerPersonTieredRate(int headcount) {
    if (pricingTiers.isEmpty) return basePriceEgp;

    // Escape room tiers: {"3": 220, "4": 200, "5": 180, "6": 160}
    final sortedSizes = pricingTiers.keys
        .map((k) => int.tryParse(k))
        .whereType<int>()
        .toList()
      ..sort();

    if (sortedSizes.isEmpty) return basePriceEgp;

    // If headcount is smaller than lowest tier, use lowest tier rate
    if (headcount <= sortedSizes.first) {
      return (pricingTiers[sortedSizes.first.toString()] as num?)?.toDouble() ?? basePriceEgp;
    }

    // If headcount matches or fits inside a tier
    for (int i = 0; i < sortedSizes.length; i++) {
      if (headcount <= sortedSizes[i]) {
        return (pricingTiers[sortedSizes[i].toString()] as num?)?.toDouble() ?? basePriceEgp;
      }
    }

    // For squads larger than highest tier, give best discount (highest size tier)
    return (pricingTiers[sortedSizes.last.toString()] as num?)?.toDouble() ?? basePriceEgp;
  }

  double? _parseTierValue(String key) {
    final val = pricingTiers[key];
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'venue_id': venueId,
        'category': category,
        'unit_name': unitName,
        if (unitNameAr != null) 'unit_name_ar': unitNameAr,
        'pricing_mode': pricingMode.value,
        'base_price_egp': basePriceEgp,
        'pricing_tiers': pricingTiers,
        'service_menu': serviceMenu.map((s) => s.toJson()).toList(),
        'addons': addons.map((a) => a.toJson()).toList(),
        'min_capacity': minCapacity,
        'max_capacity': maxCapacity,
        'specs_metadata': specsMetadata,
      };

  factory BookableUnit.fromJson(Map<String, dynamic> json) {
    final rawServices = json['service_menu'] as List<dynamic>? ??
        json['services'] as List<dynamic>? ??
        [];
    final rawAddons = json['addons'] as List<dynamic>? ?? [];

    Map<String, dynamic> parsedTiers = {};
    if (json['pricing_tiers'] is Map) {
      parsedTiers = Map<String, dynamic>.from(json['pricing_tiers'] as Map);
    } else if (json['pricing_tiers'] is String) {
      try {
        parsedTiers = jsonDecode(json['pricing_tiers'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    Map<String, dynamic> parsedSpecs = {};
    if (json['specs_metadata'] is Map) {
      parsedSpecs = Map<String, dynamic>.from(json['specs_metadata'] as Map);
    } else if (json['specs_metadata'] is String) {
      try {
        parsedSpecs = jsonDecode(json['specs_metadata'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    return BookableUnit(
      id: json['id']?.toString() ?? '',
      venueId: (json['venue_id'] ?? json['venueId'])?.toString() ?? '',
      category: json['category']?.toString() ?? 'lounge',
      unitName: (json['unit_name'] ?? json['name'] ?? 'Unit').toString(),
      unitNameAr: (json['unit_name_ar'] ?? json['nameAr'])?.toString(),
      pricingMode: PricingMode.fromString(json['pricing_mode']?.toString()),
      basePriceEgp: (json['base_price_egp'] ?? json['hourlyRate'] ?? json['price'] as num?)?.toDouble() ?? 50.0,
      pricingTiers: parsedTiers,
      serviceMenu: rawServices
          .map((item) => ServiceMenuItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      addons: rawAddons
          .map((item) => UnitAddon.fromJson(item as Map<String, dynamic>))
          .toList(),
      minCapacity: (json['min_capacity'] as num?)?.toInt() ?? 1,
      maxCapacity: (json['max_capacity'] as num?)?.toInt() ?? 4,
      specsMetadata: parsedSpecs,
    );
  }

  BookableUnit copyWith({
    String? id,
    String? venueId,
    String? category,
    String? unitName,
    String? unitNameAr,
    PricingMode? pricingMode,
    double? basePriceEgp,
    Map<String, dynamic>? pricingTiers,
    List<ServiceMenuItem>? serviceMenu,
    List<UnitAddon>? addons,
    int? minCapacity,
    int? maxCapacity,
    Map<String, dynamic>? specsMetadata,
  }) =>
      BookableUnit(
        id: id ?? this.id,
        venueId: venueId ?? this.venueId,
        category: category ?? this.category,
        unitName: unitName ?? this.unitName,
        unitNameAr: unitNameAr ?? this.unitNameAr,
        pricingMode: pricingMode ?? this.pricingMode,
        basePriceEgp: basePriceEgp ?? this.basePriceEgp,
        pricingTiers: pricingTiers ?? this.pricingTiers,
        serviceMenu: serviceMenu ?? this.serviceMenu,
        addons: addons ?? this.addons,
        minCapacity: minCapacity ?? this.minCapacity,
        maxCapacity: maxCapacity ?? this.maxCapacity,
        specsMetadata: specsMetadata ?? this.specsMetadata,
      );
}
