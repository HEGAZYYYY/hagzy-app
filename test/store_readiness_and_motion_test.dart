import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/main.dart';
import 'package:hagzy_app/theme/hagzy_theme.dart';
import 'package:hagzy_app/widgets/hagzy_components.dart';
import 'package:hagzy_app/widgets/hagzy_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    kDarkMode.value = false;
    kAppLanguage.value = 'EN';
  });

  tearDown(() {
    kDarkMode.value = false;
    kAppLanguage.value = 'EN';
  });

  testWidgets(
      'showHagzyDialog animates cleanly and respects reduced-motion accessibility',
      (tester) async {
    Future<void> pumpDialogHost({required bool disableAnimations}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: HagzyTheme.lightTheme(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: disableAnimations),
            child: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    onPressed: () {
                      showHagzyDialog<void>(
                        context: ctx,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Motion Check'),
                          content: const Text('Unified dialog transition.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text('Done'),
                            ),
                          ],
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Standard animated transition
    await pumpDialogHost(disableAnimations: false);
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Motion Check'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Motion Check'), findsNothing);

    // Reduced-motion mode completes immediately without lingering frames
    await pumpDialogHost(disableAnimations: true);
    await tester.tap(find.text('Open Dialog'));
    await tester.pump();
    expect(find.text('Motion Check'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('Motion Check'), findsNothing);
  });

  testWidgets('showHagzySheet renders content and dismisses cleanly',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: HagzyTheme.lightTheme(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: FilledButton(
                onPressed: () {
                  showHagzySheet<void>(
                    context: ctx,
                    builder: (sheetCtx) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Hagzy Sheet Title'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            child: const Text('Close Sheet'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Hagzy Sheet Title'), findsOneWidget);

    await tester.tap(find.text('Close Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Hagzy Sheet Title'), findsNothing);
  });

  testWidgets('HagzyTap triggers onTap when enabled and ignores taps when null',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: HagzyTheme.lightTheme(),
        home: Scaffold(
          body: Column(
            children: [
              HagzyTap(
                onTap: () => taps++,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Active Tap Target'),
                ),
              ),
              const HagzyTap(
                onTap: null,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Disabled Tap Target'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Active Tap Target'));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.tap(find.text('Disabled Tap Target'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets(
      'Login screen exposes accessible Terms of Service and Privacy Policy sheets',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Open Privacy Policy from Login screen
    final privacyLink = find.byKey(const Key('login_privacy_link'));
    await tester.ensureVisible(privacyLink);
    await tester.tap(privacyLink);
    await tester.pumpAndSettle();
    expect(find.text('Privacy Policy'), findsWidgets);
    expect(find.textContaining('Delete Account'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Open Terms of Service from Login screen
    final termsLink = find.byKey(const Key('login_terms_link'));
    await tester.ensureVisible(termsLink);
    await tester.tap(termsLink);
    await tester.pumpAndSettle();
    expect(find.text('Terms of Service'), findsWidgets);
    expect(find.textContaining('15-Minute Instant Hold'), findsOneWidget);
  });

  testWidgets(
      'Profile tab in-app Delete Account wipes session, favorites, and bookings and returns to login',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final venue = Venue(
      id: 'v-del-1',
      name: 'Maadi Padel Club',
      location: 'Cairo',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(
            id: 'c1', name: 'Court 1', kind: 'Padel', hourlyRate: 400),
      ],
    );
    final booking = Booking(
      id: 'b-del-1',
      venueId: venue.id,
      itemId: 'c1',
      customer: 'Nour Hassan',
      startsAt: DateTime.now().add(const Duration(hours: 4)),
      durationMinutes: 60,
      price: 400,
      dueNow: 100,
      status: 'confirmed',
      paymentStatus: 'paid',
    );

    SharedPreferences.setMockInitialValues({
      'hagzy_customer_profile_v1': jsonEncode({
        'name': 'Nour Hassan',
        'email': 'nour@hagzy.app',
        'phone': '01012345678',
        'isSignedIn': true,
        'token': 'test-token-delete',
      }),
      'hagzy_app_data_v1': jsonEncode({
        'venues': [venue.toJson()],
        'bookings': [booking.toJson()],
      }),
      'hagzy_favorite_venues_v1': ['v-del-1'],
      'hagzy_customer_area': 'Cairo',
    });

    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Navigate to Profile tab
    await tester.tap(find.text('Profile').last);
    await tester.pumpAndSettle();

    // Scroll to Delete Account button and open confirmation dialog
    final deleteBtn = find.byKey(const Key('delete_account_button'));
    await tester.scrollUntilVisible(
      deleteBtn,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    // Confirm deletion
    final confirmBtn = find.byKey(const Key('confirm_delete_account_button'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // Returned to Login screen and local personal data cleared
    expect(find.text('Explore Venues as Guest'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('hagzy_customer_profile_v1'), isNull);
    expect(prefs.getStringList('hagzy_favorite_venues_v1'), isNull);
    expect(prefs.getString('hagzy_customer_area'), isNull);
  });

  testWidgets(
      'Zero layout overflows across key store viewports (375x812, 390x844, 430x932, 1280x800) in LTR/RTL & Light/Dark',
      (tester) async {
    final configs = [
      (const Size(375, 812), 'EN', false),
      (const Size(390, 844), 'AR', false),
      (const Size(430, 932), 'EN', true),
      (const Size(1280, 800), 'AR', true),
    ];

    final venue = Venue(
      id: 'v-resp-1',
      name: 'Smash Padel Club (سماش بادل كلوب)',
      location: 'المعادي، القاهرة',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(
            id: 'c1', name: 'Court 1', kind: 'Padel', hourlyRate: 400),
      ],
    );

    for (final (size, lang, dark) in configs) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      kAppLanguage.value = lang;
      kDarkMode.value = dark;

      SharedPreferences.setMockInitialValues({
        'hagzy_customer_profile_v1': jsonEncode({
          'name': 'Salma Adel',
          'email': 'salma@hagzy.app',
          'phone': '01099887766',
          'isSignedIn': true,
          'token': 'test-token-resp',
        }),
        'hagzy_app_data_v1': jsonEncode({
          'venues': [venue.toJson()],
          'bookings': <dynamic>[],
        }),
      });

      final errors = <FlutterErrorDetails>[];
      final prevOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };
      try {
        await tester.pumpWidget(const HagzyApp());
        await tester.pumpAndSettle();

        if (lang == 'AR') {
          await tester.tap(find.text('AR').first);
          await tester.pumpAndSettle();
        }

        // Switch across Bookings and Profile tabs too
        await tester.tap(
          find.text(lang == 'AR' ? 'حجوزاتي' : 'Bookings').last,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(lang == 'AR' ? 'حسابي' : 'Profile').last,
        );
        await tester.pumpAndSettle();

        // Unmount cleanly before next viewport
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = prevOnError;
      }

      final overflowErrors = errors
          .where((e) => e.exceptionAsString().contains('RenderFlex'))
          .toList();
      expect(
        overflowErrors,
        isEmpty,
        reason: 'Unexpected RenderFlex overflow at $size ($lang, dark=$dark)',
      );
    }

    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  test('HagzyTheme light & dark disable Material ink ripple (NoSplash)', () {
    final light = HagzyTheme.lightTheme();
    final dark = HagzyTheme.darkTheme();
    expect(light.splashFactory, NoSplash.splashFactory);
    expect(dark.splashFactory, NoSplash.splashFactory);
    expect(light.splashColor, Colors.transparent);
    expect(dark.splashColor, Colors.transparent);
  });

  testWidgets(
      'showHagzyAdaptiveModal renders sheet on mobile (<600px), dialog on desktop (>=600px), and respects reduced motion',
      (tester) async {
    Future<void> runCase({
      required Size size,
      required bool disableAnimations,
      required bool expectSheet,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      String? result;
      bool? observedSheet;

      await tester.pumpWidget(
        MaterialApp(
          theme: HagzyTheme.lightTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: size,
              disableAnimations: disableAnimations,
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await showHagzyAdaptiveModal<String>(
                        context: context,
                        builder: (ctx, isSheet) {
                          observedSheet = isSheet;
                          return HagzyModalCard(
                            isSheet: isSheet,
                            title: isSheet
                                ? 'Mobile Adaptive Title'
                                : 'Desktop Adaptive Title',
                            subtitle: 'Subtle adaptive modal verification',
                            primaryLabel: 'Confirm',
                            onPrimary: () => Navigator.of(ctx).pop('confirmed'),
                            secondaryLabel: 'Cancel',
                          );
                        },
                      );
                    },
                    child: const Text('Open Modal'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Modal'));
      if (disableAnimations) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }

      expect(observedSheet, expectSheet);
      expect(
        find.text(expectSheet ? 'Mobile Adaptive Title' : 'Desktop Adaptive Title'),
        findsOneWidget,
      );

      await tester.tap(find.text('Confirm'));
      if (disableAnimations) {
        await tester.pump();
      } else {
        await tester.pumpAndSettle();
      }

      expect(result, 'confirmed');
      expect(
        find.text(expectSheet ? 'Mobile Adaptive Title' : 'Desktop Adaptive Title'),
        findsNothing,
      );
    }

    try {
      await runCase(
        size: const Size(390, 844),
        disableAnimations: false,
        expectSheet: true,
      );
      await runCase(
        size: const Size(1280, 800),
        disableAnimations: true,
        expectSheet: false,
      );
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  testWidgets(
      'Reviewer account (reviewer@hagzy.app + 123456) signs in seamlessly, seeds wallet/booking/favorite, rejects wrong OTP, and wipes cleanly on Delete Account',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    try {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const HagzyApp());
      await tester.pumpAndSettle();

      // Enter reviewer@hagzy.app into Email Address field and tap Log In
      final emailField = find.widgetWithText(TextField, 'Email Address');
      expect(emailField, findsOneWidget);
      await tester.enterText(emailField, 'reviewer@hagzy.app');
      await tester.tap(find.widgetWithText(FilledButton, 'Log In'));
      await tester.pumpAndSettle();

      expect(find.text('Enter Verification Code'), findsOneWidget);

      // Wrong OTP is rejected cleanly and remains on verification step
      await tester.enterText(find.byType(TextField).first, '000000');
      await tester.tap(find.text('Verify & Sign In'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Invalid verification code'), findsOneWidget);
      expect(find.text('Enter Verification Code'), findsOneWidget);

      // Correct OTP 123456 signs in immediately
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.tap(find.text('Verify & Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Explore Venues as Guest'), findsNothing);
      expect(find.text('Bookings'), findsWidgets);
      expect(find.text('Profile'), findsWidgets);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(HagzyWallet.keyWallet), 1000.0);
      final favs = prefs.getStringList(kFavoriteStorageKey);
      expect(favs, isNotNull);
      expect(favs, isNotEmpty);

      final rawData = prefs.getString(kStorageKey);
      expect(rawData, isNotNull);
      final decoded = jsonDecode(rawData!) as Map<String, dynamic>;
      final savedBookings = (decoded['bookings'] as List).cast<Map<String, dynamic>>();
      expect(
        savedBookings.any(
          (b) =>
              b['id'] == 'hagzy-reviewer-pass-1' &&
              b['status'] == 'confirmed' &&
              b['paymentStatus'] == 'paid',
        ),
        isTrue,
      );

      // Navigate to Bookings tab and verify confirmed seeded booking renders
      await tester.tap(find.text('Bookings').last);
      await tester.pumpAndSettle();
      expect(find.text('Confirmed'), findsWidgets);

      // Navigate to Profile tab and delete account cleanly
      await tester.tap(find.text('Profile').last);
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(const Key('delete_account_button'));
      await tester.scrollUntilVisible(
        deleteBtn,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      final confirmBtn = find.byKey(const Key('confirm_delete_account_button'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(find.text('Explore Venues as Guest'), findsOneWidget);
      expect(prefs.getString(kCustomerProfileStorageKey), isNull);
      expect(prefs.getStringList(kFavoriteStorageKey), isNull);
      expect(prefs.getDouble(HagzyWallet.keyWallet), isNull);
      final rawAfterDelete = prefs.getString(kStorageKey);
      if (rawAfterDelete != null) {
        final afterDecoded = jsonDecode(rawAfterDelete) as Map<String, dynamic>;
        expect((afterDecoded['bookings'] as List), isEmpty);
      }
    } finally {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });

  test('Dark mode text & semantic color tokens meet WCAG AA contrast (>= 4.5:1)',
      () {
    double contrastRatio(Color fg, Color bg) {
      final l1 = fg.computeLuminance();
      final l2 = bg.computeLuminance();
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    kDarkMode.value = true;
    try {
      final darkSurfaces = <String, Color>{
        'kPage': kPage,
        'kPanel': kPanel,
        'kPanelElevated': kPanelElevated,
      };
      final foregroundTokens = <String, Color>{
        'kInk': kInk,
        'kMuted': kMuted,
        'kGreen': kGreen,
        'kVolt': kVolt,
        'kSignal': kSignal,
        'kBrandAccent': kBrandAccent,
        'kSuccess': kSuccess,
        'kWarning': kWarning,
        'kError': kError,
        'kGold': kGold,
        'kCobalt': kCobalt,
        'kInfoBlue': kInfoBlue,
        'kTerracotta': kTerracotta,
      };

      for (final surface in darkSurfaces.entries) {
        for (final fg in foregroundTokens.entries) {
          final ratio = contrastRatio(fg.value, surface.value);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                'Dark mode ${fg.key} on ${surface.key} has low contrast (${ratio.toStringAsFixed(2)}:1)',
          );
        }
      }

      // Solid CTA contrast: white text on kAccentSurface
      expect(
        contrastRatio(kAccentOnSurface, kAccentSurface),
        greaterThanOrEqualTo(4.5),
      );

      // Dark input hint contrast against input fill (#23201D)
      final darkTheme = HagzyTheme.darkTheme();
      final hintColor = darkTheme.inputDecorationTheme.hintStyle!.color!;
      final inputFill = darkTheme.inputDecorationTheme.fillColor!;
      expect(
        contrastRatio(hintColor, inputFill),
        greaterThanOrEqualTo(4.5),
      );
    } finally {
      kDarkMode.value = false;
    }
  });
}
