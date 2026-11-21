import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/hagzy_api.dart';
import 'package:hagzy_app/models/models.dart';
import 'package:hagzy_app/screens/admin_workspace.dart';
import 'package:hagzy_app/screens/my_bookings_tab.dart';
import 'package:hagzy_app/screens/unified_payment_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('Booking.fromJson/toJson round-trips QR check-in & reminder metadata cleanly', () {
    final start = DateTime.now().add(const Duration(hours: 4));
    final parsed = Booking.fromJson({
      'id': 'bk_test_qr_1',
      'venueId': 'v_padel_1',
      'itemId': 'court_1',
      'customer': 'Karim',
      'startsAt': start.toIso8601String(),
      'durationMinutes': 60,
      'price': 400,
      'status': 'checked_in',
      'confirmed': true,
      'checkedIn': true,
      'checkedInAt': start.toIso8601String(),
      'qrSignature': 'abc123sig',
      'qrCheckInUrl': 'https://hagzy.shop/partner?scanBooking=bk_test_qr_1&sig=abc123sig',
      'actualPaidAmount': 100,
      'reminderOffsetMinutes': 360,
    });

    expect(parsed.checkedIn, isTrue);
    expect(parsed.isConfirmed, isTrue);
    expect(parsed.status, 'checked_in');
    expect(parsed.qrSignature, 'abc123sig');
    expect(parsed.actualPaidAmount, 100.0);
    expect(parsed.reminderOffsetMinutes, 360);

    final serialized = parsed.toJson();
    expect(serialized['checkedIn'], isTrue);
    expect(serialized['qrSignature'], 'abc123sig');
    expect(serialized['reminderOffsetMinutes'], 360);
  });

  testWidgets('MyBookingsTab renders QrImageView & reminder selector in check-in modal',
      (tester) async {
    final api = HagzyApi(baseUrl: '');
    addTearDown(api.close);
    var updatedMinutes = -1;

    final venue = Venue(
      id: 'v1',
      name: 'Nile Padel',
      location: 'Maadi',
      type: VenueType.sports,
      depositPercent: 25,
      items: [VenueItem(id: 'c1', name: 'Court 1', kind: 'Padel', hourlyRate: 400)],
    );
    final booking = Booking(
      id: 'bk_qr_modal_1',
      venueId: 'v1',
      itemId: 'c1',
      customer: 'Ahmed',
      startsAt: DateTime.now().add(const Duration(hours: 6)),
      durationMinutes: 60,
      price: 400,
      dueNow: 0,
      status: 'confirmed',
      paymentStatus: 'paid',
      actualPaidAmount: 100,
      qrSignature: 'sig_xyz',
      qrCheckInUrl: 'https://hagzy.shop/partner?scanBooking=bk_qr_modal_1&sig=sig_xyz',
      reminderOffsetMinutes: 120,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MyBookingsTab(
            venues: [venue],
            bookings: [booking],
            arabic: false,
            onChoosePayment: (_) async {},
            api: api,
            apiConfigured: false,
            onUpdateReminder: (_, mins) async {
              updatedMinutes = mins;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('QR Check-In Pass'), findsOneWidget);
    await tester.tap(find.text('QR Check-In Pass'));
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Deposit Paid'), findsOneWidget);
    expect(find.textContaining('Due at Venue'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('2h before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('6h before'));
    await tester.pumpAndSettle();

    expect(updatedMinutes, 360);
  });

  testWidgets('UnifiedPaymentScreen shows sender-match warning on InstaPay and Mobile Wallet tabs',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: UnifiedPaymentScreen(
          bookingId: 'bk_pay_warn',
          amount: 100,
          arabic: false,
          initialMethod: 'instapay',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('EXACT phone number or InstaPay handle'), findsOneWidget);

    await tester.tap(find.text('Mobile Wallet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('EXACT phone number or InstaPay handle'), findsOneWidget);
  });

  testWidgets('AdminManageWorkspace forwards partner requests, renders Gateway & Queue, and supports PosTab check-in',
      (tester) async {
    final venue = Venue(
      id: 'v_admin',
      name: 'Cairo Club',
      location: 'Nasr City',
      type: VenueType.sports,
      depositPercent: 25,
      items: [VenueItem(id: 'c1', name: 'Court 1', kind: 'Padel', hourlyRate: 400)],
    );
    final pendingBooking = Booking(
      id: 'bk_pending_1',
      venueId: 'v_admin',
      itemId: 'c1',
      customer: 'Omar',
      phone: '01011223344',
      startsAt: DateTime.now().add(const Duration(hours: 3)),
      durationMinutes: 60,
      price: 400,
      dueNow: 100,
      status: 'pending_payment',
    );
    final confirmedBooking = Booking(
      id: 'bk_confirmed_1',
      venueId: 'v_admin',
      itemId: 'c1',
      customer: 'Youssef',
      phone: '01055667788',
      startsAt: DateTime.now().add(const Duration(hours: 4)),
      durationMinutes: 60,
      price: 400,
      dueNow: 0,
      status: 'confirmed',
      paymentStatus: 'paid',
      qrSignature: 'sig123',
    );

    String? attachedItem;
    String? attachedBooking;
    String? checkedInId;
    String? dismissedNotif;

    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdminManageWorkspace(
            venues: [venue],
            bookings: [pendingBooking, confirmedBooking],
            apiConfigured: true,
            localPreview: false,
            isSingularPartner: false,
            partnerRequests: const [
              {
                'id': 'pr_widget_1',
                'venueName': 'Pending Club',
                'ownerName': 'Hossam',
                'status': 'pending',
                'city': 'Cairo',
                'venueType': 'padel',
              },
            ],
            onApprovePartnerRequest: (_) async {},
            onRejectPartnerRequest: (_) async {},
            adminNotifications: const [
              {
                'id': 'pn_1',
                'title': 'New booking from Omar',
                'body': 'Court 1 · 100 EGP deposit',
                'read': false,
              },
            ],
            onMarkNotificationRead: (id) async => dismissedNotif = id,
            onVerifyBookingQr: (id, sig) async => {
              'signatureVerified': true,
              'booking': confirmedBooking.toJson(),
              'financialSummary': {'totalPrice': 400, 'paidAmount': 100, 'remainingDue': 300},
            },
            onCheckInBooking: (id, sig) async => checkedInId = id,
            onLoadGatewayStatus: () async => {
              'isListenerActive': true,
              'lastHeartbeatAt': '2026-11-20T12:00:00Z',
              'recentLogs': [
                {'amount': 100, 'matched': true, 'bookingId': 'bk_confirmed_1', 'at': '12:00'},
              ],
            },
            onLoadReviewQueue: () async => [
              {
                'id': 'rev_1',
                'amount': 100,
                'payment_method': 'MOBILE_WALLET',
                'sender_identifier': '01011223344',
                'status': 'UNMATCHED',
                'reason': 'Arrived early',
              },
            ],
            onAttachReviewItem: (itemId, bId) async {
              attachedItem = itemId;
              attachedBooking = bId;
            },
            onAddVenue: () {},
            onEditVenue: (_) {},
            onAddItem: (_) {},
            onAddService: (_) {},
            onRemoveService: (v, s) {},
            onDelete: (_) {},
            onRemoveItem: (v, i) {},
            onWalkIn: (v, slot) {},
            onCancel: (_) {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // ManageTab receives forwarded partnerRequests
    expect(find.textContaining('Pending Club'), findsOneWidget);

    // Switch to POS timeline: notifications banner + Scan QR + Check In button
    await tester.tap(find.text('POS timeline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('New Booking Alerts (1)'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(dismissedNotif, 'pn_1');

    await tester.tap(find.text('Check In'));
    await tester.pumpAndSettle();
    expect(checkedInId, 'bk_confirmed_1');

    // Switch to Gateway & Queue tab: live oracle status + 1-tap Attach
    await tester.tap(find.text('Gateway & Queue'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Android Gateway Oracle: ACTIVE'), findsOneWidget);
    expect(find.textContaining('Review Queue (1 open)'), findsOneWidget);

    await tester.tap(find.text('Attach'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Attach & Confirm'));
    await tester.pumpAndSettle();
    expect(attachedItem, 'rev_1');
    expect(attachedBooking, 'bk_pending_1');
  });
}
