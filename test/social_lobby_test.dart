import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/core/models/models_v2.dart';
import 'package:hagzy_app/features/social_lobby/social_lobby.dart';

void main() {
  group('Social Lobby Roster & Challenger UI', () {
    final now = DateTime.now();
    final testLobby = HagzyBooking(
      id: 'lobby_test_padel',
      unitId: 'unit_padel_1',
      venueId: 'v_padel_hub',
      hostUserId: 'host_captain',
      startTime: DateTime(now.year, now.month, now.day, 20, 0),
      endTime: DateTime(now.year, now.month, now.day, 21, 30),
      isOpenLobby: true,
      totalSlots: 4,
      filledSlots: 2,
      neededRoles: const ['GK', 'DEF'],
      lobbyTitle: 'Padel Night Mini Match',
      totalPriceEgp: 400.0,
      depositRequiredEgp: 100.0,
      createdAt: now,
      venueName: 'Padel Hub',
      unitName: 'Court 1',
      venueCity: 'New Cairo',
      participantIds: const ['host_captain', 'player_2'],
    );

    testWidgets('SocialLobbyRosterScreen renders squad match details and per-person split',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SocialLobbyRosterScreen(
            lobby: testLobby,
          ),
        ),
      );

      // Verify title & venue info
      expect(find.text('Padel Night Mini Match'), findsOneWidget);
      expect(find.textContaining('Padel Hub'), findsWidgets);
      expect(find.text('2 spots left'), findsOneWidget);

      // Per-person share = 400 / 4 = 100 EGP
      expect(find.text('100 EGP'), findsWidgets);
      expect(find.textContaining('Total: 400 EGP'), findsOneWidget);

      // Verify Needed Roles
      expect(find.text('Goalkeeper (GK)'), findsOneWidget);
      expect(find.text('Defender (DEF)'), findsOneWidget);

      // Verify WhatsApp invite button
      expect(find.text('Invite Your Squad on WhatsApp'), findsOneWidget);
      expect(find.text('Claim My Spot (100 EGP)'), findsOneWidget);
    });

    testWidgets('SocialLobbyRosterScreen claims a spot and increments filled slots',
        (tester) async {
      HagzyBooking? claimed;

      await tester.pumpWidget(
        MaterialApp(
          home: SocialLobbyRosterScreen(
            lobby: testLobby,
            userProfile: UserProfile(
              id: 'new_joiner_1',
              phoneNumber: '01012345678',
              displayName: 'Karim Squad',
              createdAt: DateTime(2026, 1, 1),
            ),
            onSpotClaimed: (updated) => claimed = updated,
          ),
        ),
      );

      await tester.tap(find.text('Claim My Spot (100 EGP)'));
      await tester.pumpAndSettle();

      expect(claimed, isNotNull);
      expect(claimed!.filledSlots, 3);
      expect(claimed!.participantIds.contains('new_joiner_1'), isTrue);
      expect(find.text('1 spots left'), findsOneWidget);
    });
  });
}
