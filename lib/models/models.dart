import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/hagzy_theme.dart';

const egyptGovernorates = <(String, String)>[
  ('Cairo', 'القاهرة'),
  ('Giza', 'الجيزة'),
  ('Alexandria', 'الإسكندرية'),
  ('Dakahlia', 'الدقهلية'),
  ('Red Sea', 'البحر الأحمر'),
  ('Beheira', 'البحيرة'),
  ('Fayoum', 'الفيوم'),
  ('Gharbia', 'الغربية'),
  ('Ismailia', 'الإسماعيلية'),
  ('Menoufia', 'المنوفية'),
  ('Minya', 'المنيا'),
  ('Qalyubia', 'القليوبية'),
  ('New Valley', 'الوادي الجديد'),
  ('Suez', 'السويس'),
  ('Aswan', 'أسوان'),
  ('Assiut', 'أسيوط'),
  ('Beni Suef', 'بني سويف'),
  ('Port Said', 'بورسعيد'),
  ('Damietta', 'دمياط'),
  ('Sharkia', 'الشرقية'),
  ('South Sinai', 'جنوب سيناء'),
  ('Kafr El Sheikh', 'كفر الشيخ'),
  ('Matrouh', 'مطروح'),
  ('Luxor', 'الأقصر'),
  ('Qena', 'قنا'),
  ('North Sinai', 'شمال سيناء'),
  ('Sohag', 'سوهاج'),
];

const Map<String, (double, double)> kEgyptGovernorateCoordinates = {
  'Cairo': (30.0444, 31.2357),
  'Giza': (29.9870, 31.2118),
  'Alexandria': (31.2001, 29.9187),
  'Dakahlia': (31.0409, 31.3785),
  'Red Sea': (27.2579, 33.8116),
  'Beheira': (31.0364, 30.4689),
  'Fayoum': (29.3084, 30.8428),
  'Gharbia': (30.7865, 31.0004),
  'Ismailia': (30.5965, 32.2715),
  'Menoufia': (30.5972, 30.9876),
  'Minya': (28.0871, 30.7618),
  'Qalyubia': (30.2884, 31.2168),
  'New Valley': (25.4514, 30.5471),
  'Suez': (29.9668, 32.5498),
  'Aswan': (24.0889, 32.8998),
  'Assiut': (27.1783, 31.1859),
  'Beni Suef': (29.0661, 31.0994),
  'Port Said': (31.2653, 32.3019),
  'Damietta': (31.4175, 31.8144),
  'Sharkia': (30.5765, 31.5041),
  'South Sinai': (27.9158, 34.3299),
  'Kafr El Sheikh': (31.1107, 30.9388),
  'Matrouh': (31.3543, 27.2373),
  'Luxor': (25.6872, 32.6396),
  'Qena': (26.1551, 32.7160),
  'North Sinai': (31.1316, 33.7984),
  'Sohag': (26.5591, 31.6957),
};

double calculateDistanceKm(double lat1, double lon1, double lat2, double lon2) {
  const p = 0.017453292519943295;
  final a = 0.5 -
      cos((lat2 - lat1) * p) / 2 +
      cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
  return 12742 * asin(sqrt(a));
}

String localized(bool arabic, String english, String arabicText) =>
    arabic ? arabicText : english;

String governorateName(String english, bool arabic) {
  final governorate =
      egyptGovernorates.where((entry) => entry.$1 == english).firstOrNull;
  if (governorate == null) {
    return english == kAllEgyptAreas
        ? localized(arabic, 'Choose your area', 'كل محافظات مصر')
        : english;
  }
  return arabic ? governorate.$2 : governorate.$1;
}

enum VenueType { sports, salon, lounge }

extension VenueTypeLabel on VenueType {
  String get label => switch (this) {
        VenueType.sports => 'Padel / Football Club',
        VenueType.salon => 'Hair Salon / Barbershop',
        VenueType.lounge => 'PS5 / Billiards / Ping Pong Lounge',
      };

