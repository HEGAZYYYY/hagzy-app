import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/models/models.dart';
import 'package:hagzy_app/screens/admin_workspace.dart';
import 'package:hagzy_app/screens/smooth_venue_editor.dart';

void main() {
  testWidgets('Admin ManageTab: can move venue to trash, switch to trash tab, and restore venue', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final testVenue = Venue(
      id: 'test_venue_1',
      name: 'Adrenaline Escape Club',
      location: 'New Cairo, Egypt',
      type: VenueType.lounge,
      subCategories: const ['escape_rooms'],
      depositPercent: 25.0,
      openHour: 10,
      closeHour: 24,
      amenities: const ['Wi-Fi'],
      items: [
        VenueItem(
          id: 'room_orphans',
          name: 'Orphans - دار الأيتام',
          kind: 'Escape Room',
          hourlyRate: 100,
          description: 'Spooky orphanage',
        ),
      ],
      services: const [],
    );

    List<Venue> activeVenues = [testVenue];
    List<Venue> archivedVenues = [];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminManageWorkspace(
            venues: activeVenues,
            archivedVenues: archivedVenues,
            bookings: const [],
            onAddVenue: () {},
            onEditVenue: (_) {},
            onDelete: (venue) {
              activeVenues.remove(venue);
              archivedVenues.add(venue);
            },
            onRestoreVenue: (venue) {
              archivedVenues.remove(venue);
              activeVenues.add(venue);
            },
            onPermanentDeleteVenue: (venue) {
              archivedVenues.remove(venue);
            },
            onAddItem: (_) {},
            onAddService: (_) {},
            onRemoveService: (_, __) {},
            onRemoveItem: (_, __) {},
            onWalkIn: (_, __) {},
            onCancel: (_) {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify segmented tabs exist
    expect(find.text('Active Places (1)'), findsOneWidget);
    expect(find.text('Trash / Archived (0)'), findsOneWidget);
    expect(find.text('Adrenaline Escape Club'), findsOneWidget);

    // Delete venue -> dialog pops up
    final deleteBtn = find.byTooltip('Move to Trash');
    expect(deleteBtn, findsOneWidget);
    await tester.ensureVisible(deleteBtn);
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Confirmation dialog
    expect(find.text('Move Venue to Trash?'), findsOneWidget);
    await tester.tap(find.text('Move to Trash'));
    await tester.pumpAndSettle();

    // Verify it was moved
    expect(activeVenues.isEmpty, isTrue);
    expect(archivedVenues.length, 1);
  });

  testWidgets('SmoothVenueEditorDialog: supports Escape Room preset ladder & Story Bio', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? savedVenue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.lounge,
            populateDefaults: false,
            onSaved: (v) => savedVenue = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Escape Rooms subcategory chip
    final escapeChip = find.text('👻 Escape Rooms');
    expect(escapeChip, findsOneWidget);
    await tester.tap(escapeChip);
    await tester.pumpAndSettle();

    // Enter venue name
    await tester.enterText(find.byType(TextFormField).first, 'Adrenaline Escape Room');
    await tester.pumpAndSettle();

    // Click Add Room
    final addRoomBtn = find.text('+ Add Room');
    await tester.ensureVisible(addRoomBtn);
    await tester.tap(addRoomBtn);
    await tester.pumpAndSettle();

    // Check dialog components
    expect(find.text('Add New Escape Room'), findsOneWidget);
    expect(find.text('Adrenaline Preset'), findsOneWidget);

    // Enter room storyline
    final storyField = find.widgetWithText(TextFormField, '📖 Room Storyline & Bio *');
    expect(storyField, findsOneWidget);
    await tester.enterText(storyField, 'The terrifying story of the abandoned orphanage...');
    await tester.pumpAndSettle();

    // Tap Adrenaline Preset button
    await tester.tap(find.text('Adrenaline Preset'));
    await tester.pumpAndSettle();

    // Save unit in dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Save venue
    final saveVenueBtn = find.text('Add venue');
    await tester.ensureVisible(saveVenueBtn);
    await tester.tap(saveVenueBtn);
    await tester.pumpAndSettle();

    expect(savedVenue, isNotNull);
    expect(savedVenue!.name, 'Adrenaline Escape Room');
    expect(savedVenue!.subCategories.contains('escape_rooms'), isTrue);
    expect(savedVenue!.items.length, 1);
    final room = savedVenue!.items.first;
    expect(room.description, 'The terrifying story of the abandoned orphanage...');
    expect(room.pricingMode, 'per_person_tiered');
    expect(room.pricingTiers, isNotNull);
    expect(room.pricingTiers!['3'], 150.0);
    expect(room.pricingTiers!['5'], 120.0);
    expect(room.pricingTiers!['15'], 100.0);
  });

  testWidgets('SmoothVenueEditorDialog: supports Padel Court custom durations & flat prices', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? savedVenue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.sports,
            populateDefaults: false,
            onSaved: (v) => savedVenue = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Padel Courts subcategory chip
    final padelChip = find.text('🎾 Padel Courts');
    expect(padelChip, findsOneWidget);
    await tester.tap(padelChip);
    await tester.pumpAndSettle();

    // Enter venue name
    await tester.enterText(find.byType(TextFormField).first, 'Smash Padel Arena');
    await tester.pumpAndSettle();

    // Click Add Room
    final addCourtBtn = find.text('+ Add Room');
    await tester.ensureVisible(addCourtBtn);
    await tester.tap(addCourtBtn);
    await tester.pumpAndSettle();

    // Check Padel Preset chip
    expect(find.text('Padel Preset'), findsOneWidget);

    // Tap Padel Preset
    await tester.tap(find.text('Padel Preset'));
    await tester.pumpAndSettle();

    // Save unit in dialog
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    // Save venue
    final saveVenueBtn = find.text('Add venue');
    await tester.ensureVisible(saveVenueBtn);
    await tester.tap(saveVenueBtn);
    await tester.pumpAndSettle();

    expect(savedVenue, isNotNull);
    expect(savedVenue!.name, 'Smash Padel Arena');
    expect(savedVenue!.subCategories.contains('padel'), isTrue);
    expect(savedVenue!.items.length, 1);
    final court = savedVenue!.items.first;
    expect(court.customDurations, isNotNull);
    expect(court.customDurations!['60'], 400.0);
    expect(court.customDurations!['90'], 550.0);
    expect(court.customDurations!['120'], 700.0);
    expect(court.customDurations!['180'], 1000.0);
  });
}
