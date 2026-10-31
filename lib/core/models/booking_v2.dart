import 'bookable_unit.dart';

/// Booking status lifecycle enum
enum BookingStatus {
  pendingDeposit('pending_deposit'),
  confirmed('confirmed'),
  cancelledGrace('cancelled_grace'),
  cancelledUser('cancelled_user'),
  completed('completed'),
  noShow('no_show');

  final String value;
  const BookingStatus(this.value);

  static BookingStatus fromString(String? raw) {
    if (raw == null) return BookingStatus.pendingDeposit;
    final normalized = raw.trim().toLowerCase();
    for (final s in BookingStatus.values) {
      if (s.value == normalized || s.name.toLowerCase() == normalized) {
        return s;
      }
    }
    return BookingStatus.pendingDeposit;
  }
}

/// Payment method types supported by Hagzy automated engine
enum PaymentMethod {
  instapayOcr('instapay_ocr'),
  vodafoneCashOcr('vodafone_cash_ocr'),
  paymobWebhook('paymob_webhook'),
  hagzyWallet('hagzy_wallet'),
  payAtVenue('pay_at_venue');

  final String value;
  const PaymentMethod(this.value);

  static PaymentMethod fromString(String? raw) {
    if (raw == null) return PaymentMethod.instapayOcr;
    final normalized = raw.trim().toLowerCase();
    for (final p in PaymentMethod.values) {
      if (p.value == normalized || p.name.toLowerCase() == normalized) {
        return p;
      }
    }
    return PaymentMethod.instapayOcr;
  }
}

/// Universal Booking Model with Social "El-Shilla", Open Lobby & Grace Cancellation
class HagzyBooking {
  final String id;
  final String unitId;
  final String venueId;
  final String hostUserId;
  final String hostName;
  final String hostPhone;
  final DateTime startTime;
  final DateTime endTime;
  final int headcount;
  final List<ServiceMenuItem> selectedServices;
  final List<UnitAddon> selectedAddons;

  // Social & Open Match ("Na2esna" / "Open Table" / Challenger) Mechanics
  final bool isOpenLobby;
  final int totalSlots;
  final int filledSlots;
  final List<String> neededRoles; // e.g., ['1v1_challenger'], ['GK', 'DEF'], ['2_escape_room_players']
  final String? lobbyTitle; // e.g., "Thursday Night PS5 FIFA Tourney"
  final List<String> participantIds;

  // Financials & Automated Verification
  final double totalPriceEgp;
  final double depositRequiredEgp;
  final double serviceFeeEgp;
  final PaymentMethod paymentMethod;
  final String? receiptOcrRef; // Prevents duplicate receipt screenshot fraud
  final BookingStatus status;
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;

  // Metadata snapshots for fast offline rendering
  final String? venueName;
  final String? unitName;
  final String? venueCity;

  const HagzyBooking({
    required this.id,
    required this.unitId,
    required this.venueId,
    required this.hostUserId,
    this.hostName = 'Hagzy Member',
    this.hostPhone = '',
    required this.startTime,
    required this.endTime,
    this.headcount = 1,
    this.selectedServices = const [],
    this.selectedAddons = const [],
    this.isOpenLobby = false,
    this.totalSlots = 1,
    this.filledSlots = 1,
    this.neededRoles = const [],
    this.lobbyTitle,
    this.participantIds = const [],
    required this.totalPriceEgp,
    required this.depositRequiredEgp,
    this.serviceFeeEgp = 15.0,
    this.paymentMethod = PaymentMethod.instapayOcr,
    this.receiptOcrRef,
    this.status = BookingStatus.pendingDeposit,
    required this.createdAt,
    this.confirmedAt,
    this.cancelledAt,
    this.venueName,
    this.unitName,
    this.venueCity,
  });

  /// Duration in minutes
  int get durationMinutes => endTime.difference(startTime).inMinutes;

  /// Contrast Anchoring: Remaining balance paid in cash at the venue
  double get remainingCashAtVenueEgp =>
      (totalPriceEgp - depositRequiredEgp).clamp(0.0, double.infinity);

  /// Per-person price split
  double get perPersonShareEgp {
    final divisor = (isOpenLobby && totalSlots > 1)
        ? totalSlots
        : (headcount > 0 ? headcount : 1);
    return totalPriceEgp / divisor;
  }

  /// Per-person deposit split
  double get perPersonDepositEgp {
    final divisor = (isOpenLobby && totalSlots > 1)
        ? totalSlots
        : (headcount > 0 ? headcount : 1);
    return depositRequiredEgp / divisor;
  }

  /// Social Lobby remaining open slots
  int get openSlotsRemaining =>
      (totalSlots - filledSlots).clamp(0, totalSlots);

  bool get isLobbyFull => filledSlots >= totalSlots;

