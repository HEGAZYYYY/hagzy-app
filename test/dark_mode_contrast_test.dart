import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/theme/hagzy_theme.dart';
import 'package:hagzy_app/screens/admin_workspace.dart';

void main() {
  setUp(() {
    kDarkMode.value = false;
  });

  tearDown(() {
    kDarkMode.value = false;
  });

  test('kSnackBarBg provides high-contrast dark background in both light and dark mode', () {
    kDarkMode.value = false;
    expect(kSnackBarBg, const Color(0xFF0F172A));

    kDarkMode.value = true;
    expect(kSnackBarBg, const Color(0xFF1F352D));
  });

  testWidgets('New Booking Alerts card renders dark theme with visible contrast in dark mode',
      (WidgetTester tester) async {
    kDarkMode.value = true;

    final unread = [
      {
        'id': 'notif_1',
        'title': 'New Booking for Salon Nader',
        'body': 'Omar Khatab booked VIP Chair 1',
      }
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: HagzyTheme.darkTheme(),
        home: Scaffold(
          body: AdminManageWorkspace(
            venues: const [],
            bookings: const [],
            adminNotifications: unread,
            onAddVenue: () {},
            onEditVenue: (_) {},
            onAddItem: (_) {},
            onAddService: (_) {},
            onRemoveService: (_, __) {},
            onDelete: (_) {},
            onRemoveItem: (_, __) {},
            onWalkIn: (_, __) {},
            onCancel: (_) {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to POS timeline tab where notifications live
    await tester.tap(find.text('POS timeline'));
    await tester.pumpAndSettle();

    // Verify Title text is rendered with Colors.white
    final titleFinder = find.text('New Booking for Salon Nader');
    expect(titleFinder, findsOneWidget);
    final titleWidget = tester.widget<Text>(titleFinder);
    expect(titleWidget.style?.color, Colors.white);

    // Verify Subtitle text is rendered with light slate Color(0xFF94A3B8)
    final subtitleFinder = find.text('Omar Khatab booked VIP Chair 1');
    expect(subtitleFinder, findsOneWidget);
    final subtitleWidget = tester.widget<Text>(subtitleFinder);
    expect(subtitleWidget.style?.color, const Color(0xFF94A3B8));
  });

  testWidgets('New Booking Alerts card renders light theme with visible contrast in light mode',
      (WidgetTester tester) async {
    kDarkMode.value = false;

    final unread = [
      {
        'id': 'notif_2',
        'title': 'New Booking for Padel',
        'body': 'Ahmed booked Court 1',
      }
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: HagzyTheme.lightTheme(),
        home: Scaffold(
          body: AdminManageWorkspace(
            venues: const [],
            bookings: const [],
            adminNotifications: unread,
            onAddVenue: () {},
            onEditVenue: (_) {},
            onAddItem: (_) {},
            onAddService: (_) {},
            onRemoveService: (_, __) {},
            onDelete: (_) {},
            onRemoveItem: (_, __) {},
            onWalkIn: (_, __) {},
            onCancel: (_) {},
            onConfirm: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to POS timeline tab where notifications live
    await tester.tap(find.text('POS timeline'));
    await tester.pumpAndSettle();

    // Verify Title text is rendered with dark ink Color(0xFF0F172A)
    final titleFinder = find.text('New Booking for Padel');
    expect(titleFinder, findsOneWidget);
    final titleWidget = tester.widget<Text>(titleFinder);
    expect(titleWidget.style?.color, const Color(0xFF0F172A));

    // Verify Subtitle text is rendered with dark slate Color(0xFF334155)
    final subtitleFinder = find.text('Ahmed booked Court 1');
    expect(subtitleFinder, findsOneWidget);
    final subtitleWidget = tester.widget<Text>(subtitleFinder);
    expect(subtitleWidget.style?.color, const Color(0xFF334155));
  });
}
