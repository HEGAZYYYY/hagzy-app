import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';

void main() {
  group('Phase 1: Polymorphic BookableUnit & Pricing Modes', () {
    test('1. hourly_flat: Sports Courts, Billiards, Ping Pong', () {
      final unit = BookableUnit(
        id: 'unit_court_1',
        venueId: 'venue_1',
        category: 'court',
        unitName: 'Al-Ahly 5v5 Turf Pitch',
        pricingMode: PricingMode.hourlyFlat,
        basePriceEgp: 300.0,
        minCapacity: 10,
        maxCapacity: 14,
      );

      // 2 hours, 10 players
      final calc = unit.calculatePricing(headcount: 10, durationHours: 2.0);

      expect(calc.totalPriceEgp, 600.0);
      expect(calc.perPersonShareEgp, 60.0); // 600 / 10 = 60 EGP / player
      expect(calc.depositRequiredEgp, 60.0); // 10% anchor of 600 = 60 EGP
      expect(calc.remainingCashAtVenueEgp, 540.0);
      expect(calc.totalDurationMins, 120);
    });

    test('2. hourly_tiered_capacity: PlayStation VIP Lounge', () {
      final ps5Unit = BookableUnit(
        id: 'unit_ps5_vip',
        venueId: 'venue_lounge',
        category: 'playstation',
        unitName: 'VIP Room 1 (PS5 & 65" 4K)',
        pricingMode: PricingMode.hourlyTieredCapacity,
        basePriceEgp: 60.0,
        pricingTiers: {
          '2': 60, // 2 players = 60 EGP/hr
          '4': 100, // 4 players = 100 EGP/hr
        },
        addons: [
          const UnitAddon(id: 'add_ctrl', name: 'Extra DualSense Controller', price: 20),
        ],
        minCapacity: 1,
        maxCapacity: 4,
      );

      // 2 players, 1 hour
      final calc2 = ps5Unit.calculatePricing(headcount: 2, durationHours: 1.0);
      expect(calc2.totalPriceEgp, 60.0);
      expect(calc2.perPersonShareEgp, 30.0);

      // 4 players, 2 hours + 1 extra controller addon (20 EGP)
      final calc4 = ps5Unit.calculatePricing(
        headcount: 4,
        durationHours: 2.0,
        selectedAddonIds: ['add_ctrl'],
      );
      // 100 * 2 hours = 200 + 20 addon = 220 EGP
      expect(calc4.totalPriceEgp, 220.0);
      expect(calc4.perPersonShareEgp, 55.0); // 220 / 4 = 55 EGP / player
    });

    test('3. per_person_tiered: Escape Rooms & Group Hangouts', () {
      final escapeUnit = BookableUnit(
        id: 'unit_escape_1',
        venueId: 'venue_escape',
        category: 'escape_room',
        unitName: 'The Pharaoh\'s Tomb Mystery',
        pricingMode: PricingMode.perPersonTiered,
        basePriceEgp: 220.0,
        pricingTiers: {
          '3': 220, // 3 players: 220 EGP / person (Total 660)
          '4': 200, // 4 players: 200 EGP / person (Total 800)
          '5': 180, // 5 players: 180 EGP / person (Total 900)
          '6': 160, // 6 players: 160 EGP / person (Total 960)
        },
        minCapacity: 3,
        maxCapacity: 8,
      );

      // 3 players: cost per person is 220
      final calc3 = escapeUnit.calculatePricing(headcount: 3);
      expect(calc3.rateAppliedEgp, 220.0);
      expect(calc3.totalPriceEgp, 660.0);
      expect(calc3.perPersonShareEgp, 220.0);

      // 6 players: cost per person drops to 160 EGP!
      final calc6 = escapeUnit.calculatePricing(headcount: 6);
      expect(calc6.rateAppliedEgp, 160.0);
      expect(calc6.totalPriceEgp, 960.0);
      expect(calc6.perPersonShareEgp, 160.0);
    });

    test('4. time_pass: Workspaces & Study Zones', () {
      final workspaceUnit = BookableUnit(
        id: 'desk_silent_1',
        venueId: 'venue_hub',
        category: 'workspace',
        unitName: 'Focus Silent Study Desk #4',
        pricingMode: PricingMode.timePass,
        basePriceEgp: 25.0,
        pricingTiers: {
          'hourly': 25,
          'day_pass': 90,
          'weekly': 450,
        },
        minCapacity: 1,
        maxCapacity: 1,
      );

      // Hourly booking: 3 hours, 1 person
      final calcHourly = workspaceUnit.calculatePricing(
        headcount: 1,
        durationHours: 3.0,
        timePassType: 'hourly',
      );
      expect(calcHourly.totalPriceEgp, 75.0); // 25 * 3 = 75

      // Full-day pass booking: flat 90 EGP for the day
      final calcDayPass = workspaceUnit.calculatePricing(
        headcount: 1,
        timePassType: 'day_pass',
      );
      expect(calcDayPass.totalPriceEgp, 90.0);
      expect(calcDayPass.totalDurationMins, 480); // 8 hours
    });

    test('5. service_menu: Barbershops & Additive Checklist', () {
      final barberChair = BookableUnit(
        id: 'chair_ahmed',
        venueId: 'venue_barber',
        category: 'barber',
        unitName: 'Master Barber Ahmed Chair',
        pricingMode: PricingMode.serviceMenu,
        basePriceEgp: 100.0,
        serviceMenu: const [
          ServiceMenuItem(id: 's_hair', name: 'Haircut & Styling', price: 100, durationMins: 30),
          ServiceMenuItem(id: 's_beard', name: 'Beard Contour & Hot Towel', price: 60, durationMins: 20),
          ServiceMenuItem(id: 's_facial', name: 'Charcoal Facial Mask', price: 50, durationMins: 15),
        ],
        minCapacity: 1,
        maxCapacity: 1,
      );

      // Select Haircut + Beard Grooming
      final calc = barberChair.calculatePricing(
        selectedServiceIds: ['s_hair', 's_beard'],
      );

      expect(calc.totalPriceEgp, 160.0); // 100 + 60
      expect(calc.totalDurationMins, 50); // 30 + 20 mins
    });
  });

  group('Phase 1: UserProfile & Reputation / Reliability Passport', () {
    test('Default profile has 100 score and good perks', () {
      final profile = UserProfile(
        id: 'usr_1',
        phoneNumber: '01012345678',
        displayName: 'Mohamed Hegazy',
        city: 'Kafr El Sheikh',
        createdAt: DateTime.now(),
      );

      expect(profile.reliabilityScore, 100.0);
      expect(profile.requiresFullDeposit, isFalse);
      expect(profile.hasZeroDepositPerks, isTrue);
      expect(profile.canJoinChallengerLobby, isTrue);
    });

    test('No-show drops score and drops below 80% enforces full deposit', () {
      var profile = UserProfile(
        id: 'usr_test',
        phoneNumber: '01000000000',
        createdAt: DateTime.now(),
      );

      // 1st no show: 100 - 15 = 85
      profile = profile.recordNoShow();
      expect(profile.reliabilityScore, 85.0);
      expect(profile.requiresFullDeposit, isFalse);

      // 2nd no show: 85 - 15 = 70 (<80% threshold!)
      profile = profile.recordNoShow();
      expect(profile.reliabilityScore, 70.0);
      expect(profile.requiresFullDeposit, isTrue); // Anti-fraud strike triggered
    });

    test('10-Minute Grace cancellation refunds 100% to wallet', () {
      var profile = UserProfile(
        id: 'usr_wallet_test',
        phoneNumber: '01000000000',
        hagzyWalletBalance: 50.0,
        createdAt: DateTime.now(),
      );

      // Instant refund of 60 EGP deposit
      profile = profile.creditWallet(60.0);
      expect(profile.hagzyWalletBalance, 110.0);

      // Use balance for next booking
      profile = profile.debitWallet(40.0);
      expect(profile.hagzyWalletBalance, 70.0);
    });
  });

  group('Phase 1: HagzyBooking & Social Lobby Mechanics', () {
    test('10-Minute Grace Period Countdown & Status Handling', () {
      final now = DateTime.now();
      final booking = HagzyBooking(
        id: 'bk_123',
        unitId: 'unit_ps5',
        venueId: 'v_1',
        hostUserId: 'u_1',
        startTime: now.add(const Duration(hours: 3)),
        endTime: now.add(const Duration(hours: 4)),
        totalPriceEgp: 100.0,
        depositRequiredEgp: 30.0,
        status: BookingStatus.confirmed,
        confirmedAt: now.subtract(const Duration(minutes: 2)), // 2 minutes ago
        createdAt: now.subtract(const Duration(minutes: 3)),
      );

      expect(booking.isGracePeriodActive(now), isTrue);
      expect(booking.graceSecondsRemaining(now), inInclusiveRange(470, 490));

      // After 10 mins: grace period expires
      final pastGrace = now.add(const Duration(minutes: 9));
      expect(booking.isGracePeriodActive(pastGrace), isFalse);
    });

    test('Open Lobby (Challenger Mode) and WhatsApp invite generation', () {
      final now = DateTime(2026, 10, 30, 21, 0);
      final booking = HagzyBooking(
        id: 'bk_challenger_99',
        unitId: 'billiard_1',
        venueId: 'v_stars',
        hostUserId: 'u_captain',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        isOpenLobby: true,
        totalSlots: 2,
        filledSlots: 1,
        neededRoles: ['1v1_challenger'],
        lobbyTitle: 'Billiards 1v1 Challenger Match',
        totalPriceEgp: 80.0,
        depositRequiredEgp: 30.0,
        createdAt: now,
        venueName: 'Stars Lounge Kafr El Sheikh',
        unitName: 'Billiard Table #1',
      );

      expect(booking.openSlotsRemaining, 1);
      expect(booking.isLobbyFull, isFalse);

      final shareText = booking.buildWhatsAppShareMessage();
      expect(shareText, contains('Billiards 1v1 Challenger Match'));
      expect(shareText, contains('Stars Lounge Kafr El Sheikh'));
      expect(shareText, contains('https://hagzy.app/join/bk_challenger_99'));

      // Claim spot
      final updated = booking.addParticipant('usr_challenger');
      expect(updated.filledSlots, 2);
      expect(updated.isLobbyFull, isTrue);
      expect(updated.openSlotsRemaining, 0);
    });
  });
}