  /// 10-Minute Free Cancellation Grace Period
  /// Active if confirmed within the last 10 minutes (zero-anxiety coordination on WhatsApp)
  bool isGracePeriodActive([DateTime? now]) {
    if (status != BookingStatus.confirmed) return false;
    final referenceTime = confirmedAt ?? createdAt;
    final current = now ?? DateTime.now();
    final elapsedSecs = current.difference(referenceTime).inSeconds;
    return elapsedSecs >= 0 && elapsedSecs < 600; // 600s = 10 mins
  }

  /// Remaining seconds in the 10-minute grace cancellation period
  int graceSecondsRemaining([DateTime? now]) {
    if (!isGracePeriodActive(now)) return 0;
    final referenceTime = confirmedAt ?? createdAt;
    final current = now ?? DateTime.now();
    final elapsedSecs = current.difference(referenceTime).inSeconds;
    return (600 - elapsedSecs).clamp(0, 600);
  }

  /// Deep link URL for WhatsApp sharing
  String get deepLinkUrl => 'https://hagzy.app/join/$id';

  /// Generates pre-filled viral WhatsApp message with slot details & split
  String buildWhatsAppShareMessage({String? customVenueName}) {
    final vName = customVenueName ?? venueName ?? 'Hagzy Lounge';
    final perPerson = perPersonShareEgp.toStringAsFixed(0);
    final buffer = StringBuffer();

    if (isOpenLobby && lobbyTitle != null && lobbyTitle!.isNotEmpty) {
      buffer.writeln('🎮 *${lobbyTitle!}*');
    } else {
      buffer.writeln('🔥 *حجز الشلة على حجزي (Hagzy)*');
    }

    buffer.writeln('📍 المكان: $vName');
    if (unitName != null) buffer.writeln('🚪 الغرفة/الطاولة: $unitName');
    buffer.writeln('⏰ الميعاد: ${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}');
    buffer.writeln('💰 نصيب الفرد: $perPerson ج.م فقط');
    buffer.writeln('');
    buffer.writeln('اضغط على اللينك عشان تثبت مكانك في الشلة:');
    buffer.writeln(deepLinkUrl);

    return buffer.toString();
  }

  /// Cancel booking under grace period (refunds 100% deposit to Hagzy Wallet)
  HagzyBooking cancelUnderGrace([DateTime? now]) => copyWith(
        status: BookingStatus.cancelledGrace,
        cancelledAt: now ?? DateTime.now(),
      );

  /// Confirm booking after OCR/Gateway deposit verification
  HagzyBooking confirmDeposit({String? ocrRef, DateTime? now}) => copyWith(
        status: BookingStatus.confirmed,
        receiptOcrRef: ocrRef ?? receiptOcrRef,
        confirmedAt: now ?? DateTime.now(),
      );

