import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hagzy_app/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Customer can sign in and profile displays account details',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const HagzyApp());
    await tester.pumpAndSettle();

    // 1. App opens on CustomerLoginScreen
    expect(find.text('Welcome to Hagzy'), findsOneWidget);

    // 2. Sign in with email directly in Log In mode
    await tester.enterText(
      find.widgetWithText(TextField, 'Email Address'),
      'ziad.hegazy@example.com',
    );
    await tester.pumpAndSettle();

    final loginBtn = find.text('Log In').first;
    await tester.ensureVisible(loginBtn);
    await tester.tap(loginBtn);
    await tester.pumpAndSettle();

    // 3. Enter 6-digit OTP
    expect(find.text('Enter Verification Code'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();

    // 4. Tap Verify & Sign In
    final verifyBtn = find.text('Verify & Sign In');
    await tester.ensureVisible(verifyBtn);
    await tester.tap(verifyBtn);
    await tester.pumpAndSettle();

    // 5. Verify user profile displays the account
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('ziad.hegazy@example.com'), findsWidgets);
  });

  testWidgets(
      'Customer can name account after login via onboarding modal sheet and update profile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    builder: (ctx) {
                      final ctrl = TextEditingController(text: 'Ziad Hegazy');
                      return Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('What should we call you?'),
                            TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                labelText: 'Your Full Name',
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, ctrl.text),
                              child: const Text('Save & Continue'),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
                child: const Text('Trigger Modal'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Trigger naming modal
    await tester.tap(find.text('Trigger Modal'));
    await tester.pumpAndSettle();

    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Your Full Name'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Ziad Hegazy');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save & Continue'));
    await tester.pumpAndSettle();

    expect(find.text('What should we call you?'), findsNothing);
  });
}
