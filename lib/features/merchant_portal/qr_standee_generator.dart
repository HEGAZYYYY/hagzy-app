import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/models/models_v2.dart';

String resolveVenueBookingUrl(String venueId) {
  const envUrl = String.fromEnvironment('HAGZY_PUBLIC_URL');
  if (envUrl.isNotEmpty) {
    final clean = envUrl.endsWith('/') ? envUrl.substring(0, envUrl.length - 1) : envUrl;
    return '$clean/#/venue/$venueId';
  }
  if (kIsWeb) {
    try {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.contains('localhost') && !origin.contains('127.0.0.1')) {
        return '$origin/#/venue/$venueId';
      }
    } catch (_) {}
  }
  return 'https://hagzy-booking.web.app/#/venue/$venueId';
}

/// Printable In-App Counter Standee Generator for Venue Merchants
class QrStandeeGenerator extends StatelessWidget {
  final HagzyVenue venue;
  final VoidCallback? onPrintOrShare;
  final bool isArabic;

  const QrStandeeGenerator({
    super.key,
    required this.venue,
    this.onPrintOrShare,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    final bookingUrl = resolveVenueBookingUrl(venue.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'بوستر الطاولات والكونتر (QR Standee)' : 'Counter QR Standee',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (onPrintOrShare != null)
            IconButton(
              icon: const Icon(Icons.print_rounded),
              onPressed: onPrintOrShare,
            ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, // High contrast white for physical paper printing
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top Brand Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.flash_on_rounded, color: Colors.amber, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'HAGZY • حِجْزِي',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Venue Name
                Text(
                  venue.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                Text(
                  venue.city,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),

                // Real Dynamic QR Code Generator for Venue Deep-Link
                Container(
                  width: 210,
                  height: 210,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12, width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      QrImageView(
                        data: bookingUrl,
                        version: QrVersions.auto,
                        size: 135.0,
                        gapless: true,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isArabic ? 'امسح للحجز الفوري' : 'Scan to Book Instantly',
                        style: TextStyle(
                          color: Colors.black.withValues(alpha: 0.7),
                          fontSize: 12.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Catchy Egyptian Headline
                Text(
                  isArabic
                      ? 'احجز غرفتك أو طاولتك في ١٠ ثواني'
                      : 'Book Your Table or Room in 10s',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isArabic
                      ? 'بدون انتظار على واتساب • أسعار واضحة وتأكيد فوري'
                      : 'No WhatsApp waiting • Instant slot confirmation',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.65),
                    fontSize: 12.0,
                  ),
                ),
                const SizedBox(height: 14),

                // Short URL pill
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    bookingUrl,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontSize: 12.0,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