  /// Add participant to social lobby
  HagzyBooking addParticipant(String userId) {
    if (participantIds.contains(userId) || isLobbyFull) return this;
    final updated = List<String>.from(participantIds)..add(userId);
    return copyWith(
      participantIds: updated,
      filledSlots: filledSlots + 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'unit_id': unitId,
        'venue_id': venueId,
        'host_user_id': hostUserId,
        'host_name': hostName,
        'host_phone': hostPhone,
        'start_time': startTime.toIso8601String(),
        'end_time': endTime.toIso8601String(),
        'headcount': headcount,
        'selected_services': selectedServices.map((s) => s.toJson()).toList(),
        'selected_addons': selectedAddons.map((a) => a.toJson()).toList(),
        'is_open_lobby': isOpenLobby,
        'total_slots': totalSlots,
        'filled_slots': filledSlots,
        'needed_roles': neededRoles,
        if (lobbyTitle != null) 'lobby_title': lobbyTitle,
        'participant_ids': participantIds,
        'total_price_egp': totalPriceEgp,
        'deposit_required_egp': depositRequiredEgp,
        'service_fee_egp': serviceFeeEgp,
        'payment_method': paymentMethod.value,
        if (receiptOcrRef != null) 'receipt_ocr_ref': receiptOcrRef,
        'status': status.value,
        'created_at': createdAt.toIso8601String(),
        if (confirmedAt != null) 'confirmed_at': confirmedAt!.toIso8601String(),
        if (cancelledAt != null) 'cancelled_at': cancelledAt!.toIso8601String(),
        if (venueName != null) 'venue_name': venueName,
        if (unitName != null) 'unit_name': unitName,
        if (venueCity != null) 'venue_city': venueCity,
      };

  factory HagzyBooking.fromJson(Map<String, dynamic> json) {
    final rawServices = json['selected_services'] as List<dynamic>? ?? [];
    final rawAddons = json['selected_addons'] as List<dynamic>? ?? [];
    final rawRoles = json['needed_roles'] as List<dynamic>? ?? [];
    final rawParticipants = json['participant_ids'] as List<dynamic>? ?? [];

    DateTime start = DateTime.now();
    if (json['start_time'] != null) {
      start = DateTime.tryParse(json['start_time'].toString()) ?? DateTime.now();
    } else if (json['startsAt'] != null) {
      start = DateTime.tryParse(json['startsAt'].toString()) ?? DateTime.now();
    }

    DateTime end = start.add(const Duration(hours: 1));
    if (json['end_time'] != null) {
      end = DateTime.tryParse(json['end_time'].toString()) ?? end;
    } else if (json['durationMinutes'] != null) {
      end = start.add(Duration(minutes: (json['durationMinutes'] as num).toInt()));
    }

    return HagzyBooking(
      id: json['id']?.toString() ?? '',
      unitId: (json['unit_id'] ?? json['itemId'] ?? '').toString(),
      venueId: (json['venue_id'] ?? json['venueId'] ?? '').toString(),
      hostUserId: (json['host_user_id'] ?? json['customer_id'] ?? json['customerId'] ?? '').toString(),
      hostName: (json['host_name'] ?? json['customer'] ?? 'Hagzy Member').toString(),
      hostPhone: (json['host_phone'] ?? json['phone'] ?? '').toString(),
      startTime: start,
      endTime: end,
      headcount: (json['headcount'] ?? json['splitCount'] as num?)?.toInt() ?? 1,
      selectedServices: rawServices
          .map((s) => ServiceMenuItem.fromJson(s as Map<String, dynamic>))
          .toList(),
      selectedAddons: rawAddons
          .map((a) => UnitAddon.fromJson(a as Map<String, dynamic>))
          .toList(),
      isOpenLobby: json['is_open_lobby'] == true,
      totalSlots: (json['total_slots'] as num?)?.toInt() ?? 1,
      filledSlots: (json['filled_slots'] as num?)?.toInt() ?? 1,
      neededRoles: rawRoles.map((r) => r.toString()).toList(),
      lobbyTitle: json['lobby_title']?.toString(),
      participantIds: rawParticipants.map((p) => p.toString()).toList(),
      totalPriceEgp: (json['total_price_egp'] ?? json['price'] as num?)?.toDouble() ?? 0.0,
      depositRequiredEgp: (json['deposit_required_egp'] ?? json['dueNow'] as num?)?.toDouble() ?? 0.0,
      serviceFeeEgp: (json['service_fee_egp'] as num?)?.toDouble() ?? 15.0,
      paymentMethod: PaymentMethod.fromString(json['payment_method']?.toString()),
      receiptOcrRef: json['receipt_ocr_ref']?.toString() ?? json['paymentReference']?.toString(),
      status: BookingStatus.fromString(json['status']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      confirmedAt: json['confirmed_at'] != null
          ? DateTime.tryParse(json['confirmed_at'].toString())
          : null,
      cancelledAt: json['cancelled_at'] != null
          ? DateTime.tryParse(json['cancelled_at'].toString())
          : null,
      venueName: json['venue_name']?.toString(),
      unitName: json['unit_name']?.toString(),
      venueCity: json['venue_city']?.toString(),
    );
  }

  HagzyBooking copyWith({
    String? id,
    String? unitId,
    String? venueId,
    String? hostUserId,
    String? hostName,
    String? hostPhone,
    DateTime? startTime,
    DateTime? endTime,
    int? headcount,
    List<ServiceMenuItem>? selectedServices,
    List<UnitAddon>? selectedAddons,
    bool? isOpenLobby,
    int? totalSlots,
    int? filledSlots,
    List<String>? neededRoles,
    String? lobbyTitle,
    List<String>? participantIds,
    double? totalPriceEgp,
    double? depositRequiredEgp,
    double? serviceFeeEgp,
    PaymentMethod? paymentMethod,
    String? receiptOcrRef,
    BookingStatus? status,
    DateTime? createdAt,
    DateTime? confirmedAt,
    DateTime? cancelledAt,
    String? venueName,
    String? unitName,
    String? venueCity,
  }) =>
      HagzyBooking(
        id: id ?? this.id,
        unitId: unitId ?? this.unitId,
        venueId: venueId ?? this.venueId,
        hostUserId: hostUserId ?? this.hostUserId,
        hostName: hostName ?? this.hostName,
        hostPhone: hostPhone ?? this.hostPhone,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        headcount: headcount ?? this.headcount,
        selectedServices: selectedServices ?? this.selectedServices,
        selectedAddons: selectedAddons ?? this.selectedAddons,
        isOpenLobby: isOpenLobby ?? this.isOpenLobby,
        totalSlots: totalSlots ?? this.totalSlots,
        filledSlots: filledSlots ?? this.filledSlots,
        neededRoles: neededRoles ?? this.neededRoles,
        lobbyTitle: lobbyTitle ?? this.lobbyTitle,
        participantIds: participantIds ?? this.participantIds,
        totalPriceEgp: totalPriceEgp ?? this.totalPriceEgp,
        depositRequiredEgp: depositRequiredEgp ?? this.depositRequiredEgp,
        serviceFeeEgp: serviceFeeEgp ?? this.serviceFeeEgp,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        receiptOcrRef: receiptOcrRef ?? this.receiptOcrRef,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        confirmedAt: confirmedAt ?? this.confirmedAt,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        venueName: venueName ?? this.venueName,
        unitName: unitName ?? this.unitName,
        venueCity: venueCity ?? this.venueCity,
      );
}

