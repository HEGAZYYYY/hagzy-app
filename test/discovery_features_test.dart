import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/core/utils/smart_defaults.dart';
import 'package:hagzy_app/features/discovery/discovery.dart';

void main() {
  group('Phase 2: Smart Defaults Heuristics', () {
    test('8:00 AM to 4:00 PM resolves to dayProductivity vibe', () {
      final morning = DateTime(2026, 10, 30, 10, 30);
      final vibe = DiscoveryVibe.fromDateTime(morning);

      expect(vibe, DiscoveryVibe.dayProductivity);
      expect(vibe.recommendedCategories, contains('workspace'));
      expect(vibe.recommendedCategories, contains('barber'));
    });

    test('4:00 PM to 1:00 AM resolves to eveningHangout vibe', () {
      final night = DateTime(2026, 10, 30, 21, 0); // 9:00 PM
      final vibe = DiscoveryVibe.fromDateTime(night);

      expect(vibe, DiscoveryVibe.eveningHangout);
      expect(vibe.recommendedCategories, contains('playstation'));
      expect(vibe.recommendedCategories, contains('billiards'));
      expect(vibe.recommendedCategories, contains('court'));
      expect(vibe.recommendedCategories, contains('escape_room'));
    });

    test('Dynamic CTA never says just Search and shows reward count', () {
      final ctaEn = buildDynamicCtaText(
        availableCount: 14,
        vibe: DiscoveryVibe.eveningHangout,
        isArabic: false,
      );
      expect(ctaEn, 'Show 14 Venues Open Tonight →');

      final ctaAr = buildDynamicCtaText(
        availableCount: 8,
        vibe: DiscoveryVibe.dayProductivity,
        isArabic: true,
      );
      expect(ctaAr, contains('8'));
      expect(ctaAr, contains('مذاكرة'));
    });

    test('ShillaSizePreset filters units by capacity', () {
      final soloUnit = BookableUnit(
        id: 'u1',
        venueId: 'v1',
        category: 'workspace',
        unitName: 'Desk 1',
        pricingMode: PricingMode.timePass,
        basePriceEgp: 20,
        minCapacity: 1,
        maxCapacity: 1,
      );

      final squadUnit = BookableUnit(
        id: 'u2',
        venueId: 'v1',
        category: 'court',
        unitName: 'Pitch 5v5',
        pricingMode: PricingMode.hourlyFlat,
        basePriceEgp: 300,
        minCapacity: 10,
        maxCapacity: 14,
      );

      expect(ShillaSizePreset.solo.matchesUnit(soloUnit), isTrue);
      expect(ShillaSizePreset.solo.matchesUnit(squadUnit), isFalse);

      expect(ShillaSizePreset.squad.matchesUnit(squadUnit), isTrue);
      expect(ShillaSizePreset.squad.matchesUnit(soloUnit), isFalse);
    });
  });

  group('Phase 2: Discovery Widgets Rendering', () {
    testWidgets('ShillaGroupSizeFilterBar renders and responds to tap', (tester) async {
      ShillaSizePreset selected = ShillaSizePreset.all;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShillaGroupSizeFilterBar(
              selectedPreset: selected,
              onPresetSelected: (preset) {
                selected = preset;
              },
            ),
          ),
        ),
      );

      expect(find.text('Shilla Group Size'), findsOneWidget);
      expect(find.text('Solo'), findsOneWidget);
      expect(find.text('2 Friends'), findsOneWidget);
      expect(find.text('3-5 Friends'), findsOneWidget);
      expect(find.text('6+ Squad'), findsOneWidget);

      await tester.tap(find.text('2 Friends'));
      await tester.pump();

      expect(selected, ShillaSizePreset.duo);
    });

    testWidgets('OpenLobbyFeedCarousel displays active challenger match', (tester) async {
      final sampleLobby = HagzyBooking(
        id: 'bk_open_1',
        unitId: 'unit_table',
        venueId: 'v_stars',
        hostUserId: 'usr_host',
        startTime: DateTime(2026, 10, 30, 21, 0),
        endTime: DateTime(2026, 10, 30, 22, 0),
        isOpenLobby: true,
        totalSlots: 2,
        filledSlots: 1,
        neededRoles: ['1v1_challenger'],
        lobbyTitle: 'Ping Pong 1v1 Challenger',
        totalPriceEgp: 50,
        depositRequiredEgp: 20,
        createdAt: DateTime.now(),
        venueName: 'Stars Lounge',
        venueCity: 'Kafr El Sheikh',
      );

      bool joined = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OpenLobbyFeedCarousel(
              activeLobbies: [sampleLobby],
              onJoinLobby: (lobby) {
                joined = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Open Lobbies & Challengers'), findsOneWidget);
      expect(find.text('Ping Pong 1v1 Challenger'), findsOneWidget);
      expect(find.text('Stars Lounge • Kafr El Sheikh'), findsOneWidget);

      await tester.tap(find.text('Accept Challenge ⚔️'));
      await tester.pump();

      expect(joined, isTrue);
    });
  });
}

