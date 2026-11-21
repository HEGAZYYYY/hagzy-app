import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/models/models.dart';
import 'package:hagzy_app/screens/smooth_venue_editor.dart';

void main() {
  testWidgets('SmoothVenueEditorDialog renders fields, default units, and saves sports venue', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.sports,
            populateDefaults: true,
            onSaved: (v) => created = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify sections exist
    expect(find.text('Add a venue'), findsOneWidget);
    expect(find.text('Basic Info & Category'), findsOneWidget);
    expect(find.text('Rooms, Courts & Units'), findsOneWidget);

    // Enter name
    await tester.enterText(find.byType(TextFormField).first, 'Smash Padel Club');
    await tester.pumpAndSettle();

    // Check pre-populated court items
    expect(find.text('Court 1 (Panoramic Glass)'), findsOneWidget);
    expect(find.text('Court 2 (Standard)'), findsOneWidget);

    // Tap Add venue
    await tester.tap(find.text('Add venue'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.name, 'Smash Padel Club');
    expect(created!.type, VenueType.sports);
    expect(created!.items.length, 2);
    expect(created!.items.first.name, 'Court 1 (Panoramic Glass)');
  });

  testWidgets('SmoothVenueEditorDialog populates salon chairs and services for Salon type', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.salon,
            populateDefaults: true,
            onSaved: (v) => created = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Salon Chairs & Stations'), findsOneWidget);

    // Enter name
    await tester.enterText(find.byType(TextFormField).first, 'Master Barber Shop');
    await tester.pumpAndSettle();

    expect(find.text('Master Barber Chair 1'), findsOneWidget);
    expect(find.text('VIP Private Grooming Suite'), findsOneWidget);
    expect(find.text('Haircut & Styling (30 min)'), findsOneWidget);

    // Tap Add venue
    await tester.tap(find.text('Add venue'));
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.name, 'Master Barber Shop');
    expect(created!.type, VenueType.salon);
    expect(created!.items.length, 3);
    expect(created!.services.length, 3);
  });

  testWidgets('SmoothVenueEditorDialog displays Upload Picture File button and handles image url input', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.lounge,
            populateDefaults: false,
            onSaved: (v) => created = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final uploadBtn = find.text('Upload Picture File');
    expect(uploadBtn, findsOneWidget);

    await tester.ensureVisible(uploadBtn);
    await tester.pumpAndSettle();

    // Tap the upload button
    await tester.tap(uploadBtn);
    await tester.pumpAndSettle();

    // Verify presets exist
    final presetChip = find.textContaining('Football Pitch');
    expect(presetChip, findsOneWidget);

    // Tap a preset chip
    await tester.tap(presetChip);
    await tester.pumpAndSettle();

    // The clear image button should now be visible
    expect(find.byTooltip('Clear Image'), findsOneWidget);

    // Enter venue name
    await tester.enterText(find.byType(TextFormField).first, 'Cairo Gaming Hub');
    await tester.pumpAndSettle();

    // Save
    final saveBtn = find.text('Add venue');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.name, 'Cairo Gaming Hub');
    expect(created!.imageUrl, isNotNull);
    expect(created!.imageUrl, contains('unsplash.com'));
  });

  testWidgets('SmoothVenueEditorDialog allows adding room with image and description', (tester) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Venue? created;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothVenueEditorDialog(
            initialType: VenueType.sports,
            populateDefaults: false,
            onSaved: (v) => created = v,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Enter venue name
    await tester.enterText(find.byType(TextFormField).first, 'Modern Padel Academy');
    await tester.pumpAndSettle();

    // Tap Add Room button
    final addRoomBtn = find.text('+ Add Room');
    expect(addRoomBtn, findsOneWidget);
    await tester.ensureVisible(addRoomBtn);
    await tester.pumpAndSettle();
    await tester.tap(addRoomBtn);
    await tester.pumpAndSettle();

    // Dialog should show room inputs including description and unit picture
    expect(find.text('Add New Room or Court'), findsOneWidget);
    expect(find.text('Upload Room Picture'), findsOneWidget);

    // Enter room description
    final descField = find.widgetWithText(TextFormField, 'Description & Features (Optional)');
    expect(descField, findsOneWidget);
    await tester.enterText(descField, 'Panoramic glass court with LED floodlights');
    await tester.pumpAndSettle();

    // Enter room image URL
    final imgField = find.widgetWithText(TextFormField, 'Or Unit Picture URL');
    expect(imgField, findsOneWidget);
    await tester.enterText(imgField, 'https://example.com/padel_room1.jpg');
    await tester.pumpAndSettle();

    // Tap Add in dialog
    final confirmAddBtn = find.widgetWithText(FilledButton, 'Add');
    await tester.tap(confirmAddBtn);
    await tester.pumpAndSettle();

    // Room item should be displayed in list
    expect(find.text('Panoramic glass court with LED floodlights'), findsOneWidget);

    // Save venue
    final saveBtn = find.text('Add venue');
    await tester.ensureVisible(saveBtn);
    await tester.pumpAndSettle();
    await tester.tap(saveBtn);
    await tester.pumpAndSettle();

    expect(created, isNotNull);
    expect(created!.items.length, 1);
    expect(created!.items.first.description, 'Panoramic glass court with LED floodlights');
    expect(created!.items.first.imageUrl, 'https://example.com/padel_room1.jpg');
  });
}
