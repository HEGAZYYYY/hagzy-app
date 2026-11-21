import 'dart:convert';

import 'package:http/http.dart' as http;

import 'services/supabase_config.dart';

String resolveDefaultApiUrl() {
  const envUrl = String.fromEnvironment('HAGZY_API_URL');
  if (envUrl.isNotEmpty) return envUrl;
  return kDefaultEdgeApiUrl;
}

class HagzyApi {
  HagzyApi({String? baseUrl, http.Client? client})
      : baseUrl = (baseUrl ?? resolveDefaultApiUrl())
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
    return (result['venues'] as List<dynamic>?) ?? const [];
  }

  Future<List<dynamic>> bookings(String token) async {
    final result = await _send('GET', '/api/admin/bookings', token: token);
    return (result['bookings'] as List<dynamic>?) ?? const [];
  }

  Future<void> saveVenue(String token, Map<String, dynamic> venue) async {
    await _send('PUT',
        '/api/admin/venues/${Uri.encodeComponent((venue['id'] ?? '').toString())}',
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
    return {
      ...(result['booking'] is Map
          ? Map<String, dynamic>.from(result['booking'] as Map)
          : const <String, dynamic>{}),
      // Present only for wallet payments: the server-side balance after payment.
      if (result['walletBalance'] != null)
        'walletBalance': result['walletBalance'],
    };
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
    return result['booking'] is Map
        ? Map<String, dynamic>.from(result['booking'] as Map)
        : const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> submitPaymentProof(
    String bookingId, {
    required String method,
    required String reference,
  }) async {
    final cleanRef = reference.trim();
    final lowerMethod = method.toLowerCase();
    if (lowerMethod.contains('insta') ||
        lowerMethod.contains('vodafone') ||
        lowerMethod.contains('wallet')) {
      final intentMethod =
          (lowerMethod.contains('vodafone') || lowerMethod.contains('wallet'))
              ? 'MOBILE_WALLET'
              : 'INSTAPAY';
      try {
        await _send(
          'POST',
          '/api/payments/intent',
          body: {
            'bookingId': bookingId,
            'paymentMethod': intentMethod,
            'senderIdentifier': cleanRef,
          },
        );
      } catch (_) {
        // Fallback to payment-proof below if intent creation fails.
      }
    }
    final result = await _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/payment-proof',
      body: {
        'method': method,
        'reference': cleanRef,
      },
    );
    try {
      final latest = await bookingStatus(bookingId);
      return latest;
    } catch (_) {
      return result['booking'] is Map
          ? Map<String, dynamic>.from(result['booking'] as Map)
          : const <String, dynamic>{};
    }
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
    String paymentMethod = 'card',
  }) async {
    final result = await _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/paymob-intention',
      body: {
        'paymentMethod': paymentMethod,
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
    return (result['checkoutUrl'] ?? '').toString();
  }

  /// Requests a 6-digit OTP code for customer phone or email verification.
  Future<Map<String, dynamic>> requestCustomerOtp([
    String? phone,
    String? email,
    String? name,
    bool? isSignUp,
    bool? isPartner,
  ]) async =>
      _send(
        'POST',
        '/api/auth/customer-otp/request',
        body: {
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (isSignUp != null) 'isSignUp': isSignUp,
          if (isPartner != null) 'isPartner': isPartner,
        },
      );

  /// Requests a 6-digit OTP code with named parameters (for phone or email).
  Future<Map<String, dynamic>> requestVerificationOtp({
    String? phone,
    String? email,
    String? name,
    bool? isSignUp,
    bool? isPartner,
  }) async =>
      requestCustomerOtp(phone, email, name, isSignUp, isPartner);

  /// Verifies a customer OTP code (SMS or Email) and returns session token & customer profile.
  Future<Map<String, dynamic>> verifyCustomerOtp([
    String? phone,
    String? code,
    String? email,
    String? name,
    bool? isPartner,
  ]) async =>
      _send(
        'POST',
        '/api/auth/customer-otp/verify',
        body: {
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
          if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
          if (code != null && code.trim().isNotEmpty) 'code': code.trim(),
          if (isPartner != null) 'isPartner': isPartner,
        },
      );

  /// Verifies a customer OTP code with named parameters.
  Future<Map<String, dynamic>> verifyVerificationOtp({
    String? phone,
    String? email,
    required String code,
    String? name,
    bool? isPartner,
  }) async =>
      verifyCustomerOtp(phone, code, email, name, isPartner);

  /// Retrieves customer profile by email or phone.
  Future<Map<String, dynamic>> customerSignIn({
    String? name,
    String? email,
    String? phone,
  }) async =>
      getCustomerProfile(email: email, phone: phone);

  /// Authenticates a customer with a social identity provider (Google, Apple).
  Future<Map<String, dynamic>> signInWithSocial({
    required String provider, // 'google' | 'apple'
    required String email,
    required String name,
    String? providerId,
    String? avatar,
    String? idToken,
    bool? isPartner,
  }) async =>
      _send(
        'POST',
        '/api/auth/social/$provider',
        body: {
          'email': email.trim(),
          'name': name.trim(),
          if (providerId != null && providerId.trim().isNotEmpty)
            'providerId': providerId.trim(),
          if (provider == 'google' && providerId != null)
            'googleId': providerId.trim(),
          if (provider == 'apple' && providerId != null)
            'appleUserId': providerId.trim(),
          if (avatar != null && avatar.trim().isNotEmpty)
            'avatar': avatar.trim(),
          if (idToken != null && idToken.trim().isNotEmpty)
            provider == 'google' ? 'idToken' : 'identityToken': idToken.trim(),
          if (isPartner != null) 'isPartner': isPartner,
        },
      );

  /// Exchanges a verified customer/partner token for an admin/partner portal token.
  Future<Map<String, dynamic>> loginWithToken(String token) async =>
      _send('POST', '/api/auth/login', body: {'token': token});

  /// Submits or updates a venue owner's partner dashboard request.
  Future<Map<String, dynamic>> submitPartnerRequest({
    required String token,
    required String venueName,
    String venueType = 'padel',
    String city = 'Cairo',
    String address = '',
    String ownerName = '',
    String notes = '',
  }) async =>
      _send(
        'POST',
        '/api/partner/requests',
        token: token,
        body: {
          'venueName': venueName.trim(),
          'venueType': venueType.trim(),
          'city': city.trim(),
          if (address.trim().isNotEmpty) 'address': address.trim(),
          if (ownerName.trim().isNotEmpty) 'ownerName': ownerName.trim(),
          if (notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );

  /// Fetches the authenticated user's partner request & live approval status.
  Future<Map<String, dynamic>> getMyPartnerRequest({
    required String token,
  }) async =>
      _send('GET', '/api/partner/requests/me', token: token);

  /// Lists all partner requests for platform super-owner review.
  Future<List<Map<String, dynamic>>> getAdminPartnerRequests({
    required String adminToken,
  }) async {
    final res = await _send('GET', '/api/admin/partner-requests', token: adminToken);
    final raw = (res['requests'] as List<dynamic>?) ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Approves a partner request and creates/binds their singular venue.
  Future<Map<String, dynamic>> approvePartnerRequest({
    required String adminToken,
    required String requestId,
  }) async =>
      _send(
        'POST',
        '/api/admin/partner-requests/${Uri.encodeComponent(requestId)}/approve',
        token: adminToken,
      );

  /// Rejects a partner request with an optional reason.
  Future<Map<String, dynamic>> rejectPartnerRequest({
    required String adminToken,
    required String requestId,
    String reason = '',
  }) async =>
      _send(
        'POST',
        '/api/admin/partner-requests/${Uri.encodeComponent(requestId)}/reject',
        token: adminToken,
        body: {
          if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        },
      );

  /// Registers a new customer with verified email and password.
  Future<Map<String, dynamic>> registerCustomer({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async =>
      _send('POST', '/api/auth/customer/register', body: {
        'name': name.trim(),
        'email': email.trim(),
        'password': password,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      });

  /// Logs in a customer with registered email and password.
  Future<Map<String, dynamic>> loginCustomer({
    required String email,
    required String password,
  }) async =>
      _send('POST', '/api/auth/customer/login', body: {
        'email': email.trim(),
        'password': password,
      });

  /// Retrieves synced customer profile and cloud wallet balance.
  Future<Map<String, dynamic>> getCustomerProfile({
    String? token,
    String? phone,
    String? email,
  }) async {
    final queryParams = <String, String>{
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    final uri = Uri(path: '/api/customer/profile', queryParameters: queryParams.isEmpty ? null : queryParams);
    return _send('GET', uri.toString(), token: token);
  }

  /// Updates authenticated customer profile details on the server.
  Future<Map<String, dynamic>> updateCustomerProfile({
    required String token,
    String? name,
    String? phone,
    String? email,
  }) async =>
      _send(
        'PUT',
        '/api/customer/profile',
        token: token,
        body: {
          if (name != null) 'name': name.trim(),
          if (phone != null) 'phone': phone.trim(),
          if (email != null) 'email': email.trim(),
        },
      );

  /// Revokes an active customer session on the backend.
  Future<Map<String, dynamic>> logoutCustomer(String token) async =>
      _send('POST', '/api/auth/customer/logout', token: token);

  /// Permanently deletes the authenticated customer account from backend & Supabase Auth.
  Future<Map<String, dynamic>> deleteCustomerAccount(String token) async =>
      _send('DELETE', '/api/customer/account', token: token);

  /// Fetches linked users and booking summaries for Admin/Partner CRM.
  Future<List<Map<String, dynamic>>> adminUsers(String token) async {
    final res = await _send('GET', '/api/admin/users', token: token);
    final raw = (res['users'] as List<dynamic>?) ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Refreshes backend venue cache/sync state on Supabase.
  Future<Map<String, dynamic>> syncVenuesToCloud(String token) async =>
      _send('POST', '/api/admin/venues/sync-firebase', token: token);

  /// Atomically deducts customer wallet balance on the cloud server.
  Future<Map<String, dynamic>> deductWalletFunds({
    required double amount,
    String? token,
    String? phone,
    String? email,
  }) async =>
      _send(
        'POST',
        '/api/customer/wallet/deduct',
        token: token,
        body: {
          'amount': amount,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );

  /// Adds funds to the customer cloud wallet.
  Future<Map<String, dynamic>> addWalletFunds({
    required double amount,
    String? token,
    String? phone,
    String? email,
  }) async =>
      _send(
        'POST',
        '/api/customer/wallet/add',
        token: token,
        body: {
          'amount': amount,
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        },
      );

  /// Retrieves all confirmed and pending customer bookings from cloud server.
  Future<List<dynamic>> customerBookings({
    String? phone,
    String? email,
    String? token,
  }) async {
    final queryParams = <String, String>{
      if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
      if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
    };
    final uri = Uri(path: '/api/bookings', queryParameters: queryParams.isEmpty ? null : queryParams);
    final result = await _send('GET', uri.toString(), token: token);
    return result['bookings'] as List<dynamic>? ?? const [];
  }

  /// Cancels an eligible customer booking using the customer's authenticated session.
  Future<Map<String, dynamic>> cancelCustomerBooking(
    String bookingId, {
    required String token,
  }) async {
    return _send(
      'POST',
      '/api/bookings/${Uri.encodeComponent(bookingId)}/cancel',
      token: token,
    );
  }

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
    return result['booking'] is Map
        ? Map<String, dynamic>.from(result['booking'] as Map)
        : const <String, dynamic>{};
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
    return (result['bookings'] as List<dynamic>?) ?? const [];
  }

  /// Fetches the live Android gateway listener heartbeat status and recent transfer feed.
  Future<Map<String, dynamic>> getGatewayStatus() async =>
      _send('GET', '/api/payments/listener/status');

  /// Lists unmatched or flagged payment events in the review queue (admin/partner).
  Future<List<Map<String, dynamic>>> getPaymentReviewQueue(
    String adminToken,
  ) async {
    final res = await _send(
      'GET',
      '/api/admin/payments/review-queue',
      token: adminToken,
    );
    final raw = (res['items'] as List<dynamic>?) ?? const [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  /// Attaches a review-queue payment event to a booking or customer wallet.
  Future<Map<String, dynamic>> attachReviewQueueItem(
    String adminToken,
    String itemId, {
    String? bookingId,
    String? userId,
  }) async =>
      _send(
        'POST',
        '/api/admin/payments/review-queue/${Uri.encodeComponent(itemId)}/attach',
        token: adminToken,
        body: {
          if (bookingId != null && bookingId.isNotEmpty) 'bookingId': bookingId,
          if (userId != null && userId.isNotEmpty) 'userId': userId,
        },
      );

  /// Fetches persistent in-app notifications for the partner/admin dashboard.
  Future<Map<String, dynamic>> getAdminNotifications(
    String adminToken, {
    bool unreadOnly = false,
  }) async {
    final query = unreadOnly ? '?unreadOnly=true' : '';
    return _send('GET', '/api/admin/notifications$query', token: adminToken);
  }

  /// Marks a partner/admin notification as read.
  Future<Map<String, dynamic>> markAdminNotificationRead(
    String adminToken,
    String notificationId,
  ) async =>
      _send(
        'POST',
        '/api/admin/notifications/${Uri.encodeComponent(notificationId)}/read',
        token: adminToken,
      );

  /// Verifies a scanned booking QR pass and returns guest + financial details.
  Future<Map<String, dynamic>> getBookingQrDetails(
    String adminToken,
    String bookingId, {
    String? sig,
  }) async {
    final query = (sig != null && sig.trim().isNotEmpty)
        ? '?sig=${Uri.encodeQueryComponent(sig.trim())}'
        : '';
    return _send(
      'GET',
      '/api/admin/bookings/${Uri.encodeComponent(bookingId)}/qr-details$query',
      token: adminToken,
    );
  }

  /// Marks a confirmed booking as checked in at the venue.
  Future<Map<String, dynamic>> checkInBooking(
    String adminToken,
    String bookingId, {
    String? sig,
  }) async =>
      _send(
        'POST',
        '/api/admin/bookings/${Uri.encodeComponent(bookingId)}/check-in',
        token: adminToken,
        body: {
          if (sig != null && sig.trim().isNotEmpty) 'sig': sig.trim(),
        },
      );

  /// Updates the customer's chosen WhatsApp reminder timing for a booking.
  Future<Map<String, dynamic>> updateBookingReminder({
    required String bookingId,
    required int reminderOffsetMinutes,
    required String customerToken,
  }) async =>
      _send(
        'PUT',
        '/api/bookings/${Uri.encodeComponent(bookingId)}/reminder',
        token: customerToken,
        body: {'reminderOffsetMinutes': reminderOffsetMinutes},
      );

  /// Generates a full venue configuration using Gemini 1.5 Flash (or heuristic fallback)
  Future<Map<String, dynamic>> generateVenueWithAi({
    String? prompt,
    String? imageBase64,
    String? mimeType,
    String? categoryHint,
    bool? isArabic,
    String? token,
  }) async =>
      _send(
        'POST',
        '/api/ai/venue-generator',
        token: token,
        body: {
          if (prompt != null) 'prompt': prompt,
          if (imageBase64 != null) 'imageBase64': imageBase64,
          if (mimeType != null) 'mimeType': mimeType,
          if (categoryHint != null) 'categoryHint': categoryHint,
          if (isArabic != null) 'isArabic': isArabic,
        },
      );

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
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final errVal = decoded['error'] ?? decoded['message'] ?? decoded['msg'];
          if (errVal != null && errVal.toString().isNotEmpty) {
            message = errVal.toString();
          }
        }
      } catch (_) {
        if (response.body.isNotEmpty) message = '$message ${response.body}';
      }
      if (response.statusCode == 429) {
        // Never surface raw rate-limit internals to customers.
        message =
            'Too many attempts (HTTP 429). Please wait a minute and try again.';
      }
      throw Exception(message);
    }
    if (response.statusCode == 204 || response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
          'The Hagzy API returned an unexpected response.');
    }
    return Map<String, dynamic>.from(decoded);
  }
}
