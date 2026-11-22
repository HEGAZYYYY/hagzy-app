import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/models/models.dart';
import 'package:hagzy_app/screens/book_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Escape room headcount selector, tier pricing, confirmation and Back to Rooms works properly', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});

    final escapeVenue = Venue(
      id: 'adrenaline-kfs',
      name: 'Adrenaline Escape Room',
      location: 'Kafr El Sheikh',
      type: VenueType.lounge,
      subCategories: ['escape_rooms'],
      depositPercent: 25,
      items: [
        VenueItem(
          id: 'adrenaline-orphans',
          name: '👻 Orphans – دار الأيتام ♣️🧸',
          kind: 'Escape Room',
          hourlyRate: 150,
          minCapacity: 2,
          maxCapacity: 15,
          pricingTiers: const {'3': 150, '5': 120, '15': 100},
          description: 'Orphans story bio',
        ),
        VenueItem(
          id: 'adrenaline-cannibal',
          name: '🥩 Cannibal – آكل لحوم البشر 🩸☠️',
          kind: 'Escape Room',
          hourlyRate: 120,
          minCapacity: 4,
          maxCapacity: 15,
          pricingTiers: const {'5': 120, '15': 100},
          description: 'Cannibal story bio',
        ),
        VenueItem(
          id: 'adrenaline-the-curse',
          name: '🔮 The Curse – اللعنة 👁️📜',
          kind: 'Escape Room',
          hourlyRate: 200,
          minCapacity: 3,
          maxCapacity: 20,
          pricingTiers: const {'4': 200, '20': 150},
          description: 'Curse story bio',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookTab(
            venues: [escapeVenue],
            bookings: const [],
            arabic: false,
            onBook: (_, __, ___, [____]) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap on the venue card to expand it
    final venueCard = find.text('Adrenaline Escape Room');
    expect(venueCard, findsWidgets);
    await tester.ensureVisible(venueCard.first);
    await tester.tap(venueCard.first);
    await tester.pumpAndSettle();

    // VERIFY PHASE 1: Room Selection is visible!
    // It should NOT auto-assign Orphans or show "Back to Rooms" yet.
    expect(find.text('Choose Your Escape Room'), findsOneWidget);
    expect(find.text('👻 Orphans – دار الأيتام ♣️🧸'), findsOneWidget);
    expect(find.text('🥩 Cannibal – آكل لحوم البشر 🩸☠️'), findsOneWidget);
    expect(find.text('🔮 The Curse – اللعنة 👁️📜'), findsOneWidget);
    expect(find.text('Back to Rooms'), findsNothing);

    // TAP ON ORPHANS ROOM
    final orphansCard = find.text('👻 Orphans – دار الأيتام ♣️🧸');
    await tester.ensureVisible(orphansCard);
    await tester.tap(orphansCard);
    await tester.pumpAndSettle();

    // VERIFY PHASE 2: Orphans room is now active!
    expect(find.text('Back to Rooms'), findsOneWidget);
    expect(find.text('Number of Players (Shilla)'), findsOneWidget);
    expect(find.text('Room capacity: 2 to 15 players'), findsOneWidget);

    // Default headcount is minCapacity = 2.
    // Orphans pricing: 2 or 3 players -> 150 EGP/person. Total = 2 * 150 = 300 EGP.
    expect(find.text('2 Players'), findsOneWidget);
    expect(find.text('150 EGP/person'), findsOneWidget);
    expect(find.text('300 EGP total'), findsOneWidget);

    // Step 2 should NOT be unlocked yet
    expect(find.text('Confirm Group Size (2 Players) · Total: 300 EGP'), findsOneWidget);

    // TAP QUICK CHIP "5"
    final chip5 = find.widgetWithText(ChoiceChip, '5');
    await tester.ensureVisible(chip5);
    await tester.tap(chip5);
    await tester.pumpAndSettle();

    // For 5 players: tier is 4-5 players -> 120 EGP/person. Total = 5 * 120 = 600 EGP.
    expect(find.text('5 Players'), findsOneWidget);
    expect(find.text('120 EGP/person'), findsOneWidget);
    expect(find.text('600 EGP total'), findsOneWidget);
    expect(find.text('Confirm Group Size (5 Players) · Total: 600 EGP'), findsOneWidget);

    // TAP "+" to 6 Players
    final plusBtn = find.byTooltip('Increase');
    await tester.ensureVisible(plusBtn);
    await tester.tap(plusBtn);
    await tester.pumpAndSettle();

    // For 6 players: tier is 6+ players -> 100 EGP/person. Total = 6 * 100 = 600 EGP.
    expect(find.text('6 Players'), findsOneWidget);
    expect(find.text('100 EGP/person'), findsOneWidget);
    expect(find.text('600 EGP total'), findsOneWidget);
    expect(find.text('Confirm Group Size (6 Players) · Total: 600 EGP'), findsOneWidget);

    // TAP "Confirm Group Size"
    final confirmBtn = find.text('Confirm Group Size (6 Players) · Total: 600 EGP');
    await tester.ensureVisible(confirmBtn);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // Group size is confirmed! Summary card shows:
    expect(find.text('Group Size Confirmed'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    // Step 2 slot picker is now unlocked!
    expect(find.text('Pick an Available Time'), findsOneWidget);

    // TAP "Back to Rooms"
    final backBtn = find.text('Back to Rooms');
    await tester.ensureVisible(backBtn);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // VERIFY RETURN TO PHASE 1: Back to room selection cards!
    expect(find.text('Choose Your Escape Room'), findsOneWidget);
    expect(find.text('Back to Rooms'), findsNothing);
    expect(find.text('🥩 Cannibal – آكل لحوم البشر 🩸☠️'), findsOneWidget);
  });
}