  IconData get icon => switch (this) {
        VenueType.sports => Icons.sports_tennis,
        VenueType.salon => Icons.content_cut,
        VenueType.lounge => Icons.sports_esports,
      };
}

class VenueItem {
  VenueItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.hourlyRate,
    this.multiRate = 0,
  });

  final String id;
  final String name;
  final String kind;
  final double hourlyRate;
  final double multiRate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'hourlyRate': hourlyRate,
        'multiRate': multiRate,
      };

  factory VenueItem.fromJson(Map<String, dynamic> json) => VenueItem(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        hourlyRate: (json['hourlyRate'] as num).toDouble(),
        multiRate: (json['multiRate'] as num?)?.toDouble() ?? 0,
      );
}

class SalonService {
  SalonService({
    required this.id,
    required this.name,
    required this.minutes,
    required this.price,
  });

  final String id;
  final String name;
  final int minutes;
  final double price;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'minutes': minutes, 'price': price};

  factory SalonService.fromJson(Map<String, dynamic> json) => SalonService(
        id: json['id'] as String,
        name: json['name'] as String,
        minutes: (json['minutes'] ?? json['durationMinutes'] ?? 30) as int,
        price: (json['price'] as num).toDouble(),
      );
}

class VenueReview {
  VenueReview({
    required this.id,
    required this.author,
    required this.rating,
    this.comment = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String author;
  final double rating;
  final String comment;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'author': author,
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt.toIso8601String(),
      };

  factory VenueReview.fromJson(Map<String, dynamic> json) => VenueReview(
        id: json['id'] as String? ?? generateId(),
        author: json['author'] as String? ?? 'Guest',
        rating: (json['rating'] as num?)?.toDouble() ?? 5.0,
        comment: json['comment'] as String? ?? '',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

class PromoOffer {
  const PromoOffer({
    required this.code,
    required this.englishDescription,
    required this.arabicDescription,
    required this.discountType,
    required this.value,
    this.minSpend = 0,
    this.maxDiscount = 9999,
    this.allowedCategory,
  });

  final String code;
  final String englishDescription;
  final String arabicDescription;
  final String discountType; // 'percent' or 'fixed'
  final double value;
  final double minSpend;
  final double maxDiscount;
  final VenueType? allowedCategory;

  double calculateDiscount(double subtotal, VenueType venueType) {
    if (allowedCategory != null && allowedCategory != venueType) return 0;
    if (subtotal < minSpend) return 0;
    double d = 0;
    if (discountType == 'percent') {
      d = subtotal * (value / 100);
    } else {
      d = value;
    }
    if (d > maxDiscount) d = maxDiscount;
    if (d > subtotal) d = subtotal;
    return d;
  }
}

const List<PromoOffer> kAvailablePromos = [
  PromoOffer(
    code: 'HAGZY50',
    englishDescription: '50 EGP off on bookings above 150 EGP',
    arabicDescription: 'خصم ٥٠ ج على الحجوزات أكثر من ١٥٠ ج',
    discountType: 'fixed',
    value: 50,
    minSpend: 150,
  ),
  PromoOffer(
    code: 'HAGZY20',
    englishDescription: '20% off up to 100 EGP',
    arabicDescription: 'خصم ٢٠٪ بحد أقصى ١٠٠ ج',
    discountType: 'percent',
    value: 20,
    maxDiscount: 100,
  ),
  PromoOffer(
    code: 'WELCOME',
    englishDescription: '25% off first booking (up to 120 EGP)',
    arabicDescription: 'خصم ٢٥٪ ترحيبي (حتى ١٢٠ ج)',
    discountType: 'percent',
    value: 25,
    maxDiscount: 120,
  ),
  PromoOffer(
    code: 'PADEL100',
    englishDescription: '100 EGP off sports & padel (min 350 EGP)',
    arabicDescription: 'خصم ١٠٠ ج لملاعب البادل والكرة (حجوزات ٣٥٠+ ج)',
    discountType: 'fixed',
    value: 100,
    minSpend: 350,
    allowedCategory: VenueType.sports,
  ),
];

class HagzyWallet {
  static const String keyWallet = 'hagzy_customer_wallet_balance';
  static const double defaultWelcomeBalance = 150.0;

  static Future<double> getBalance() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(keyWallet) ?? defaultWelcomeBalance;
  }

  static Future<double> addFunds(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getDouble(keyWallet) ?? defaultWelcomeBalance;
    final updated = current + amount;
    await prefs.setDouble(keyWallet, updated);
    return updated;
  }

  static Future<double> deductFunds(double amount) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getDouble(keyWallet) ?? defaultWelcomeBalance;
    final updated = (current - amount).clamp(0.0, double.infinity);
    await prefs.setDouble(keyWallet, updated);
    return updated;
  }
}

class Venue {
  Venue({
    required this.id,
    required this.name,
    required this.location,
    required this.type,
    this.ownerPhone = '',
    this.depositPercent = 25,
    this.imageUrl,
    this.description = '',
    this.googleMapsUrl = '',
    this.instaPayAddress = '',
    this.vodafoneCashNumber = '',
    this.openHour = 10,
    this.closeHour = 22,
    this.rating = 4.9,
    this.latitude,
    this.longitude,
    List<String>? staffMembers,
    List<String>? galleryUrls,
    List<String>? amenities,
    List<VenueReview>? reviews,
    List<VenueItem>? items,
    List<SalonService>? services,
  })  : galleryUrls = galleryUrls ?? [],
        amenities = amenities ?? [],
        reviews = reviews ?? [],
        items = items ?? [],
        services = services ?? [],
        staffMembers = staffMembers ?? [];

