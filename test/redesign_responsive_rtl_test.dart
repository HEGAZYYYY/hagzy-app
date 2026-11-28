import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/main.dart';
import 'package:hagzy_app/screens/admin_workspace.dart';
import 'package:hagzy_app/theme/hagzy_theme.dart';
import 'package:hagzy_app/widgets/common_widgets.dart';
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
      'Desktop viewport (>= 900px) renders split-screen login and top customer nav without bottom dock',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // Split-screen login renders showcase panel & auth form
    expect(find.text('Welcome to Hagzy'), findsOneWidget);
    expect(find.text('15-Minute Instant Slot Lock'), findsOneWidget);

    // Explore as guest transitions to desktop customer view
    await tester.tap(find.text('Explore Venues as Guest'));
    await tester.pumpAndSettle();

    // Desktop customer app shows top nav tabs and omits mobile bottom dock
    expect(find.byType(FloatingDock), findsNothing);
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('Bookings'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
  });

  testWidgets(
      'Desktop owner portal renders persistent sidebar and revenue bar chart in AnalyticsTab',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 840);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final venue = Venue(
      id: 'v-desktop-1',
      name: 'Emerald Padel Club',
      location: 'New Cairo',
      type: VenueType.sports,
      depositPercent: 25,
      items: [
        VenueItem(
            id: 'c1', name: 'Court 1', kind: 'Padel', hourlyRate: 450),
      ],
    );
    final booking = Booking(
      id: 'b-desktop-1',
      venueId: venue.id,
      itemId: 'c1',
      customer: 'Karim Adel',
      startsAt: DateTime.now().add(const Duration(hours: 2)),
      durationMinutes: 60,
      price: 450,
      dueNow: 112.5,
      status: 'confirmed',
      paymentStatus: 'paid',
    );

    SharedPreferences.setMockInitialValues({
      'hagzy_customer_profile_v1':
          '{"name":"Owner","email":"owner@hagzy.app","phone":"01012345678","isSignedIn":true,"token":"tok"}',
      'hagzy_app_data_v1': jsonEncode({
        'venues': [venue.toJson()],
        'bookings': [booking.toJson()],
      }),
    });

    await tester.pumpWidget(const HagzyApp(adminMode: true));
    await tester.pumpAndSettle();
    final dynamic state = tester.state(find.byType(HagzyHome));
    state.enterAdminPreviewForTesting();
    await tester.pumpAndSettle();

    // Desktop owner portal shows persistent sidebar rail and omits mobile bottom dock
    expect(find.byType(HagzyDesktopSidebar), findsOneWidget);
    expect(find.byType(FloatingDock), findsNothing);

    // Navigate to Analytics from sidebar
    await tester.tap(find.text('Analytics'));
    await tester.pumpAndSettle();

    expect(find.byType(AnalyticsTab), findsOneWidget);
    expect(find.byType(HagzyRevenueBarChart), findsOneWidget);
    expect(find.text('Revenue Distribution'), findsOneWidget);
    expect(find.text('Confirmation Rate'), findsOneWidget);
  });

  testWidgets('HagzyDirectionalChevron mirrors icon correctly for RTL Arabic',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: HagzyDirectionalChevron()),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.chevron_left_rounded);
  });

  testWidgets(
      'Brand system (HagzyBrandSymbol, HagzyBrandLoader, HagzySuccessSeal) & HagzySlidingSelector settle cleanly in LTR and RTL',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                const HagzyPrimaryLogo(arabic: true),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HagzyBrandSymbol(variant: HagzyBrandVariant.obsidian),
                    HagzyBrandSymbol(variant: HagzyBrandVariant.volt),
                    HagzyBrandSymbol(variant: HagzyBrandVariant.light),
                    HagzyBrandSymbol(variant: HagzyBrandVariant.monochromeDark),
                    HagzyBrandSymbol(
                        variant: HagzyBrandVariant.monochromeLight),
                  ],
                ),
                const HagzyBrandLoader(size: 36, label: 'جاري التحقق...'),
                const HagzySuccessSeal(size: 72),
                HagzySlidingSelector(
                  itemCount: 2,
                  selectedIndex: 1,
                  indicatorDecoration: BoxDecoration(
                    color: kVolt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  itemBuilder: (_, i, selected) => Center(child: Text('Tab $i')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HagzyBrandSymbol), findsWidgets);
    expect(find.byType(HagzyBrandLoader), findsOneWidget);
    expect(find.byType(HagzySuccessSeal), findsOneWidget);
    expect(find.text('Tab 0'), findsOneWidget);
    expect(find.text('Tab 1'), findsOneWidget);
  });

  testWidgets(
      'Compact mobile viewport (375x812) renders login and Explore feed with zero layout overflow',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Hagzy'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Explore Venues as Guest'));
    await tester.pumpAndSettle();

    expect(find.byType(FloatingDock), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
