import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hagzy_app/hagzy_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('admin API requests carry the backend-issued bearer session', () async {
    http.Request? captured;
    final api = HagzyApi(
      baseUrl: 'https://api.example.test/',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"venues":[]}', 200);
      }),
    );
    addTearDown(api.close);

    expect(await api.venues(adminToken: 'session-token'), isEmpty);
    expect(
        captured!.url.toString(), 'https://api.example.test/api/admin/venues');
    expect(captured!.headers['authorization'], 'Bearer session-token');
  });

  test('API errors are surfaced instead of treated as successful responses',
      () async {
    final api = HagzyApi(
      baseUrl: 'https://api.example.test',
      client: MockClient(
        (_) async => http.Response('{"error":"Overlap conflict."}', 409),
      ),
    );
    addTearDown(api.close);

    await expectLater(
      api.venues(),
      throwsA(
          predicate((error) => error.toString().contains('Overlap conflict.'))),
    );
  });

  test('unconfigured API explains how to enable shared mode', () async {
    final api = HagzyApi(
        baseUrl: '',
        client: MockClient((_) async {
          fail('An unconfigured API must not send a request.');
        }));
    addTearDown(api.close);

    await expectLater(
      api.venues(),
      throwsA(predicate((error) => error.toString().contains('HAGZY_API_URL'))),
    );
  });

  test('Paymob checkout does not require or send an email address', () async {
    http.Request? captured;
    final api = HagzyApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        captured = request;
        return http.Response('{"checkoutUrl":"https://pay.example.test"}', 200);
      }),
    );
    addTearDown(api.close);

    await api.createPaymobCheckout(
      'booking-1',
      firstName: 'Test',
      lastName: 'Customer',
      phone: '+201012345678',
    );

    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    final billingData = body['billingData'] as Map<String, dynamic>;
    expect(billingData['phone_number'], '+201012345678');
    expect(billingData.containsKey('email'), isFalse);
  });
}
