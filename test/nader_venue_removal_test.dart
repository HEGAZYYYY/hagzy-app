import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/models/models.dart';
import 'package:hagzy_app/screens/book_tab.dart';
import 'package:flutter/material.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaultPrototypeVenues does not contain Nader El Khawaga', () {
    final prototypes = defaultPrototypeVenues();
    expect(
      prototypes.any((v) =>
          v.id == 'nader-el-khawaga-kafr-el-sheikh' ||
          v.name.toLowerCase().contains('nader')),
      isFalse,
    );
  });

  test('upsertNaderSalon cleanses and rejects Nader El Khawaga from venue lists', () {
    final venues = [
      naderSalonSample(),
      adrenalineEscapeRoomSample(),
    ];
    final result = upsertNaderSalon(venues);
    expect(
      result.any((v) =>
          v.id == 'nader-el-khawaga-kafr-el-sheikh' ||
          v.name.toLowerCase().contains('nader')),
      isFalse,
    );
    expect(result.length, 1);
    expect(result.first.id, 'adrenaline-escape-room-kafr-el-sheikh');
  });

  testWidgets('BookTab does not display or inject Nader El Khawaga if not present in venues',
      (WidgetTester tester) async {
    final venues = [
      adrenalineEscapeRoomSample(),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BookTab(
            venues: venues,
            bookings: const [],
            arabic: false,
            onBook: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify Nader El Khawaga is nowhere to be found in the UI
    expect(find.textContaining('Nader'), findsNothing);
    expect(find.textContaining('نادر'), findsNothing);
    expect(find.textContaining('Adrenaline'), findsWidgets);
  });
}
