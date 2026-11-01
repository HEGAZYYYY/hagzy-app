import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/features/universal_booking/universal_booking_bottom_sheet.dart';

void main() {
  final sampleVenue = HagzyVenue(
    id: 'venue_1',
    ownerId: 'owner_1',
    name: 'Arena Gaming & Sports Lounge',
    city: 'Kafr El Sheikh',
    categories: ['playstation', 'billiards', 'court', 'escape_room', 'barber', 'workspace'],
    createdAt: DateTime.now(),
  );

  group('Phase 3: Universal Polymorphic Booking Bottom Sheet UI', () {
    testWidgets('1. Switches to Hourly & Tiered Capacity for PlayStation VIP Room',
        (tester) async {
      const ps5Unit = BookableUnit(
        id: 'ps5_vip_1',
        venueId: 'venue_1',
        category: 'playstation',
        unitName: 'VIP PS5 Room 1',
        pricingMode: PricingMode.hourlyTieredCapacity,
        basePriceEgp: 60.0,
        pricingTiers: {'2': 60, '4': 100},
        minCapacity: 1,
        maxCapacity: 4,
      );

      HagzyBooking? createdBooking;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalBookingBottomSheet(
              unit: ps5Unit,
              venue: sampleVenue,
              initialStartTime: DateTime(2026, 10, 30, 21, 0),
              onLockSlotAndProceed: (b) => createdBooking = b,
            ),
          ),
        ),
      );

      expect(find.text('VIP PS5 Room 1'), findsOneWidget);
      expect(find.text('Arena Gaming & Sports Lounge • Kafr El Sheikh'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('1 hr'), findsOneWidget);
      expect(find.text('2 hrs'), findsOneWidget);

      // Tap 2 hrs
      await tester.tap(find.text('2 hrs'));
      await tester.pump();

      // Tap "Lock My Slot & Generate Invite Link →"
      await tester.tap(find.text('Lock My Slot & Generate Invite Link →'));
      await tester.pump();

      expect(createdBooking, isNotNull);
      expect(createdBooking!.unitId, 'ps5_vip_1');
      expect(createdBooking!.durationMinutes, 120);
    });

    testWidgets('2. Switches to Escape Room Tiered Headcount with discount callout',
        (tester) async {
      const escapeUnit = BookableUnit(
        id: 'escape_tomb',
        venueId: 'venue_1',
        category: 'escape_room',
        unitName: 'Pharaoh\'s Secret Escape',
        pricingMode: PricingMode.perPersonTiered,
        basePriceEgp: 220.0,
        pricingTiers: {'3': 220, '4': 200, '6': 160},
        minCapacity: 3,
        maxCapacity: 8,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalBookingBottomSheet(
              unit: escapeUnit,
              venue: sampleVenue,
              initialStartTime: DateTime(2026, 10, 30, 19, 0),
              onLockSlotAndProceed: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Group Size (More Friends = Cheaper!)'), findsOneWidget);
      expect(find.textContaining('3 People'), findsOneWidget);
      expect(find.textContaining('220 EGP/ea'), findsWidgets);
    });

    testWidgets('3. Switches to Workspace Pass Mode (Hourly vs Day Pass)',
        (tester) async {
      const deskUnit = BookableUnit(
        id: 'desk_quiet_1',
        venueId: 'venue_1',
        category: 'workspace',
        unitName: 'Quiet Study Desk #4',
        pricingMode: PricingMode.timePass,
        basePriceEgp: 20.0,
        pricingTiers: {'hourly': 20, 'day_pass': 80, 'weekly': 350},
        minCapacity: 1,
        maxCapacity: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalBookingBottomSheet(
              unit: deskUnit,
              venue: sampleVenue,
              initialStartTime: DateTime(2026, 10, 30, 10, 0),
              onLockSlotAndProceed: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Pass Type'), findsOneWidget);
      expect(find.text('Hourly'), findsOneWidget);
      expect(find.text('Day Pass'), findsOneWidget);
      expect(find.text('Weekly'), findsOneWidget);

      await tester.tap(find.text('Day Pass'));
      await tester.pump();

      // Check contrast bottom bar reflects Day Pass price (80 EGP)
      expect(find.textContaining('80 EGP'), findsWidgets);
    });

    testWidgets('4. Switches to Barbershop Additive Checklist',
        (tester) async {
      const barberUnit = BookableUnit(
        id: 'chair_master',
        venueId: 'venue_1',
        category: 'barber',
        unitName: 'Barber Ahmed VIP Chair',
        pricingMode: PricingMode.serviceMenu,
        basePriceEgp: 100.0,
        serviceMenu: [
          ServiceMenuItem(id: 's_cut', name: 'Haircut', price: 100, durationMins: 30),
          ServiceMenuItem(id: 's_beard', name: 'Beard Grooming', price: 60, durationMins: 20),
        ],
        minCapacity: 1,
        maxCapacity: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UniversalBookingBottomSheet(
              unit: barberUnit,
              venue: sampleVenue,
              initialStartTime: DateTime(2026, 10, 30, 16, 0),
              onLockSlotAndProceed: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Select Services'), findsOneWidget);
      expect(find.text('Haircut'), findsOneWidget);
      expect(find.text('Beard Grooming'), findsOneWidget);

      // Check Beard Grooming as well
      await tester.tap(find.text('Beard Grooming'));
      await tester.pump();

      // 100 + 60 = 160 EGP total
      expect(find.textContaining('160 EGP'), findsWidgets);
    });
  });
}