  final String id;
  final String name;
  final String location;
  final VenueType type;
  final String ownerPhone;
  final double depositPercent;
  final String? imageUrl;
  final String description;
  final String googleMapsUrl;
  final String instaPayAddress;
  final String vodafoneCashNumber;
  final int openHour;
  final int closeHour;
  final double rating;
  final double? latitude;
  final double? longitude;
  final List<String> staffMembers;
  final List<String> galleryUrls;
  final List<String> amenities;
  final List<VenueReview> reviews;
  final List<VenueItem> items;
  final List<SalonService> services;

  double get effectiveLatitude =>
      latitude ?? kEgyptGovernorateCoordinates[location]?.$1 ?? 30.0444;

  double get effectiveLongitude =>
      longitude ?? kEgyptGovernorateCoordinates[location]?.$2 ?? 31.2357;

  Venue copyWith({
    String? id,
    String? name,
    String? location,
    VenueType? type,
    String? ownerPhone,
    double? depositPercent,
    String? imageUrl,
    String? description,
    String? googleMapsUrl,
    String? instaPayAddress,
    String? vodafoneCashNumber,
    int? openHour,
    int? closeHour,
    double? rating,
    double? latitude,
    double? longitude,
    List<String>? staffMembers,
    List<String>? galleryUrls,
    List<String>? amenities,
    List<VenueReview>? reviews,
    List<VenueItem>? items,
    List<SalonService>? services,
  }) =>
      Venue(
        id: id ?? this.id,
        name: name ?? this.name,
        location: location ?? this.location,
        type: type ?? this.type,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        depositPercent: depositPercent ?? this.depositPercent,
        imageUrl: imageUrl ?? this.imageUrl,
        description: description ?? this.description,
        googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
        instaPayAddress: instaPayAddress ?? this.instaPayAddress,
        vodafoneCashNumber: vodafoneCashNumber ?? this.vodafoneCashNumber,
        openHour: openHour ?? this.openHour,
        closeHour: closeHour ?? this.closeHour,
        rating: rating ?? this.rating,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        staffMembers: staffMembers ?? this.staffMembers,
        galleryUrls: galleryUrls ?? this.galleryUrls,
        amenities: amenities ?? this.amenities,
        reviews: reviews ?? this.reviews,
        items: items ?? this.items,
        services: services ?? this.services,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'type': type.name,
        'ownerPhone': ownerPhone,
        'depositPercent': depositPercent,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        if (description.isNotEmpty) 'description': description,
        if (googleMapsUrl.isNotEmpty) 'googleMapsUrl': googleMapsUrl,
        if (instaPayAddress.isNotEmpty) 'instaPayAddress': instaPayAddress,
        if (vodafoneCashNumber.isNotEmpty)
          'vodafoneCashNumber': vodafoneCashNumber,
        'openHour': openHour,
        'closeHour': closeHour,
        'rating': rating,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (staffMembers.isNotEmpty) 'staffMembers': staffMembers,
        if (galleryUrls.isNotEmpty) 'galleryUrls': galleryUrls,
        if (amenities.isNotEmpty) 'amenities': amenities,
        if (reviews.isNotEmpty)
          'reviews': reviews.map((r) => r.toJson()).toList(),
        'items': items.map((item) => item.toJson()).toList(),
        'services': services.map((service) => service.toJson()).toList(),
      };

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String? ?? '',
        type: VenueType.values.byName(json['type'] as String),
        ownerPhone: json['ownerPhone'] as String? ?? '',
        depositPercent: (json['depositPercent'] as num?)?.toDouble() ?? 25,
        imageUrl: json['imageUrl'] as String?,
        description: json['description'] as String? ?? '',
        googleMapsUrl: json['googleMapsUrl'] as String? ?? '',
        instaPayAddress: json['instaPayAddress'] as String? ?? '',
        vodafoneCashNumber: json['vodafoneCashNumber'] as String? ?? '',
        openHour: (json['openHour'] as num?)?.toInt() ?? 10,
        closeHour: (json['closeHour'] as num?)?.toInt() ?? 22,
        rating: (json['rating'] as num?)?.toDouble() ?? 4.9,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        staffMembers:
            (json['staffMembers'] as List<dynamic>? ?? []).cast<String>(),
        galleryUrls:
            (json['galleryUrls'] as List<dynamic>? ?? []).cast<String>(),
        amenities:
            (json['amenities'] as List<dynamic>? ?? []).cast<String>(),
        reviews: (json['reviews'] as List<dynamic>? ?? [])
            .map((r) => VenueReview.fromJson(r as Map<String, dynamic>))
            .toList(),
        items: (json['items'] as List<dynamic>? ?? [])
            .map((item) => VenueItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        services: (json['services'] as List<dynamic>? ?? [])
            .map((item) => SalonService.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class Booking {
  Booking({
    required this.id,
    required this.venueId,
    required this.itemId,
    required this.customer,
    required this.startsAt,
    required this.durationMinutes,
    required this.price,
    this.serviceNames = const [],
    this.splitCount = 1,
    this.multiController = false,
    this.cancelled = false,
    this.phone = '',
    this.email = '',
    this.dueNow,
    this.status = 'pending_payment',
    this.paymentStatus = 'unpaid',
    this.holdExpiresAt,
    this.paymentMethod = '',
    this.paymentReference = '',
    this.promoCode = '',
    this.discountAmount = 0,
    this.staffMember = '',
    this.blockReason = '',
  });

  final String id;
  final String venueId;
  final String itemId;
  final String customer;
  final DateTime startsAt;
  final int durationMinutes;
  final double price;
  final List<String> serviceNames;
  final int splitCount;
  final bool multiController;
  final bool cancelled;
  final String phone;
  final String email;
  final double? dueNow;
  final String status;
  final String paymentStatus;
  final DateTime? holdExpiresAt;
  final String paymentMethod;
  final String paymentReference;
  final String promoCode;
  final double discountAmount;
  final String staffMember;
  final String blockReason;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

  bool get isBlocked =>
      blockReason.isNotEmpty || customer.startsWith('[BLOCKED]');

  bool get isPendingPayment =>
      status == 'pending_payment' &&
      paymentStatus != 'paid' &&
      (holdExpiresAt == null || holdExpiresAt!.isAfter(DateTime.now()));

  bool get isPendingVerification =>
      isPendingPayment &&
      (paymentStatus == 'pending' || paymentReference.trim().isNotEmpty);

  bool get isConfirmed =>
      status == 'confirmed' &&
      !cancelled &&
      (paymentStatus == 'paid' || dueNow == 0);

  bool get blocksAvailability =>
      !cancelled &&
      (isBlocked ||
          isConfirmed ||
          (status == 'pending_payment' &&
              (holdExpiresAt == null ||
                  holdExpiresAt!.isAfter(DateTime.now()))));

  Booking copyWith({
    String? id,
    String? venueId,
    String? itemId,
    String? customer,
    DateTime? startsAt,
    int? durationMinutes,
    double? price,
    List<String>? serviceNames,
    int? splitCount,
    bool? multiController,
    bool? cancelled,
    String? phone,
    String? email,
    double? dueNow,
    String? status,
    String? paymentStatus,
    DateTime? holdExpiresAt,
    bool clearHoldExpiresAt = false,
    String? paymentMethod,
    String? paymentReference,
    String? promoCode,
    double? discountAmount,
    String? staffMember,
    String? blockReason,
  }) =>
      Booking(
        id: id ?? this.id,
        venueId: venueId ?? this.venueId,
        itemId: itemId ?? this.itemId,
        customer: customer ?? this.customer,
        startsAt: startsAt ?? this.startsAt,
        durationMinutes: durationMinutes ?? this.durationMinutes,
        price: price ?? this.price,
        serviceNames: serviceNames ?? this.serviceNames,
        splitCount: splitCount ?? this.splitCount,
        multiController: multiController ?? this.multiController,
        cancelled: cancelled ?? this.cancelled,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        dueNow: dueNow ?? this.dueNow,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        holdExpiresAt:
            clearHoldExpiresAt ? null : (holdExpiresAt ?? this.holdExpiresAt),
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentReference: paymentReference ?? this.paymentReference,
        promoCode: promoCode ?? this.promoCode,
        discountAmount: discountAmount ?? this.discountAmount,
        staffMember: staffMember ?? this.staffMember,
        blockReason: blockReason ?? this.blockReason,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'venueId': venueId,
        'itemId': itemId,
        'customer': customer,
        'startsAt': startsAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'price': price,
        'serviceNames': serviceNames,
        'splitCount': splitCount,
        'multiController': multiController,
        'cancelled': cancelled,
        'phone': phone,
        'email': email,
        'dueNow': dueNow,
        'status': status,
        'paymentStatus': paymentStatus,
        'holdExpiresAt': holdExpiresAt?.toIso8601String(),
        if (paymentMethod.isNotEmpty) 'paymentMethod': paymentMethod,
        if (paymentReference.isNotEmpty) 'paymentReference': paymentReference,
        if (promoCode.isNotEmpty) 'promoCode': promoCode,
        if (discountAmount > 0) 'discountAmount': discountAmount,
        if (staffMember.isNotEmpty) 'staffMember': staffMember,
        if (blockReason.isNotEmpty) 'blockReason': blockReason,
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        venueId: json['venueId'] as String,
        itemId: json['itemId'] as String,
        customer: json['customer'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String),
        durationMinutes: json['durationMinutes'] as int,
        price: (json['price'] as num).toDouble(),
        serviceNames:
            (json['serviceNames'] as List<dynamic>? ?? []).cast<String>(),
        splitCount: json['splitCount'] as int? ?? 1,
        multiController: json['multiController'] as bool? ?? false,
        cancelled: json['cancelled'] as bool? ?? false,
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        dueNow: (json['dueNow'] as num?)?.toDouble(),
        status: json['status'] as String? ??
            ((json['cancelled'] as bool? ?? false)
                ? 'cancelled'
                : 'pending_payment'),
        paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
        holdExpiresAt: DateTime.tryParse(
              json['holdExpiresAt'] as String? ?? '',
            ) ??
            ((json['status'] as String? ?? 'pending_payment') ==
                    'pending_payment'
                ? DateTime.now()
                : null),
        paymentMethod: json['paymentMethod'] as String? ?? '',
        paymentReference: json['paymentReference'] as String? ?? '',
        promoCode: json['promoCode'] as String? ?? '',
        discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
        staffMember: json['staffMember'] as String? ?? '',
        blockReason: json['blockReason'] as String? ?? '',
      );
}

Venue naderSalonSample() => Venue(
      id: 'nader-el-khawaga-kafr-el-sheikh',
      name: 'Nader El Khawaga',
      location: 'Kafr El Sheikh',
      type: VenueType.salon,
      depositPercent: 30,
      latitude: 31.1107,
      longitude: 30.9388,
      staffMembers: const [
        'كابتن نادر (Master Barber)',
        'أحمد عصام (Senior Stylist)',
        'مينا فوزي (Beard Specialist)',
        'Any Specialist / أي مصفف متاح',
      ],
      imageUrl:
          'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=1000&q=80',
      galleryUrls: const [
        'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=800&q=80',
        'https://images.unsplash.com/photo-1585747860715-2ba37e788b70?auto=format&fit=crop&w=800&q=80',
        'https://images.unsplash.com/photo-1621605815971-fbc98d665033?auto=format&fit=crop&w=800&q=80',
      ],
      googleMapsUrl:
          'https://www.google.com/maps/search/?api=1&query=Nader+El+Khawaga+Kafr+El+Sheikh',
      description:
          'Premier men’s grooming & barbershop in Kafr El Sheikh offering precision haircuts, beard styling, and VIP chair service.',
      instaPayAddress: 'nader.salon@instapay',
      vodafoneCashNumber: '01024129393',
      amenities: const ['AC', 'Wi-Fi', 'VIP Chair', 'Kids Friendly'],
      items: [
        VenueItem(
          id: 'nader-el-khawaga-chair-1',
          name: 'Barber Chair 1',
          kind: 'Barber / chair',
          hourlyRate: 150,
        ),
      ],
      services: [
        SalonService(
          id: 'nader-haircut',
          name: 'Haircut (قص شعر كلاسيك)',
          minutes: 30,
          price: 150,
        ),
        SalonService(
          id: 'nader-beard-trim',
          name: 'Beard trim & shaping (تحديد لحية بالموس)',
          minutes: 20,
          price: 100,
        ),
        SalonService(
          id: 'nader-vip-grooming',
          name: 'VIP Grooming Package (باقة العريس VIP)',
          minutes: 60,
          price: 350,
        ),
        SalonService(
          id: 'nader-haircut-beard',
          name: 'Haircut + beard (شعر ولحية)',
          minutes: 45,
          price: 220,
        ),
        SalonService(
          id: 'nader-kids-haircut',
          name: 'Kids haircut (قص أطفال)',
          minutes: 25,
          price: 100,
        ),
        SalonService(
          id: 'nader-facial-scrub',
          name: 'Facial Steam & Scrub (حمام بخار وسكراب)',
          minutes: 25,
          price: 120,
        ),
      ],
    );

List<Venue> defaultPrototypeVenues() => [
      naderSalonSample(),
      Venue(
        id: 'smash-padel-tagamoa',
        name: 'Smash Padel Club',
        location: 'Cairo',
        type: VenueType.sports,
        ownerPhone: '01012345678',
        depositPercent: 25,
        latitude: 30.0298,
        longitude: 31.4789,
        staffMembers: const [
          'Court Marshal / مشرف الملعب',
          'Padel Coach Omar / كابتن عمر',
        ],
        imageUrl:
            'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=1000&q=80',
        galleryUrls: const [
          'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=800&q=80',
          'https://images.unsplash.com/photo-1554068865-24cecd4e34b8?auto=format&fit=crop&w=800&q=80',
          'https://images.unsplash.com/photo-1574629810360-7efbbe195018?auto=format&fit=crop&w=800&q=80',
        ],
        googleMapsUrl:
            'https://www.google.com/maps/search/?api=1&query=Smash+Padel+Club+New+Cairo',
        description:
            'Championship panoramic padel courts in New Cairo with LED floodlights, pro racket rentals, and specialty coffee lounge.',
        instaPayAddress: 'smash.padel@instapay',
        vodafoneCashNumber: '01012345678',
        amenities: const ['Parking', 'Café', 'Locker Room', 'Racket Rental'],
        items: [
          VenueItem(
            id: 'smash-court-1',
            name: 'Court 1 (Panoramic)',
            kind: 'Padel court',
            hourlyRate: 450,
          ),
          VenueItem(
            id: 'smash-court-2',
            name: 'Court 2 (Standard)',
            kind: 'Padel court',
            hourlyRate: 400,
          ),
        ],
      ),
      Venue(
        id: 'bunker-lounge-maadi',
        name: 'The Bunker VIP Lounge',
        location: 'Cairo',
        type: VenueType.lounge,
        ownerPhone: '01098765432',
        depositPercent: 20,
        latitude: 29.9602,
        longitude: 31.2569,
        staffMembers: const [
          'VIP Lounge Host / مسؤول الصالة',
        ],
        imageUrl:
            'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=1000&q=80',
        galleryUrls: const [
          'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=800&q=80',
          'https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=800&q=80',
          'https://images.unsplash.com/photo-1538481199705-c710c4e965fc?auto=format&fit=crop&w=800&q=80',
        ],
        googleMapsUrl:
            'https://www.google.com/maps/search/?api=1&query=Maadi+Gaming+Lounge+Cairo',
        description:
            'Soundproof PS5 VIP suites with 85-inch 4K OLED screens, tournament billiards tables, and full snack & drink service.',
        instaPayAddress: 'bunker.lounge@instapay',
        vodafoneCashNumber: '01098765432',
        amenities: const [
          '85" 4K TV',
          'AC',
          'Snacks & Drinks',
          'High-Speed Wi-Fi',
        ],
        items: [
          VenueItem(
            id: 'bunker-ps5-vip',
            name: 'PS5 VIP Suite (85-inch 4K)',
            kind: 'PS5 room',
            hourlyRate: 180,
            multiRate: 240,
          ),
          VenueItem(
            id: 'bunker-billiards-1',
            name: 'Championship Billiards Table',
            kind: 'Billiards table',
            hourlyRate: 140,
          ),
        ],
      ),
    ];

List<Venue> upsertNaderSalon(List<Venue> venues) {
  if (!kSeedNaderSalon) return venues;
  final sample = naderSalonSample();
  final matches = venues
      .where((venue) =>
          venue.id == sample.id ||
          (venue.name.trim().toLowerCase() == sample.name.toLowerCase() &&
              venue.location.trim().toLowerCase() ==
                  sample.location.toLowerCase()))
      .toList();
  if (matches.isEmpty) return [...venues, sample];

  final primary = matches.first;
  final items = <VenueItem>[];
  final services = <SalonService>[];
  for (final value in [...matches, sample]) {
    for (final item in value.items) {
      if (!items.any((saved) =>
          saved.id == item.id ||
          saved.name.trim().toLowerCase() == item.name.trim().toLowerCase())) {
        items.add(item);
      }
    }
    for (final service in value.services) {
      if (!services.any((saved) =>
          saved.id == service.id ||
          saved.name.trim().toLowerCase() ==
              service.name.trim().toLowerCase())) {
        services.add(service);
      }
    }
  }
  final merged = primary.copyWith(
    name: sample.name,
    location: sample.location,
    type: VenueType.salon,
    depositPercent: sample.depositPercent,
    items: items,
    services: services,
  );
  final firstMatch = venues.indexWhere((venue) => matches.contains(venue));
  return [
    ...venues.take(firstMatch),
    merged,
    ...venues.skip(firstMatch).where((venue) => !matches.contains(venue)),
  ];
}

String? requiredValidator(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

String? positiveNumberValidator(String? value) {
  final number = double.tryParse(value ?? '');
  return number == null || !number.isFinite || number <= 0
      ? 'Enter an amount greater than zero'
      : null;
}

String? phoneValidator(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length >= 7 ? null : 'Enter a valid phone number';
}

String generateId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';

String formatMoney(double amount) => amount.toStringAsFixed(2);

String formatDateTime(DateTime value) =>
    '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
