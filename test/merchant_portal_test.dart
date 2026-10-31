import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/features/merchant_portal/merchant_portal.dart';

void main() {
  group('Phase 5: Merchant Templates & Goal Gradient Logic', () {
    test('CategoryTemplates auto-loads realistic units for PlayStation', () {
      final units = CategoryTemplates.getTemplateUnitsForCategory(
        category: 'playstation',
        venueId: 'v_ps5',
      );

      expect(units.isNotEmpty, isTrue);
      final vip = units.first;
      expect(vip.pricingMode, PricingMode.hourlyTieredCapacity);
      expect(vip.pricingTiers['2'], 60);
      expect(vip.pricingTiers['4'], 100);
      expect(vip.addons.isNotEmpty, isTrue);
    });

    test('CategoryTemplates auto-loads additive services for Barbershops', () {
      final units = CategoryTemplates.getTemplateUnitsForCategory(
        category: 'barber',
        venueId: 'v_barber',
      );

      expect(units.isNotEmpty, isTrue);
      final chair = units.first;
      expect(chair.pricingMode, PricingMode.serviceMenu);
      expect(chair.serviceMenu.length, greaterThanOrEqualTo(2));
    });
  });

  group('Phase 5: Merchant Portal Widgets Rendering', () {
    testWidgets('GoalGradientOnboardingScreen displays 40% initial progress',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: GoalGradientOnboardingScreen(
            ownerId: 'owner_123',
            onVenueCreated: (_) {},
          ),
        ),
      );

      // Verify 40% complete callout (Principle 3)
      expect(find.textContaining('40% Complete'), findsOneWidget);
      expect(find.textContaining('Partner Account Initialized ✅'), findsOneWidget);
      expect(find.textContaining('Default Category Templates Loaded ✅'), findsOneWidget);
      expect(find.textContaining('Venue Name & 1-Tap GPS Pin 🔄'), findsOneWidget);
    });

    testWidgets('MerchantLossAversionBanner displays lost revenue and absorb button',
        (tester) async {
      bool proTapped = false;
      bool absorbTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MerchantLossAversionBanner(
              estimatedLostRevenueEgp: 1450.0,
              noShowCount: 6,
              onUpgradePro: () => proTapped = true,
              onDismissAbsorbLosses: () => absorbTapped = true,
            ),
          ),
        ),
      );

      expect(find.textContaining('1450 EGP'), findsOneWidget);
      expect(find.textContaining('6 no-shows'), findsOneWidget);
      expect(find.text('Turn On Automated Deposits'), findsOneWidget);
      expect(find.text('I\'ll absorb the losses'), findsOneWidget);

      await tester.tap(find.text('Turn On Automated Deposits'));
      await tester.pump();
      expect(proTapped, isTrue);

      await tester.tap(find.text('I\'ll absorb the losses'));
      await tester.pump();
      expect(absorbTapped, isTrue);
    });

    testWidgets('QrStandeeGenerator renders venue poster with 10s booking headline',
        (tester) async {
      final venue = HagzyVenue(
        id: 'v_standee',
        ownerId: 'o_1',
        name: 'The Cave Gaming Lounge',
        city: 'Kafr El Sheikh',
        categories: ['playstation'],
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QrStandeeGenerator(venue: venue),
        ),
      );

      expect(find.text('HAGZY • حِجْزِي'), findsOneWidget);
      expect(find.text('The Cave Gaming Lounge'), findsOneWidget);
      expect(find.text('Book Your Table or Room in 10s'), findsOneWidget);
      expect(find.text('Scan to Book Instantly'), findsOneWidget);
    });
  });
}

