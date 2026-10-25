import 'dart:convert';
import 'package:http/http.dart' as http;
import 'url_launcher_stub.dart' if (dart.library.html) 'url_launcher_web.dart';

class NotificationService {
  NotificationService({
    required this.whatsappApiToken,
    required this.whatsappInstanceId,
    required this.smsApiKey,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String whatsappApiToken;
  final String whatsappInstanceId;
  final String smsApiKey;
  final http.Client _client;

  /// Send automated WhatsApp confirmation via UltraMsg / Cloud API
  Future<bool> sendWhatsAppMessage({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty || whatsappApiToken.isEmpty) return false;

    final formattedPhone = cleanPhone.startsWith('0') ? '2$cleanPhone' : cleanPhone;

    try {
      final response = await _client.post(
        Uri.parse('https://api.ultramsg.com/$whatsappInstanceId/messages/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': whatsappApiToken,
          'to': formattedPhone,
          'body': message,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Send SMS OTP or booking alert via Egyptian gateway (e.g., VictoryLink / CEQUENS)
  Future<bool> sendSms({
    required String phone,
    required String message,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.isEmpty || smsApiKey.isEmpty) return false;

    try {
      final response = await _client.post(
        Uri.parse('https://sms.hagzy.app/api/v1/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $smsApiKey',
        },
        body: jsonEncode({
          'recipient': cleanPhone,
          'message': message,
        }),
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
