import 'dart:convert';
import 'package:http/http.dart' as http;

class PaymentService {
  PaymentService({
    required this.apiKey,
    required this.integrationId,
    required this.iframeId,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final int integrationId;
  final int iframeId;
  final http.Client _client;

  static const String _baseUrl = 'https://accept.paymob.com/api';

  /// Step 1: Authenticate with Paymob to get a token
  Future<String?> getAuthToken() async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/auth/tokens'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'api_key': apiKey}),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Step 2: Register an order for a booking
  Future<int?> createOrder({
    required String authToken,
    required double amountCents,
    required String bookingId,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/ecommerce/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'auth_token': authToken,
          'delivery_needed': 'false',
          'amount_cents': amountCents.toInt().toString(),
          'currency': 'EGP',
          'merchant_order_id': bookingId,
          'items': [],
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['id'] as int?;
      }
    } catch (_) {}
    return null;
  }

  /// Step 3: Request payment key for credit card, Meeza, or wallet
  Future<String?> getPaymentKey({
    required String authToken,
    required int orderId,
    required double amountCents,
    required Map<String, String> billingData,
  }) async {
    try {
      final response = await _client.post(
        Uri.parse('$_baseUrl/acceptance/payment_keys'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'auth_token': authToken,
          'amount_cents': amountCents.toInt().toString(),
          'expiration': 3600,
          'order_id': orderId,
          'billing_data': {
            'apartment': billingData['apartment'] ?? 'NA',
            'email': billingData['email'] ?? 'customer@hagzy.app',
            'floor': billingData['floor'] ?? 'NA',
            'first_name': billingData['first_name'] ?? 'Hagzy',
            'street': billingData['street'] ?? 'Cairo',
            'building': billingData['building'] ?? 'NA',
            'phone_number': billingData['phone_number'] ?? '+201000000000',
            'shipping_method': 'PKG',
            'postal_code': '00000',
            'city': billingData['city'] ?? 'Cairo',
            'country': 'EGY',
            'last_name': billingData['last_name'] ?? 'Customer',
            'state': billingData['state'] ?? 'Cairo',
          },
          'currency': 'EGP',
          'integration_id': integrationId,
          'lock_order_when_paid': 'false',
        }),
      );
      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['token'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Get Paymob iframe checkout URL
  String getCheckoutUrl(String paymentKey) {
    return 'https://accept.paymob.com/api/acceptance/iframes/$iframeId?payment_token=$paymentKey';
  }
}
