import 'dart:convert';

import 'package:http/http.dart' as http;

class HagzyApi {
  HagzyApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? const String.fromEnvironment('HAGZY_API_URL'))
            .trim()
            .replaceFirst(RegExp(r'/$'), ''),
        _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  bool get isConfigured => baseUrl.isNotEmpty;

  void close() => _client.close();

  Future<Map<String, dynamic>> login(String email, String password) async =>
      _send('POST', '/api/auth/login', body: {
        'email': email,
        'password': password,
      });

  Future<List<dynamic>> venues({String? adminToken}) async {
    final path = adminToken == null ? '/api/venues' : '/api/admin/venues';
    final result = await _send('GET', path, token: adminToken);
    return result['venues'] as List<dynamic>;
  }

  Future<List<dynamic>> bookings(String token) async {
    final result = await _send('GET', '/api/admin/bookings', token: token);
    return result['bookings'] as List<dynamic>;
  }

  Future<void> saveVenue(String token, Map<String, dynamic> venue) async {
    await _send('PUT',
        '/api/admin/venues/${Uri.encodeComponent(venue['id'] as String)}',
        token: token, body: venue);
  }

  Future<void> deleteVenue(String token, String venueId) async {
    await _send('DELETE', '/api/admin/venues/${Uri.encodeComponent(venueId)}',
        token: token);
  }

  Future<Map<String, dynamic>> createBooking(
    Map<String, dynamic> booking, {
    String? adminToken,
  }) async {
    final result =
        await _send('POST', '/api/bookings', token: adminToken, body: booking);
    return result['booking'] as Map<String, dynamic>;
  }

  Future<void> cancelBooking(String token, String bookingId) async {
    await _send(
        'DELETE', '/api/admin/bookings/${Uri.encodeComponent(bookingId)}',
        token: token);
  }

  Future<Map<String, dynamic>> confirmBooking(
    String token,
    String bookingId,
  ) async {
    final result = await _send(
      'POST',
      '/api/admin/bookings/${Uri.encodeComponent(bookingId)}/confirm',
      token: token,
    );
    return result['booking'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitPaymentProof(
    String bookingId, {
    required String method,
    required String reference,
  }) async {
    final result = await _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/payment-proof',
      body: {
        'method': method,
        'reference': reference.trim(),
      },
    );
    return result['booking'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitVenueReview(
    String venueId, {
    required String author,
    required double rating,
    String comment = '',
    String? phone,
    String? bookingId,
  }) async {
    final result = await _send(
      'POST',
      '/api/venues/${Uri.encodeComponent(venueId)}/reviews',
      body: {
        'author': author.trim(),
        'rating': rating,
        'comment': comment.trim(),
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (bookingId != null && bookingId.trim().isNotEmpty)
          'bookingId': bookingId.trim(),
      },
    );
    return result;
  }

  Future<String> createPaymobCheckout(
    String bookingId, {
    required String firstName,
    required String lastName,
    String? email,
    required String phone,
  }) async {
    final result = await _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/paymob-intention',
      body: {
        'billingData': {
          'first_name': firstName,
          'last_name': lastName,
          'phone_number': phone,
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          'apartment': 'NA',
          'floor': 'NA',
          'street': 'NA',
          'building': 'NA',
          'shipping_method': 'NA',
          'postal_code': 'NA',
          'city': 'Cairo',
          'country': 'EG',
          'state': 'Cairo',
        },
      },
    );
    return result['checkoutUrl'] as String;
  }

  /// Requests a 6-digit OTP for customer phone verification.
  Future<Map<String, dynamic>> requestCustomerOtp(String phone) async => _send(
        'POST',
        '/api/auth/customer-otp/request',
        body: {'phone': phone.trim()},
      );

  /// Verifies a customer OTP code and returns a signed customer session token.
  Future<Map<String, dynamic>> verifyCustomerOtp(
    String phone,
    String code,
  ) async =>
      _send(
        'POST',
        '/api/auth/customer-otp/verify',
        body: {
          'phone': phone.trim(),
          'code': code.trim(),
        },
      );

  /// Creates a FawryPay reference number for a pending booking deposit.
  Future<Map<String, dynamic>> createFawryCheckout(
    String bookingId, {
    required String customerName,
    required String phone,
  }) async {
    return _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/fawry-reference',
      body: {
        'customerName': customerName.trim(),
        'phone': phone.trim(),
      },
    );
  }

  /// Sends a message to the Hagzy WhatsApp / Assistant Chatbot endpoint.
  Future<Map<String, dynamic>> sendChatbotMessage(
    String message, {
    String? bookingId,
    String? phone,
    String? customerToken,
    String language = 'EN',
  }) async {
    return _send(
      'POST',
      '/api/chatbot/message',
      token: customerToken,
      body: {
        'message': message.trim(),
        if (bookingId != null && bookingId.isNotEmpty) 'bookingId': bookingId,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'language': language,
      },
    );
  }

  /// Polls a single booking's current status (public endpoint, no token needed).
  Future<Map<String, dynamic>> bookingStatus(String bookingId) async {
    final result =
        await _send('GET', '/api/bookings/${Uri.encodeComponent(bookingId)}');
    return result['booking'] as Map<String, dynamic>;
  }

  /// Looks up active bookings by customer phone number (requires verified customer OTP token).
  Future<List<dynamic>> bookingsByPhone(
    String phone, {
    String? customerToken,
  }) async {
    final encodedPhone = Uri.encodeQueryComponent(phone.trim());
    final result = await _send(
      'GET',
      '/api/bookings?phone=$encodedPhone',
      token: customerToken,
    );
    return result['bookings'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? body,
  }) async {
    if (!isConfigured) {
      throw StateError(
        'Shared Hagzy services are not configured. Build with --dart-define=HAGZY_API_URL=https://your-api.example.com.',
      );
    }
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final encodedBody = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'GET' => await _client.get(uri, headers: headers),
      'POST' => await _client.post(uri, headers: headers, body: encodedBody),
      'PUT' => await _client.put(uri, headers: headers, body: encodedBody),
      'DELETE' => await _client.delete(uri, headers: headers),
      _ => throw ArgumentError.value(method, 'method', 'Unsupported method'),
    };
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Hagzy API returned HTTP ${response.statusCode}.';
      try {
        final error = jsonDecode(response.body) as Map<String, dynamic>;
        if (error['error'] is String) message = error['error'] as String;
      } on FormatException {
        if (response.body.isNotEmpty) message = '$message ${response.body}';
      } on TypeError {
        if (response.body.isNotEmpty) message = '$message ${response.body}';
      }
      throw Exception(message);
    }
    if (response.statusCode == 204 || response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
          'The Hagzy API returned an unexpected response.');
    }
    return decoded;
  }
}
