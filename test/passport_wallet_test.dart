import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/features/passport_wallet/passport_wallet.dart';

void main() {
  group('Hagzy Lifestyle Passport & Cross-Category Vouchers', () {
    testWidgets('UserReliabilityPassportCard displays 100% score and unlocked zero-deposit perk',
        (tester) async {
      final vipProfile = UserProfile(
        id: 'usr_vip',
        phoneNumber: '01011223344',
        displayName: 'Ziad Hagzy',
        reliabilityScore: 98.0,
        completedBookingsCount: 16,
        noShowCount: 0,
        hagzyWalletBalance: 250.0,
        badges: const ['reliable', 'shilla_leader', 'gamer_vip'],
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserReliabilityPassportCard(profile: vipProfile),
          ),
        ),
      );

      expect(find.text('Hagzy Lifestyle Passport'), findsOneWidget);
      expect(find.text('Verified Lifestyle Member'), findsOneWidget);
      expect(find.text('98%'), findsOneWidget);
      expect(find.textContaining('Zero-Deposit Weekday Booking Perks'), findsOneWidget);
      expect(find.text('16'), findsOneWidget); // completed count
      expect(find.text('0'), findsOneWidget); // no-show count
      expect(find.text('250 EGP'), findsOneWidget);
      expect(find.textContaining('Shilla Leader'), findsOneWidget);
      expect(find.textContaining('Gamer VIP'), findsOneWidget);
    });

    testWidgets('CrossCategoryVouchersCarousel renders cross-vertical vouchers and triggers redeem',
        (tester) async {
      CrossCategoryVoucher? redeemed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CrossCategoryVouchersCarousel(
              onRedeemVoucher: (v) => redeemed = v,
            ),
          ),
        ),
      );

      expect(find.text('Cross-Vertical Loyalty Perks'), findsOneWidget);
      expect(find.text('PlayStation VIP Room'), findsOneWidget);
      expect(find.text('20% OFF'), findsOneWidget);
      expect(find.textContaining('Workspaces'), findsOneWidget);

      await tester.tap(find.text('Use Voucher ⚡').first);
      await tester.pumpAndSettle();

      expect(redeemed, isNotNull);
      expect(redeemed!.id, 'v_ps5_workspace');
      expect(find.textContaining('Applied 20% OFF'), findsOneWidget);
    });

    testWidgets('TopUpWalletSheet allows custom amount input and chip selection',
        (tester) async {
      double? topUpAmount;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  TopUpWalletSheet.show(
                    context: context,
                    currentBalance: 75.0,
                    onProceedToPayment: (amt) => topUpAmount = amt,
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );

      // Open sheet
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();

      expect(find.text('Top Up Hagzy Wallet'), findsOneWidget);
      expect(find.text('Current Balance: 75 EGP'), findsOneWidget);

      // Verify preset chips exist
      expect(find.text('+50 EGP'), findsOneWidget);
      expect(find.text('+100 EGP'), findsOneWidget);
      expect(find.text('+200 EGP'), findsOneWidget);
      expect(find.text('+500 EGP'), findsOneWidget);
      expect(find.text('+1000 EGP'), findsOneWidget);

      // Tap on +200 EGP chip
      await tester.tap(find.text('+200 EGP'));
      await tester.pumpAndSettle();

      expect(find.text('200'), findsOneWidget);

      // Enter custom amount '350'
      final textField = find.byType(TextFormField);
      await tester.enterText(textField, '350');
      await tester.pumpAndSettle();

      // Submit via CTA button
      await tester.tap(find.text('Continue to Payment (350 EGP) →'));
      await tester.pumpAndSettle();

      expect(topUpAmount, 350.0);
    });

    testWidgets('UserReliabilityPassportCard triggers onTopUpTap on Hagzy Balance tap',
        (tester) async {
      bool topUpTapped = false;
      final profile = UserProfile(
        id: 'usr_test',
        phoneNumber: '01011223344',
        displayName: 'Test User',
        reliabilityScore: 90.0,
        completedBookingsCount: 5,
        noShowCount: 0,
        hagzyWalletBalance: 120.0,
        badges: const ['reliable'],
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UserReliabilityPassportCard(
              profile: profile,
              onTopUpTap: () => topUpTapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('120 EGP'));
      await tester.pumpAndSettle();

      expect(topUpTapped, isTrue);
    });
  });
}
