import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/main.dart';
import 'package:hagzy_app/screens/book_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('Escape room does not auto-assign room and Back to Rooms works properly', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
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
      items: [
        VenueItem(
          id: 'adrenaline-orphans',
          name: '👻 Orphans – دار الأيتام ♣️🧸',
          kind: 'Escape Room',
          hourlyRate: 150,
          description: 'Orphans story bio',
        ),
        VenueItem(
          id: 'adrenaline-cannibal',
          name: '🥩 Cannibal – آكل لحوم البشر 🩸☠️',
          kind: 'Escape Room',
          hourlyRate: 120,
          description: 'Cannibal story bio',
        ),
        VenueItem(
          id: 'adrenaline-the-curse',
          name: '🔮 The Curse – اللعنة 👁️📜',
          kind: 'Escape Room',
          hourlyRate: 200,
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

    // TAP ON CANNIBAL ROOM
    final cannibalCard = find.text('🥩 Cannibal – آكل لحوم البشر 🩸☠️');
    await tester.ensureVisible(cannibalCard);
    await tester.tap(cannibalCard);
    await tester.pumpAndSettle();

    // VERIFY PHASE 2: Cannibal room is now active!
    expect(find.text('Back to Rooms'), findsOneWidget);
    expect(find.text('Select Number of People'), findsOneWidget);
    expect(find.text('4 or 5 players'), findsOneWidget);
    expect(find.text('More than 5 players'), findsOneWidget);

    // TAP "< Back to Rooms"
    final backBtn = find.text('Back to Rooms');
    await tester.ensureVisible(backBtn);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // VERIFY RETURN TO PHASE 1: Back to room selection cards!
    expect(find.text('Choose Your Escape Room'), findsOneWidget);
    expect(find.text('Back to Rooms'), findsNothing);
    expect(find.text('🔮 The Curse – اللعنة 👁️📜'), findsOneWidget);

    // TAP ON THE CURSE ROOM
    final curseCard = find.text('🔮 The Curse – اللعنة 👁️📜');
    await tester.ensureVisible(curseCard);
    await tester.tap(curseCard);
    await tester.pumpAndSettle();

    // VERIFY PHASE 2: The Curse is now active with its specific options!
    expect(find.text('Back to Rooms'), findsOneWidget);
    expect(find.text('3 or 4 players'), findsOneWidget);
    expect(find.text('5 or more players'), findsOneWidget);
  });
}
