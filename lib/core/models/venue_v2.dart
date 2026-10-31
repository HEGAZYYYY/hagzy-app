import 'dart:convert';
import 'bookable_unit.dart';

/// Multi-Category Universal Venue (Hosts PS5, Billiards, Desks, Escape Rooms, Barbers, Courts)
class HagzyVenue {
  final String id;
  final String ownerId;
  final String name;
  final String? nameAr;
  final String city; // e.g., 'Kafr El Sheikh', 'Tanta', 'New Cairo', 'Alexandria'
  final String? address;
  final String? addressAr;
  final double? lat;
  final double? lng;
  final List<String> categories; // ['playstation', 'billiards', 'ping_pong', 'workspace', 'escape_room', 'barber', 'court']
  final String? instapayAddress;
  final String? walletNumber;
  final String subscriptionTier; // 'free', 'pro'
  final double reliabilityScore; // Merchant score e.g. 5.0
  final List<BookableUnit> units;
  final String? phone;
  final String? imageUrl;
  final DateTime createdAt;

  const HagzyVenue({
    required this.id,
    required this.ownerId,
    required this.name,
    this.nameAr,
    required this.city,
    this.address,
    this.addressAr,
    this.lat,
    this.lng,
    required this.categories,
    this.instapayAddress,
    this.walletNumber,
    this.subscriptionTier = 'free',
    this.reliabilityScore = 5.0,
    this.units = const [],
    this.phone,
    this.imageUrl,
    required this.createdAt,
  });

  bool get isPro => subscriptionTier.toLowerCase() == 'pro';

  bool hasCategory(String cat) {
    final needle = cat.trim().toLowerCase();
    return categories.any((c) => c.toLowerCase() == needle);
  }

  /// Finds units inside this venue matching a specific category
  List<BookableUnit> unitsForCategory(String category) =>
      units.where((u) => u.category.toLowerCase() == category.toLowerCase()).toList();

  /// Finds units fitting a specific shilla party size
  List<BookableUnit> unitsForPartySize(int partySize) =>
      units.where((u) => u.fitsPartySize(partySize)).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'owner_id': ownerId,
        'name': name,
        if (nameAr != null) 'name_ar': nameAr,
        'city': city,
        if (address != null) 'address': address,
        if (addressAr != null) 'address_ar': addressAr,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'categories': categories,
        if (instapayAddress != null) 'instapay_address': instapayAddress,
        if (walletNumber != null) 'wallet_number': walletNumber,
        'subscription_tier': subscriptionTier,
        'reliability_score': reliabilityScore,
        'units': units.map((u) => u.toJson()).toList(),
        if (phone != null) 'phone': phone,
        if (imageUrl != null) 'image_url': imageUrl,
        'created_at': createdAt.toIso8601String(),
      };

  factory HagzyVenue.fromJson(Map<String, dynamic> json) {
    List<String> parsedCategories = [];
    if (json['categories'] is List) {
      parsedCategories = (json['categories'] as List).map((c) => c.toString()).toList();
    } else if (json['categories'] is String) {
      try {
        parsedCategories = (jsonDecode(json['categories'] as String) as List).map((c) => c.toString()).toList();
      } catch (_) {
        parsedCategories = [json['categories'].toString()];
      }
    } else if (json['type'] != null) {
      // Legacy compatibility
      parsedCategories = [json['type'].toString()];
    }

    final rawUnits = json['units'] as List<dynamic>? ??
        json['items'] as List<dynamic>? ??
        [];

    final venueId = json['id']?.toString() ?? '';

    return HagzyVenue(
      id: venueId,
      ownerId: (json['owner_id'] ?? json['ownerId'] ?? '').toString(),
      name: (json['name'] ?? 'Venue').toString(),
      nameAr: (json['name_ar'] ?? json['nameAr'])?.toString(),
      city: (json['city'] ?? json['governorate'] ?? 'Kafr El Sheikh').toString(),
      address: (json['address'] ?? json['location'])?.toString(),
      addressAr: (json['address_ar'] ?? json['locationAr'])?.toString(),
      lat: (json['lat'] as num?)?.toDouble() ?? (json['latitude'] as num?)?.toDouble(),
      lng: (json['lng'] as num?)?.toDouble() ?? (json['longitude'] as num?)?.toDouble(),
      categories: parsedCategories.isNotEmpty ? parsedCategories : ['playstation'],
      instapayAddress: (json['instapay_address'] ?? json['instapayAddress'] ?? json['instapayUsername'])?.toString(),
      walletNumber: (json['wallet_number'] ?? json['walletNumber'])?.toString(),
      subscriptionTier: json['subscription_tier']?.toString() ?? 'free',
      reliabilityScore: (json['reliability_score'] as num?)?.toDouble() ?? 5.0,
      units: rawUnits.map((u) {
        final map = u as Map<String, dynamic>;
        // Ensure venue_id is propagated if missing
        if (!map.containsKey('venue_id') && !map.containsKey('venueId')) {
          map['venue_id'] = venueId;
        }
        return BookableUnit.fromJson(map);
      }).toList(),
      phone: json['phone']?.toString(),
      imageUrl: (json['image_url'] ?? json['imageUrl'])?.toString(),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  HagzyVenue copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? nameAr,
    String? city,
    String? address,
    String? addressAr,
    double? lat,
    double? lng,
    List<String>? categories,
    String? instapayAddress,
    String? walletNumber,
    String? subscriptionTier,
    double? reliabilityScore,
    List<BookableUnit>? units,
    String? phone,
    String? imageUrl,
    DateTime? createdAt,
  }) =>
      HagzyVenue(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        name: name ?? this.name,
        nameAr: nameAr ?? this.nameAr,
        city: city ?? this.city,
        address: address ?? this.address,
        addressAr: addressAr ?? this.addressAr,
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        categories: categories ?? this.categories,
        instapayAddress: instapayAddress ?? this.instapayAddress,
        walletNumber: walletNumber ?? this.walletNumber,
        subscriptionTier: subscriptionTier ?? this.subscriptionTier,
        reliabilityScore: reliabilityScore ?? this.reliabilityScore,
        units: units ?? this.units,
        phone: phone ?? this.phone,
        imageUrl: imageUrl ?? this.imageUrl,
        createdAt: createdAt ?? this.createdAt,
      );
}

