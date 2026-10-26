import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/main.dart';
import 'package:hagzy_app/screens/profile_tab.dart';
import 'package:hagzy_app/widgets/map_explorer.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> enterAdminPreview(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Open local preview'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open local preview'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unpaid reservations are temporary holds, never confirmed bookings', () {
    final startsAt = DateTime.now().add(const Duration(days: 1));
    final hold = Booking(
      id: 'hold-1',
      venueId: 'venue-1',
      itemId: 'court-1',
      customer: 'Test Customer',
      startsAt: startsAt,
      durationMinutes: 60,
      price: 200,
      dueNow: 50,
      status: 'pending_payment',
      paymentStatus: 'unpaid',
      holdExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    expect(hold.isPendingPayment, isTrue);
    expect(hold.isConfirmed, isFalse);
    expect(hold.blocksAvailability, isTrue);

    final expiredHold = Booking(
      id: 'hold-2',
      venueId: 'venue-1',
      itemId: 'court-1',
      customer: 'Test Customer',
      startsAt: startsAt,
      durationMinutes: 60,
      price: 200,
      dueNow: 50,
      status: 'pending_payment',
      paymentStatus: 'unpaid',
      holdExpiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );
    expect(expiredHold.isPendingPayment, isFalse);
    expect(expiredHold.isConfirmed, isFalse);
    expect(expiredHold.blocksAvailability, isFalse);
  });

  testWidgets('local admin preview adds venues and customer can reserve them',
      (tester) async {
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    await enterAdminPreview(tester);

    await tester.tap(find.text('Manage Venues'));
    await tester.pumpAndSettle();
    expect(find.text('Manage Venues'), findsNWidgets(2));
    expect(find.text('Your self-service builder'), findsOneWidget);
    await tester.tap(find.text('Add venue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Nile Padel');
    await tester.enterText(find.byType(TextFormField).at(1), 'New Cairo');
    await tester.enterText(find.byType(TextFormField).at(2), '01012345678');
    await tester.enterText(find.byType(TextFormField).last, '40');
    await tester.tap(find.text('Add venue').last);
    await tester.pumpAndSettle();

    expect(find.text('Nile Padel'), findsOneWidget);
    await tester.tap(find.text('Add court / table'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Court 1');
    await tester.enterText(find.byType(TextFormField).last, '500');
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    expect(find.text('Court 1 · Padel court'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nile Padel'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nile Padel'), findsOneWidget);
    await tester.ensureVisible(find.text('Nile Padel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nile Padel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save Venue'));
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Saved'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Nile Padel'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Nile Padel'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('All Places'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.tap(find.text('All Places'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Court 1 · 500.00 EGP/h'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.scrollUntilVisible(
      find.text('10:00 PM'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('10:00 PM'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10:00 PM'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reserve & pay deposit'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Reserve & pay deposit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reserve & pay deposit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Test Customer');
    await tester.enterText(find.byType(TextFormField).at(1), '01012345678');
    expect(find.text('Email (for online checkout)'), findsNothing);
    await tester.tap(find.text('Continue to deposit'));
    await tester.pumpAndSettle();
    expect(find.text('Secure Your Time'), findsOneWidget);
    expect(find.text('15-minute reservation hold'), findsOneWidget);
    expect(
        find.text('Not confirmed until payment is verified'), findsOneWidget);
    expect(find.text('Paymob'), findsOneWidget);
    expect(find.text('Fawry'), findsOneWidget);
    expect(find.text('InstaPay'), findsOneWidget);
    expect(find.text('Continue in WhatsApp'), findsOneWidget);
    expect(
      find.textContaining(
          'A chat does not confirm your booking or verify payment.'),
      findsOneWidget,
    );
    expect(find.textContaining('Saved on this device only'), findsOneWidget);
    await tester.ensureVisible(find.text('Pay later'));
    await tester.tap(find.text('Pay later'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('My Bookings').last);
    await tester.pumpAndSettle();
    expect(find.text('Nile Padel'), findsOneWidget);
    expect(find.textContaining('not confirmed'), findsOneWidget);
    expect(find.text('AWAITING DEPOSIT'), findsOneWidget);
    expect(find.text('Confirmed'), findsNothing);
    await tester.ensureVisible(find.textContaining('Pay Deposit'));
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Pay Deposit'));
    await tester.pumpAndSettle();
    expect(find.text('Secure Your Time'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    await enterAdminPreview(tester);
    await tester.tap(find.text('Manage Venues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POS timeline').first);
    await tester.pumpAndSettle();
    expect(find.text('Test Customer'), findsOneWidget);
    expect(find.textContaining('Awaiting deposit · not confirmed'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gaming & Tables'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    await tester.scrollUntilVisible(
      find.text('Gaming & Tables'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gaming & Tables'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('No Places Found Here'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('No Places Found Here'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    await enterAdminPreview(tester);
    await tester.tap(find.text('Manage Venues'));
    await tester.pumpAndSettle();
    expect(find.text('Nile Padel'), findsOneWidget);
    expect(find.text('Court 1 · Padel court'), findsOneWidget);
  });

  testWidgets('customer build does not show venue-owner access',
      (tester) async {
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    expect(find.text('Find your next favorite'), findsOneWidget);
    expect(find.text('Venue owner'), findsNothing);
    expect(find.text('Continue as admin'), findsNothing);
    expect(find.text('Manage'), findsNothing);
    expect(find.text('POS'), findsNothing);
    expect(find.text('Payments'), findsNothing);

    await tester.tap(find.text('My Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Your Bookings'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    expect(find.text('Venue owner sign in'), findsOneWidget);
    await enterAdminPreview(tester);
    await tester.tap(find.text('Manage Venues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POS timeline').first);
    await tester.pumpAndSettle();
    expect(find.text('POS timeline'), findsNWidgets(2));
    await tester.tap(find.text('Payment Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Payments & deposits'), findsOneWidget);
    expect(find.textContaining('never in this app'), findsOneWidget);
  });

  testWidgets(
      'empty category hides booking steps and limits builder CTA to owner',
      (tester) async {
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Gaming & Tables'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gaming & Tables'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, 1600),
    );
    await tester.pumpAndSettle();
    expect(find.text('PS5 VIP Rooms, Billiards & Ping Pong'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('No Places Found Here'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No Places Found Here'), findsOneWidget);
    expect(find.text('Your Booking'), findsNothing);
    expect(find.textContaining('Add New Venue'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    await enterAdminPreview(tester);
    await tester.scrollUntilVisible(
      find.text('Gaming & Tables'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Gaming & Tables'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Add New Venue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Add New Venue'));
    await tester.pumpAndSettle();
    expect(find.text('Add a venue'), findsOneWidget);
  });

  testWidgets('Arabic switches branding, layout, and governorate selection',
      (tester) async {
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('AR'));
    await tester.pumpAndSettle();

    expect(find.text('حجزي'), findsOneWidget);
    expect(find.text('Hagzy · حجزي'), findsNothing);
    expect(find.text('استكشف التصنيفات'), findsOneWidget);
    expect(find.text('Explore Categories'), findsNothing);
    expect(
      Directionality.of(tester.element(find.text('استكشف التصنيفات'))),
      TextDirection.rtl,
    );

    await tester.tap(find.text('تغيير'));
    await tester.pumpAndSettle();
    expect(find.text('اختر المحافظة'), findsOneWidget);
    expect(find.text('القاهرة'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('كفر الشيخ'),
      160,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('كفر الشيخ'));
    await tester.pumpAndSettle();
    expect(find.text('كفر الشيخ'), findsOneWidget);
  });

  testWidgets('expired booking holds are removed from customer history',
      (tester) async {
    final expiredBooking = {
      'id': 'expired-hold',
      'venueId': 'venue-1',
      'itemId': 'chair-1',
      'customer': 'Expired Customer',
      'startsAt': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
      'durationMinutes': 30,
      'price': 100,
      'dueNow': 30,
      'status': 'pending_payment',
      'paymentStatus': 'unpaid',
      'holdExpiresAt':
          DateTime.now().subtract(const Duration(minutes: 1)).toIso8601String(),
    };
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': <dynamic>[],
        'bookings': [expiredBooking],
      }),
    });
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('My Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Expired Customer'), findsNothing);
    expect(find.text('Nothing Booked Yet'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('hagzy_app_data_v1'),
        isNot(contains('Expired Customer')));
  });

  testWidgets('tapping selected venue or close button toggles and deselects it',
      (tester) async {
    final venue = Venue(
      id: 'venue-toggle-test',
      name: 'Smash Club',
      location: 'Cairo',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(
          id: 'smash-court-1',
          name: 'Padel Court A',
          kind: 'Padel court',
          hourlyRate: 400,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': [venue.toJson()],
        'bookings': <dynamic>[],
      }),
    });

    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Smash Club'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Smash Club'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Your Booking'), findsNothing);

    // Tap venue card to open
    await tester.ensureVisible(find.text('Smash Club'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Smash Club'));
    await tester.pumpAndSettle();

    // Booking steps expand directly and button becomes Close
    expect(find.text('Your Booking'), findsOneWidget);
    expect(find.text('Close'), findsWidgets);

    // Tap venue card again -> deselects and closes menu
    await tester.ensureVisible(find.text('Smash Club'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Smash Club'));
    await tester.pumpAndSettle();

    expect(find.text('Your Booking'), findsNothing);
    expect(find.text('Book'), findsOneWidget);

    // Tap View Times button directly -> opens
    await tester.ensureVisible(find.text('Book'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book'));
    await tester.pumpAndSettle();

    expect(find.text('Your Booking'), findsOneWidget);

    // Tap Close button on the card -> deselects and closes menu
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Your Booking'), findsNothing);
    expect(find.text('Book'), findsOneWidget);
  });

  testWidgets(
      'customer can submit InstaPay proof and owner can confirm deposit and view analytics',
      (tester) async {
    final venue = Venue(
      id: 'venue-instapay-test',
      name: 'Cairo Padel Arena',
      location: 'Cairo',
      type: VenueType.sports,
      depositPercent: 25,
      instaPayAddress: 'arena@instapay',
      amenities: const ['Parking', 'Café'],
      items: [
        VenueItem(
          id: 'arena-court-1',
          name: 'Center Court',
          kind: 'Padel court',
          hourlyRate: 400,
        ),
      ],
    );
    final hold = Booking(
      id: 'hold-instapay-1',
      venueId: venue.id,
      itemId: 'arena-court-1',
      customer: 'Omar Hassan',
      phone: '01099887766',
      startsAt: DateTime.now().add(const Duration(hours: 3)),
      durationMinutes: 60,
      price: 400,
      dueNow: 100,
      status: 'pending_payment',
      paymentStatus: 'unpaid',
      holdExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': [venue.toJson()],
        'bookings': [hold.toJson()],
      }),
    });

    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Open My Bookings and submit InstaPay transfer reference
    await tester.tap(find.text('My Bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Cairo Padel Arena'), findsOneWidget);
    await tester.tap(find.textContaining('Pay Deposit'));
    await tester.pumpAndSettle();
    expect(find.text('InstaPay'), findsOneWidget);
    expect(find.text('Vodafone Cash'), findsOneWidget);

    await tester.tap(find.text('InstaPay'));
    await tester.pumpAndSettle();
    expect(find.text('arena@instapay'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'IPN-776655');
    await tester.tap(find.text('Submit Reference'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Payment proof submitted (INSTAPAY: IPN-776655)'),
      findsOneWidget,
    );

    // Switch to Owner Preview to verify & confirm deposit and inspect Analytics
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    await enterAdminPreview(tester);
    await tester.tap(find.text('Manage Venues'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POS timeline').first);
    await tester.pumpAndSettle();

    expect(find.text('Omar Hassan'), findsOneWidget);
    expect(find.text('Verify & Confirm Deposit'), findsOneWidget);
    await tester.ensureVisible(find.text('Verify & Confirm Deposit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify & Confirm Deposit'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Confirmed by venue'), findsOneWidget);

    // Open Analytics section
    await tester.tap(find.textContaining('Analytics'));
    await tester.pumpAndSettle();
    expect(find.text('Revenue & Analytics'), findsOneWidget);
    expect(find.text('400.00 EGP'), findsWidgets);
  });

  testWidgets('Customer can view Directions and Book Again (calendar removed)',
      (tester) async {
    final venue = Venue(
      id: 'venue-convenience-test',
      name: 'Giza Sports Hub',
      location: 'Sheikh Zayed',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(
          id: 'court-gh-1',
          name: 'Court Alpha',
          kind: 'Padel court',
          hourlyRate: 350,
        ),
      ],
    );
    final booking = Booking(
      id: 'book-conv-1',
      venueId: venue.id,
      itemId: 'court-gh-1',
      customer: 'Kareem Tarek',
      startsAt: DateTime.now().add(const Duration(hours: 3)),
      durationMinutes: 60,
      price: 350,
      dueNow: 87.5,
      status: 'pending_payment',
      paymentStatus: 'unpaid',
      holdExpiresAt: DateTime.now().add(const Duration(minutes: 15)),
    );

    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': [venue.toJson()],
        'bookings': [booking.toJson()],
      }),
    });

    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // 1. "Book Again" carousel is visible on Explore because there is an active booking
    expect(find.text('Book Again'), findsOneWidget);
    expect(find.text('Your favorite regular spots'), findsOneWidget);

    // Tap the carousel card to open the booking drawer directly
    await tester.tap(find.text('Book Now').first);
    await tester.pumpAndSettle();

    expect(find.text('Your Booking'), findsOneWidget);
    expect(find.text('Choose Your Space'), findsOneWidget);

    // 2. Switch to My Bookings
    await tester.tap(find.text('My Bookings'));
    await tester.pumpAndSettle();

    expect(find.text('Giza Sports Hub'), findsOneWidget);
    expect(find.text('QR Check-In Pass'), findsOneWidget);
    expect(find.text('Directions'), findsWidgets);
    // Calendar is completely removed as requested
    expect(find.text('Add to Calendar'), findsNothing);
    expect(find.text('Calendar'), findsNothing);
    expect(find.text('Google Calendar'), findsNothing);
    expect(find.text('Book Again'), findsOneWidget);

    // 3. Tap Book Again from My Bookings to return to Explore with venue pre-selected
    await tester.ensureVisible(find.text('Book Again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Book Again'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Your Booking'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Your Booking'), findsOneWidget);
    expect(find.text('Choose Your Space'), findsOneWidget);
  });

  test('distance calculation computes correct haversine distance for Egypt coordinates', () {
    final cairo = kEgyptGovernorateCoordinates['Cairo']!;
    final alex = kEgyptGovernorateCoordinates['Alexandria']!;
    final dist = calculateDistanceKm(cairo.$1, cairo.$2, alex.$1, alex.$2);
    expect(dist, greaterThan(170));
    expect(dist, lessThan(240));

    final distSame = calculateDistanceKm(cairo.$1, cairo.$2, cairo.$1, cairo.$2);
    expect(distSame, closeTo(0.0, 0.001));
  });

  test('findNearestGovernorate correctly identifies nearest Egyptian city from GPS coords', () {
    expect(findNearestGovernorate(30.05, 31.24), 'Cairo');
    expect(findNearestGovernorate(31.21, 29.92), 'Alexandria');
    expect(findNearestGovernorate(31.11, 30.94), 'Kafr El Sheikh');
  });

  test('promo engine correctly computes fixed, percentage, and category discounts', () {
    final promo50 = kAvailablePromos.firstWhere((p) => p.code == 'HAGZY50');
    expect(promo50.calculateDiscount(100, VenueType.sports), 0);
    expect(promo50.calculateDiscount(300, VenueType.sports), 50);

    final promoPadel = kAvailablePromos.firstWhere((p) => p.code == 'PADEL100');
    expect(promoPadel.calculateDiscount(500, VenueType.sports), 100);
    expect(promoPadel.calculateDiscount(500, VenueType.salon), 0);

    final promo20 = kAvailablePromos.firstWhere((p) => p.code == 'HAGZY20');
    expect(promo20.calculateDiscount(400, VenueType.sports), 80);
    expect(promo20.calculateDiscount(1000, VenueType.sports), 100);
  });

  test('slot blocker booking correctly flags blocked status and hides from regular booking', () {
    final slot = Booking(
      id: 'blocked-slot-1',
      venueId: 'v1',
      itemId: 'space-1',
      customer: 'VENUE BLOCKED',
      phone: '01000000000',
      startsAt: DateTime.now().add(const Duration(hours: 3)),
      durationMinutes: 60,
      price: 0,
      status: 'confirmed',
      paymentMethod: 'blocked',
      blockReason: 'Court Maintenance & Cleaning',
    );
    expect(slot.isBlocked, isTrue);
    expect(slot.blockReason, 'Court Maintenance & Cleaning');
    expect(slot.blocksAvailability, isTrue);
  });

  testWidgets('customer can toggle Interactive Map View in BookTab', (tester) async {
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': defaultPrototypeVenues().map((v) => v.toJson()).toList(),
        'bookings': [],
      }),
    });
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    final pill = find.text('Map & Near Me');
    await tester.scrollUntilVisible(
      pill,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pumpAndSettle();

    expect(find.byType(HagzyMapExplorer), findsOneWidget);

    // Tap again to toggle back to list view
    await tester.ensureVisible(find.text('Map & Near Me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Map & Near Me'));
    await tester.pumpAndSettle();

    expect(find.byType(HagzyMapExplorer), findsNothing);
  });

  testWidgets(
      'customer can auto-assign area via GPS in modal and from area bar',
      (tester) async {
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // 1. Open area selection modal by tapping Change
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    // Verify modal elements
    expect(find.text('Choose a governorate'), findsOneWidget);
    expect(find.text('Auto-Assign Area via GPS'), findsOneWidget);

    // Tap Auto-Assign Area via GPS inside the dialog
    await tester.tap(find.text('Auto-Assign Area via GPS'));
    await tester.pumpAndSettle();

    // Verify feedback and updated area
    expect(find.textContaining('Auto-assigned area via GPS'), findsOneWidget);

    // 2. Also test tapping the GPS badge on the CustomerAreaBar directly
    final gpsBadge = find.text('GPS');
    expect(gpsBadge, findsOneWidget);
    await tester.tap(gpsBadge);
    await tester.pumpAndSettle();

    expect(find.textContaining('Auto-assigned area via GPS'), findsOneWidget);
  });

  testWidgets(
      'customer can navigate to profile section and sign in with email or phone',
      (tester) async {
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // 1. Navigate to Profile tab via FloatingDock
    final profileTab = find.text('Profile');
    expect(profileTab, findsOneWidget);
    await tester.tap(profileTab);
    await tester.pumpAndSettle();

    // Verify Profile section welcome & form
    expect(find.text('Welcome to Hagzy'), findsOneWidget);
    expect(find.text('Sign in with Email or Phone'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);

    // 2. Sign in with Email via verification code
    await tester.enterText(
        find.widgetWithText(TextField, 'Full Name (optional)'),
        'Mohamed Hegazy');
    await tester.enterText(
        find.widgetWithText(TextField, 'Email Address'),
        'hegazy@example.com');
    final sendCodeBtn = find.text('Send Verification Code');
    await tester.ensureVisible(sendCodeBtn);
    await tester.pumpAndSettle();
    await tester.tap(sendCodeBtn);
    await tester.pumpAndSettle();

    // Verify OTP verification view is shown
    expect(find.text('Enter Verification Code'), findsOneWidget);
    expect(find.textContaining('hegazy@example.com'), findsWidgets);

    // Enter 6-digit OTP and complete verification
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    final verifyBtn = find.text('Verify & Sign In');
    await tester.ensureVisible(verifyBtn);
    await tester.pumpAndSettle();
    await tester.tap(verifyBtn);
    await tester.pumpAndSettle();

    // Verify user is now signed in with profile card
    final profileName = find.text('Mohamed Hegazy');
    await tester.scrollUntilVisible(
      profileName,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(profileName, findsOneWidget);
    expect(find.text('hegazy@example.com'), findsWidgets);

    // 3. Sign out
    await tester.scrollUntilVisible(
      find.text('Sign Out'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign Out'), findsOneWidget);
    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of Hagzy?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
    await tester.pumpAndSettle();

    // 4. Scroll back up and sign in with Phone Number via SMS verification code
    final phoneToggle = find.text('Phone Number');
    await tester.scrollUntilVisible(
      phoneToggle,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(phoneToggle, findsOneWidget);
    await tester.tap(phoneToggle);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Full Name (optional)'),
        'Captain Hegazy');
    await tester.enterText(
        find.widgetWithText(TextField, 'Phone Number'),
        '01012345678');

    final sendSmsBtn = find.text('Send SMS Verification Code');
    await tester.ensureVisible(sendSmsBtn);
    await tester.pumpAndSettle();
    await tester.tap(sendSmsBtn);
    await tester.pumpAndSettle();

    // Verify OTP verification view is shown for SMS
    expect(find.text('Enter Verification Code'), findsOneWidget);
    expect(find.textContaining('01012345678'), findsWidgets);

    // Enter 6-digit OTP and complete verification
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();
    final verifyPhoneBtn = find.text('Verify & Sign In');
    await tester.ensureVisible(verifyPhoneBtn);
    await tester.pumpAndSettle();
    await tester.tap(verifyPhoneBtn);
    await tester.pumpAndSettle();

    // Scroll up to view the signed-in profile card
    final captainName = find.text('Captain Hegazy');
    await tester.scrollUntilVisible(
      captainName,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(captainName, findsOneWidget);
    expect(find.text('01012345678'), findsWidgets);
  });

  test('subcategories taxonomy and detection for grooming, sports, and entertainment', () {
    expect(kAllSubCategories.map((s) => s.id), containsAll([
      'barbers',
      'salons',
      'padel',
      'soccer',
      'playstation',
      'billiards',
      'table_tennis',
      'escape_rooms',
    ]));

    // Auto-detection test on prototype venues
    final nader = naderSalonSample();
    expect(nader.effectiveSubCategories, contains('barbers'));

    final sportsVenue = Venue(
      id: 'test-soccer',
      name: 'Champions Turf',
      location: 'Cairo',
      type: VenueType.sports,
      items: [
        VenueItem(id: 'pitch-1', name: 'AstroTurf 5-a-side Football Pitch', kind: 'Soccer pitch', hourlyRate: 300),
      ],
    );
    expect(sportsVenue.effectiveSubCategories, contains('soccer'));

    final loungeVenue = Venue(
      id: 'test-escape',
      name: 'Mystery Escape Rooms',
      location: 'Cairo',
      type: VenueType.lounge,
      items: [
        VenueItem(id: 'escape-1', name: "Pharaoh's Tomb Escape Room", kind: 'Escape room', hourlyRate: 250),
      ],
    );
    expect(loungeVenue.effectiveSubCategories, contains('escape_rooms'));
  });

  testWidgets('customer can filter by subcategory pills with active banner and clear', (tester) async {
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': defaultPrototypeVenues().map((v) => v.toJson()).toList(),
        'bookings': [],
      }),
    });
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    final barberFinder = find.text('Barbers');
    await tester.scrollUntilVisible(
      barberFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Verify subcategory pill appears
    expect(barberFinder, findsWidgets);

    // Tap Barbers subcategory pill
    await tester.tap(barberFinder.first);
    await tester.pumpAndSettle();

    // Verify active filter banner appears with places count and clear option
    expect(find.textContaining('Barbers:'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Clear filter
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // Verify active filter banner is cleared
    expect(find.textContaining('Barbers:'), findsNothing);
  });

  testWidgets('when no places found in an area, customer can change area or explore all governorates', (tester) async {
    // Seed with a venue in Cairo, but user area is Aswan where there are 0 venues
    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': [
          {
            'id': 'cairo-club',
            'name': 'Cairo Sports Hub',
            'location': 'Cairo',
            'type': 'sports',
            'items': [
              {'id': 'c1', 'name': 'Court 1', 'kind': 'Padel court', 'hourlyRate': 300.0}
            ],
            'services': [],
          }
        ],
        'bookings': [],
      }),
      'hagzy_customer_area': 'Aswan',
    });
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Verify empty state is shown with area explanation
    final emptyFinder = find.text('No Places Found Here');
    await tester.scrollUntilVisible(
      emptyFinder,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(emptyFinder, findsOneWidget);
    expect(find.textContaining('No venues currently found in Aswan'), findsOneWidget);

    // Verify option to Change Area is present
    final changeAreaBtn = find.text('Change Area / Governorate');
    expect(changeAreaBtn, findsOneWidget);

    // Verify option to Explore All Egypt Governorates is present
    final exploreAllBtn = find.text('Explore All Egypt Governorates');
    expect(exploreAllBtn, findsOneWidget);

    // Tap Explore All Egypt Governorates
    await tester.tap(exploreAllBtn);
    await tester.pumpAndSettle();

    // Now Cairo Sports Hub appears
    expect(find.text('Cairo Sports Hub'), findsOneWidget);
  });

  testWidgets('customer can remove items from Book Again carousel and undo', (tester) async {
    final v1 = Venue(
      id: 'venue-ba-1',
      name: 'Kafr Padel Club',
      location: 'Kafr El Sheikh',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(id: 'i1', name: 'Court 1', kind: 'Padel court', hourlyRate: 300),
      ],
    );
    final b1 = Booking(
      id: 'b-ba-1',
      venueId: v1.id,
      itemId: 'i1',
      customer: 'Captain Hegazy',
      startsAt: DateTime.now().add(const Duration(days: 1)),
      durationMinutes: 60,
      price: 300,
      status: 'confirmed',
      paymentStatus: 'paid',
    );

    SharedPreferences.setMockInitialValues({
      'hagzy_app_data_v1': jsonEncode({
        'venues': [v1.toJson()],
        'bookings': [b1.toJson()],
      }),
      'hagzy_customer_area': 'Kafr El Sheikh',
    });

    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Verify Book Again is shown
    expect(find.text('Book Again'), findsOneWidget);
    expect(find.text('Kafr Padel Club'), findsWidgets);

    // Verify the remove button tooltip is present
    final removeFinder = find.byTooltip('Remove from Book Again');
    expect(removeFinder, findsOneWidget);

    // Tap remove
    await tester.tap(removeFinder);
    await tester.pumpAndSettle();

    // Verify Book Again section is now hidden since all venues are dismissed
    expect(find.text('Book Again'), findsNothing);
    expect(find.textContaining('Removed "Kafr Padel Club" from Book Again'), findsOneWidget);

    // Tap Undo
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    // Verify Book Again is restored
    expect(find.text('Book Again'), findsOneWidget);
  });

  testWidgets('customer can tap Privacy & Security and WhatsApp Updates in profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Navigate to Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Drag down to reveal settings
    await tester.drag(find.byType(CustomerProfileTab), const Offset(0, -600));
    await tester.pumpAndSettle();

    final privacyFinder = find.text('Privacy & Security');
    await tester.ensureVisible(privacyFinder);
    await tester.pumpAndSettle();
    expect(privacyFinder, findsOneWidget);
    await tester.tap(privacyFinder);
    await tester.pumpAndSettle();

    // Verify modal appears
    expect(find.text('15-Minute Guaranteed Slot Hold'), findsOneWidget);
    expect(find.text('PCI-DSS Paymob Escrow Protection'), findsOneWidget);

    // Dismiss modal
    Navigator.pop(tester.element(find.text('15-Minute Guaranteed Slot Hold')));
    await tester.pumpAndSettle();

    // Tap WhatsApp Booking Updates
    final whatsappFinder = find.text('WhatsApp Booking Updates');
    await tester.ensureVisible(whatsappFinder);
    await tester.pumpAndSettle();
    expect(whatsappFinder, findsOneWidget);
    await tester.tap(whatsappFinder);
    await tester.pumpAndSettle();

    // Verify WhatsApp modal appears
    expect(find.text('Instant Digital Match Pass & QR'), findsOneWidget);
    expect(find.text('Active on this account'), findsOneWidget);

    // Dismiss WhatsApp modal
    Navigator.pop(tester.element(find.text('Instant Digital Match Pass & QR')));
    await tester.pumpAndSettle();
  });

  testWidgets('customer can sign in with Google account and Apple account in profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Navigate to Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Verify Google and Apple buttons are present
    final googleBtn = find.text('Continue with Google');
    final appleBtn = find.text('Continue with Apple');
    expect(googleBtn, findsOneWidget);
    expect(appleBtn, findsOneWidget);

    // Tap Continue with Google
    await tester.tap(googleBtn);
    await tester.pumpAndSettle();

    // Tap Continue with Apple
    await tester.tap(appleBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('customer can sign in or register with email and password in profile', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Navigate to Profile tab
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Verify Password field and buttons are present
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);
    final signInBtn = find.text('Sign In with Password');
    final createAccountBtn = find.text('Create Account');
    expect(signInBtn, findsOneWidget);
    expect(createAccountBtn, findsOneWidget);

    // Fill form
    await tester.enterText(
        find.widgetWithText(TextField, 'Full Name (optional)'),
        'Ahmed Zaki');
    await tester.enterText(
        find.widgetWithText(TextField, 'Email Address'),
        'zaki@hagzy.app');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'),
        'securePass123');
    await tester.pumpAndSettle();

    // Tap Sign In with Password
    await tester.drag(find.byType(CustomerProfileTab), const Offset(0, -100));
    await tester.pumpAndSettle();
    await tester.tap(signInBtn, warnIfMissed: false);
    await tester.pumpAndSettle();

    // Verify customer is signed in
    final profileName = find.text('Ahmed Zaki');
    await tester.scrollUntilVisible(
      profileName,
      -200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    expect(profileName, findsOneWidget);
    expect(find.text('zaki@hagzy.app'), findsWidgets);
  });
}

