import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/main.dart';
import 'package:hagzy_app/screens/book_tab.dart';
import 'package:hagzy_app/screens/unified_payment_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('BookTab hides test venues, filters governorates strictly, and quotes salon chair rates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final testVenue = Venue(
      id: 'test-venue',
      name: 'Test Venue',
      location: '',
      type: VenueType.sports,
      depositPercent: 30,
      items: [VenueItem(id: 'tv-1', name: 'ewrethg', kind: 'Padel', hourlyRate: 3434)],
    );
    final demoLab = demo5EgpVenueSample();
    final salon = Venue(
      id: 'salon-kfs',
      name: 'Nader Barber',
      location: 'Kafr El Sheikh',
      type: VenueType.salon,
      depositPercent: 30,
      items: [
        VenueItem(id: 'chair-1', name: 'Barber Chair 1', kind: 'Barber / chair', hourlyRate: 150),
        VenueItem(id: 'chair-vip', name: 'Barber Chair 2 (VIP)', kind: 'Barber / chair', hourlyRate: 200),
      ],
      services: [
        SalonService(id: 'svc-cut', name: 'Haircut', minutes: 30, price: 150),
      ],
    );
    final cairoClub = Venue(
      id: 'cairo-club',
      name: 'Cairo Padel',
      location: 'Cairo',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(id: 'court-1', name: 'Court 1', kind: 'Padel court', hourlyRate: 400),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookTab(
            venues: [testVenue, demoLab, salon, cairoClub],
            bookings: const [],
            arabic: false,
            onBook: (_, __, ___) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Test venues are hidden from public catalog
    expect(find.text('Test Venue'), findsNothing);
    expect(find.textContaining('5 EGP Test Lab'), findsNothing);
    expect(find.text('Nader Barber'), findsOneWidget);
    expect(find.textContaining('2 Chairs'), findsOneWidget);

    // Scroll down to Cairo Padel card (Sports & Courts section)
    final mainScrollable = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Cairo Padel'),
      250,
      scrollable: mainScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cairo Padel'), findsOneWidget);
    expect(find.textContaining('1 Court'), findsOneWidget);

    // Scroll back up to Nader Barber and verify chair pricing updates live
    await tester.scrollUntilVisible(
      find.text('Nader Barber'),
      -250,
      scrollable: mainScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nader Barber'));
    await tester.pumpAndSettle();
    expect(find.text('150 EGP'), findsWidgets);

    await tester.scrollUntilVisible(
      find.textContaining('Barber Chair 2 (VIP)'),
      120,
      scrollable: mainScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Barber Chair 2 (VIP)'));
    await tester.pumpAndSettle();
    expect(find.text('200 EGP'), findsWidgets);

    // Scroll back to top bar and select Cairo governorate
    await tester.scrollUntilVisible(
      find.text('Change'),
      -300,
      scrollable: mainScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cairo').last);
    await tester.pumpAndSettle();

    expect(find.text('Nader Barber'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Cairo Padel'),
      250,
      scrollable: mainScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Cairo Padel'), findsOneWidget);
  });

  testWidgets('Guest can explore venues from CustomerLoginScreen without losing login gate',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Explore Venues as Guest'), findsOneWidget);
    await tester.tap(find.text('Explore Venues as Guest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(BookTab), findsOneWidget);
  });

  testWidgets('UnifiedPaymentScreen uses 15-min hold banner on Mobile Wallet and clean EN copy',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UnifiedPaymentScreen(
          bookingId: 'bk_test_1',
          amount: 120,
          arabic: false,
          venueName: 'Smash Padel',
          slotTimeFormatted: '8:00 PM',
          receiverIpa: 'hagzy@instapay',
          receiverWallet: '01041570557',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // InstaPay tab shows 15-min hold and proper EGP suffix (no swapped Arabic 'ج.م' or 'payment oracle')
    expect(find.text('15-min slot hold active'), findsOneWidget);
    expect(find.textContaining('120 EGP'), findsWidgets);
    expect(find.textContaining('ج.م'), findsNothing);
    expect(find.textContaining('payment oracle'), findsNothing);

    // Switch to Mobile Wallet tab
    await tester.tap(find.textContaining('Mobile Wallet').first);
    await tester.pumpAndSettle();

    expect(find.text('15-min slot hold active'), findsOneWidget);
    expect(find.textContaining('120 EGP'), findsWidgets);
    expect(find.text('🇪🇬 EG'), findsOneWidget);
  });
}
