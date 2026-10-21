import 'dart:math';
import 'package:flutter/material.dart';
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
    List<String>? galleryUrls,
    List<String>? amenities,
    List<VenueReview>? reviews,
    List<VenueItem>? items,
    List<SalonService>? services,
  })  : galleryUrls = galleryUrls ?? [],
        amenities = amenities ?? [],
        reviews = reviews ?? [],
        items = items ?? [],
        services = services ?? [];

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
  final List<String> galleryUrls;
  final List<String> amenities;
  final List<VenueReview> reviews;
  final List<VenueItem> items;
  final List<SalonService> services;

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

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));

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
      (isConfirmed ||
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
      );
}

Venue naderSalonSample() => Venue(
      id: 'nader-el-khawaga-kafr-el-sheikh',
      name: 'Nader El Khawaga',
      location: 'Kafr El Sheikh',
      type: VenueType.salon,
      depositPercent: 30,
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
          name: 'Haircut',
          minutes: 30,
          price: 150,
        ),
        SalonService(
          id: 'nader-beard-trim',
          name: 'Beard trim',
          minutes: 20,
          price: 100,
        ),
        SalonService(
          id: 'nader-haircut-beard',
          name: 'Haircut + beard',
          minutes: 45,
          price: 220,
        ),
        SalonService(
          id: 'nader-kids-haircut',
          name: 'Kids haircut',
          minutes: 25,
          price: 100,
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
