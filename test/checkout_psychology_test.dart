import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/core/services/receipt_ocr_verifier.dart';
import 'package:hagzy_app/features/checkout_psychology/checkout_psychology.dart';

void main() {
  group('Phase 4: Receipt OCR Verifier Logic (Track B)', () {
    test('Extracts Western numerals receipt correctly', () {
      const sampleInstapayReceipt = '''
      INSTAPAY RECEIPT
      Transaction Successful
      Ref No: 241030099882
      Amount: 60.00 EGP
      To: mohamedra4adhegazy@instapay
      Date: 30-10-2026 21:30
      ''';

      final result = ReceiptOcrVerifier.parseReceiptText(
        rawText: sampleInstapayReceipt,
        expectedDepositEgp: 50.0,
        existingOcrRefs: {},
      );

      expect(result.isValid, isTrue);
      expect(result.referenceNumber, '241030099882');
      expect(result.amountEgp, 60.0);
      expect(result.recipientHandle, 'mohamedra4adhegazy@instapay');
    });

    test('Extracts Eastern Arabic numerals (٠-٩) receipt correctly', () {
      const sampleArabicVodafoneReceipt = '''
      تم تحويل مبلغ ٦٠ جنيه بنجاح
      رقم العملية: ٩٨٧٦٥٤٣٢١٠
      إلى: ٠١٠١٢٣٤٥٦٧٨
      ''';

      final result = ReceiptOcrVerifier.parseReceiptText(
        rawText: sampleArabicVodafoneReceipt,
        expectedDepositEgp: 60.0,
        existingOcrRefs: {},
      );

      expect(result.isValid, isTrue);
      expect(result.referenceNumber, '9876543210');
      expect(result.amountEgp, 60.0);
    });

    test('Detects duplicate reference number to prevent fraud', () {
      const duplicateReceipt = '''
      INSTAPAY
      Ref: 241030099882
      Amount: 100.00 EGP
      ''';

      final result = ReceiptOcrVerifier.parseReceiptText(
        rawText: duplicateReceipt,
        expectedDepositEgp: 50.0,
        existingOcrRefs: {'241030099882'}, // Already recorded
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('already been submitted'));
    });

    test('Flags insufficient transfer amounts', () {
      const smallAmountReceipt = '''
      Ref: 5544332211
      Amount: 20.00 EGP
      ''';

      final result = ReceiptOcrVerifier.parseReceiptText(
        rawText: smallAmountReceipt,
        expectedDepositEgp: 60.0, // Expected 60 but only paid 20
        existingOcrRefs: {},
      );

      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('less than required deposit'));
    });
  });

  group('Phase 4: Checkout Psychology Widgets', () {
    testWidgets('ContrastAnchoredCheckoutCard renders hero total and deposit split',
        (tester) async {
      final booking = HagzyBooking(
        id: 'bk_anchored_1',
        unitId: 'unit_1',
        venueId: 'v_1',
        hostUserId: 'u_1',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 1)),
        headcount: 6,
        totalPriceEgp: 600.0,
        depositRequiredEgp: 60.0,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContrastAnchoredCheckoutCard(booking: booking),
          ),
        ),
      );

      expect(find.text('Total Booking Value'), findsOneWidget);
      expect(find.textContaining('600 EGP (6 Players • 100 EGP/ea)'), findsOneWidget);
      expect(find.text('Lock Instant Reservation'), findsOneWidget);
      expect(find.textContaining('60 EGP only'), findsOneWidget);
      expect(find.textContaining('Remaining (540 EGP) is paid in cash'), findsOneWidget);
    });

    testWidgets('LossAversionExitDialog renders Keep My Slot and Release slot',
        (tester) async {
      bool released = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LossAversionExitDialog(
              slotTimeFormatted: 'Thursday 9:00 PM',
              venueName: 'Stars Lounge',
              onKeepSlot: () {},
              onReleaseSlot: () => released = true,
            ),
          ),
        ),
      );

      expect(find.textContaining('Release Thursday 9:00 PM at Stars Lounge?'), findsOneWidget);
      expect(find.textContaining('other people viewed this slot recently'), findsOneWidget);
      expect(find.text('Keep My Slot 🔒'), findsOneWidget);
      expect(find.text('Release slot to others'), findsOneWidget);

      await tester.tap(find.text('Release slot to others'));
      await tester.pump();

      expect(released, isTrue);
    });
  });
}

