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

  test('submitPaymentProof and confirmBooking send expected requests', () async {
    final requests = <http.Request>[];
    final api = HagzyApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/payment-proof')) {
          return http.Response(
            jsonEncode({
              'booking': {
                'id': 'booking-1',
                'venueId': 'venue-1',
                'itemId': 'court-1',
                'customer': 'Ali',
                'startsAt': DateTime.now().toIso8601String(),
                'durationMinutes': 60,
                'price': 400,
                'status': 'pending_payment',
                'paymentStatus': 'pending',
                'paymentMethod': 'instapay',
                'paymentReference': 'IPN-998877',
              }
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'booking': {
              'id': 'booking-1',
              'venueId': 'venue-1',
              'itemId': 'court-1',
              'customer': 'Ali',
              'startsAt': DateTime.now().toIso8601String(),
              'durationMinutes': 60,
              'price': 400,
              'status': 'confirmed',
              'paymentStatus': 'paid',
            }
          }),
          200,
        );
      }),
    );
    addTearDown(api.close);

    final proofResult = await api.submitPaymentProof(
      'booking-1',
      method: 'instapay',
      reference: 'IPN-998877',
    );
    expect(proofResult['paymentMethod'], 'instapay');
    expect(proofResult['paymentReference'], 'IPN-998877');

    final confirmResult = await api.confirmBooking('admin-jwt', 'booking-1');
    expect(confirmResult['status'], 'confirmed');
    expect(requests.last.headers['authorization'], 'Bearer admin-jwt');
  });

  test('createFawryCheckout and sendChatbotMessage send expected requests',
      () async {
    final requests = <http.Request>[];
    final api = HagzyApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/fawry-reference')) {
          return http.Response(
            jsonEncode({
              'referenceNumber': '9481029384',
              'serviceCode': '78890',
              'amount': 125.0,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/chatbot/message')) {
          return http.Response(
            jsonEncode({
              'reply': 'Your Fawry reference is 9481029384.',
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);

    final fawry = await api.createFawryCheckout(
      'booking-1',
      customerName: 'Ali Hassan',
      phone: '+201012345678',
    );
    expect(fawry['referenceNumber'], '9481029384');
    expect(fawry['serviceCode'], '78890');
    final fawryBody = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(fawryBody['customerName'], 'Ali Hassan');
    expect(fawryBody['phone'], '+201012345678');

    final reply = await api.sendChatbotMessage(
      'fawry code',
      bookingId: 'booking-1',
      phone: '+201012345678',
    );
    expect(reply['reply'], 'Your Fawry reference is 9481029384.');
  });

  test('signInWithSocial sends expected requests for Google and Apple', () async {
    final requests = <http.Request>[];
    final api = HagzyApi(
      baseUrl: 'https://api.example.test',
      client: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/social/google')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'token': 'google-jwt-token',
              'customer': {'name': 'Google User', 'email': 'user@gmail.com'},
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/social/apple')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'token': 'apple-jwt-token',
              'customer': {'name': 'Apple User', 'email': 'user@privaterelay.appleid.com'},
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
    addTearDown(api.close);

    final googleRes = await api.signInWithSocial(
      provider: 'google',
      email: 'user@gmail.com',
      name: 'Google User',
      providerId: 'g-12345',
    );
    expect(googleRes['token'], 'google-jwt-token');
    expect(requests[0].url.path, '/api/auth/social/google');
    final googleBody = jsonDecode(requests[0].body) as Map<String, dynamic>;
    expect(googleBody['email'], 'user@gmail.com');
    expect(googleBody['googleId'], 'g-12345');

    final appleRes = await api.signInWithSocial(
      provider: 'apple',
      email: 'user@privaterelay.appleid.com',
      name: 'Apple User',
      providerId: 'a-98765',
    );
    expect(appleRes['token'], 'apple-jwt-token');
    expect(requests[1].url.path, '/api/auth/social/apple');
    final appleBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(appleBody['appleUserId'], 'a-98765');
  });
}
