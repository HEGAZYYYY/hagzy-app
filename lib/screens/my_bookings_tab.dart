import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';

class MyBookingsTab extends StatefulWidget {
  const MyBookingsTab({
    super.key,
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onChoosePayment,
    required this.api,
    required this.apiConfigured,
    this.onCancelBooking,
    this.onBookAgain,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final bool arabic;
  final Future<void> Function(Booking booking) onChoosePayment;
  final HagzyApi api;
  final bool apiConfigured;
  final ValueChanged<Booking>? onCancelBooking;
  final ValueChanged<String>? onBookAgain;

  @override
  State<MyBookingsTab> createState() => _MyBookingsTabState();
}

class _MyBookingsTabState extends State<MyBookingsTab> {
  bool _lookingUp = false;
  String? _lookupError;

  Future<void> _lookupByPhone() async {
    var phone = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            localized(widget.arabic, 'Find my bookings', 'ابحث عن حجوزاتي')),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText:
                localized(widget.arabic, 'Phone number', 'رقم الهاتف'),
            hintText: '+20 10 1234 5678',
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
          onChanged: (value) => phone = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(localized(widget.arabic, 'Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(localized(widget.arabic, 'Search', 'بحث')),
          ),
        ],
      ),
    );
    if (confirmed != true || phone.trim().isEmpty) return;
    setState(() {
      _lookingUp = true;
      _lookupError = null;
    });
    try {
      await widget.api.requestCustomerOtp(phone);
      if (!mounted) return;
      var otpCode = '';
      final otpConfirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(localized(
              widget.arabic, 'Verify phone (OTP)', 'رمز التحقق (OTP)')),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: localized(
                  widget.arabic, '6-digit verification code', 'رمز التحقق من ٦ أرقام'),
              hintText: '123456',
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            onChanged: (value) => otpCode = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(localized(widget.arabic, 'Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(localized(widget.arabic, 'Verify', 'تحقق')),
            ),
          ],
        ),
      );
      if (otpConfirmed != true || otpCode.trim().isEmpty) return;
      final verified = await widget.api.verifyCustomerOtp(phone, otpCode);
      final customerToken = verified['token'] as String?;
      final results = await widget.api.bookingsByPhone(
        phone,
        customerToken: customerToken,
      );
      final found = results
          .map((item) => Booking.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      if (found.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(localized(
                widget.arabic, 'No bookings found', 'لم يتم العثور على حجوزات')),
            content: Text(localized(
                widget.arabic,
                'No active bookings were found for this phone number.',
                'لا توجد حجوزات نشطة لهذا الرقم.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(localized(widget.arabic, 'OK', 'حسناً')),
              ),
            ],
          ),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(localized(
                widget.arabic, 'Bookings found', 'تم العثور على حجوزات')),
            content: SizedBox(
              width: 400,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: found.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx2, index) {
                  final b = found[index];
                  final venue = widget.venues
                      .where((v) => v.id == b.venueId)
                      .firstOrNull;
                  final statusLabel = b.isConfirmed
                      ? localized(widget.arabic, 'Confirmed', 'مؤكد')
                      : b.isPendingPayment
                          ? localized(widget.arabic, 'Pending', 'معلق')
                          : localized(widget.arabic, 'Expired', 'منتهي');
                  return ListTile(
                    title: Text(b.customer),
                    subtitle: Text(
                      '${venue?.name ?? b.venueId} · ${formatDateTime(b.startsAt)} · $statusLabel',
                    ),
                    trailing: Text(
                      '${formatMoney(b.price)} EGP',
                      style: const TextStyle(
                          color: kGreen, fontWeight: FontWeight.w700),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(localized(widget.arabic, 'Close', 'إغلاق')),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _lookupError = error.toString());
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    final active = widget.bookings
        .where((booking) =>
            !booking.cancelled &&
            booking.status != 'expired' &&
            (booking.status != 'pending_payment' ||
                booking.holdExpiresAt == null ||
                booking.holdExpiresAt!.isAfter(DateTime.now())))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    if (active.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          IntroCard(
            title: localized(arabic, 'Your Bookings', 'حجوزاتك'),
            subtitle: localized(
                arabic,
                'Reservations you make will appear here.',
                'ستظهر حجوزاتك هنا.'),
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 16),
          EmptyCard(
            icon: Icons.event_available_outlined,
            title:
                localized(arabic, 'Nothing Booked Yet', 'لا توجد حجوزات بعد'),
            body: localized(
                arabic,
                'Explore a venue and choose a time to get started.',
                'استكشف الأماكن واختر وقتاً للبدء.'),
          ),
          if (widget.apiConfigured) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _lookingUp ? null : _lookupByPhone,
                icon: _lookingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.phone_outlined),
                label: Text(localized(arabic, 'Find my bookings by phone',
                    'ابحث عن حجوزاتي برقم الهاتف')),
              ),
            ),
            if (_lookupError != null) ...[
              const SizedBox(height: 8),
              Text(
                _lookupError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ],
          ],
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        IntroCard(
          title: localized(arabic, 'Your Bookings', 'حجوزاتك'),
          subtitle: localized(arabic, 'Keep track of upcoming reservations.',
              'تابع حجوزاتك القادمة.'),
          icon: Icons.calendar_month_outlined,
        ),
        const SizedBox(height: 12),
        ...active.map((booking) {
          final venue = widget.venues
              .where((item) => item.id == booking.venueId)
              .firstOrNull;
          final space = venue?.items
              .where((item) => item.id == booking.itemId)
              .firstOrNull;
          final status = booking.isConfirmed
              ? localized(arabic, 'Confirmed', 'مؤكد')
              : booking.isPendingPayment
                  ? localized(arabic, 'Awaiting Deposit', 'بانتظار العربون')
                  : localized(arabic, 'Hold Expired', 'انتهى الحجز المؤقت');
          final statusColor = booking.isConfirmed
              ? kGreen
              : booking.isPendingPayment
                  ? const Color(0xFFB45309)
                  : kMuted;
          final remainingMin = booking.holdExpiresAt
              ?.difference(DateTime.now())
              .inMinutes
              .clamp(1, 120);
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: HagzyTheme.softShadow,
            ),
            child: Card(
              margin: EdgeInsets.zero,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: booking.isConfirmed
                      ? kGreen.withValues(alpha: 0.35)
                      : kBorder,
                  width: booking.isConfirmed ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
                    decoration: BoxDecoration(
                      gradient: booking.isConfirmed
                          ? HagzyTheme.obsidianGradient
                          : const LinearGradient(
                              colors: [Color(0xFF0A0F1D), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            gradient: booking.isConfirmed
                                ? HagzyTheme.brandGradient
                                : LinearGradient(
                                    colors: [
                                      Colors.white.withValues(alpha: 0.14),
                                      Colors.white.withValues(alpha: 0.06),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: Icon(
                            venue?.type.icon ?? Icons.event_available_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                venue?.name ??
                                    localized(arabic, 'Hagzy Reservation',
                                        'حجز حجزي'),
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [
                                  if (space != null) space.name,
                                  if (venue?.location.isNotEmpty ?? false)
                                    venue!.location,
                                ].join(' · '),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: booking.isConfirmed
                                ? kGreen.withValues(alpha: 0.25)
                                : const Color(0xFFF59E0B)
                                    .withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: booking.isConfirmed
                                  ? kGreenLight.withValues(alpha: 0.45)
                                  : const Color(0xFFFBBF24)
                                      .withValues(alpha: 0.45),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              LivePulseDot(
                                color: booking.isConfirmed
                                    ? kGreenLight
                                    : const Color(0xFFFBBF24),
                                size: 6,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                status.toUpperCase(),
                                style: TextStyle(
                                  color: booking.isConfirmed
                                      ? kGreenLight
                                      : const Color(0xFFFDE68A),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _TicketPerforatedDivider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: kPage,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kBorder),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule_rounded,
                                  color: kGreen, size: 18),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  '${formatDateTime(booking.startsAt)} · ${booking.durationMinutes} ${localized(arabic, 'min', 'دقيقة')}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: kInk,
                                  ),
                                ),
                              ),
                              Text(
                                '${formatMoney(booking.price)} ${localized(arabic, 'EGP', 'جنيه')}',
                                style: const TextStyle(
                                  color: kGreen,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (booking.paymentReference.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 9),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFBFDBFE)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified_user_outlined,
                                    size: 16, color: Color(0xFF1D4ED8)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    localized(
                                      arabic,
                                      'Payment proof submitted (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · Awaiting venue verification',
                                      'تم إرسال إثبات الدفع (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · بانتظار مراجعة المكان',
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF1E40AF),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (!booking.isConfirmed) ...[
                          const SizedBox(height: 10),
                          Text(
                            booking.isPendingPayment
                                ? localized(
                                    arabic,
                                    'This time is held temporarily${remainingMin != null ? ' ($remainingMin min left)' : ''}. It is not confirmed until the deposit is paid and verified.',
                                    'هذا الوقت محجوز مؤقتاً. لن يتأكد الحجز حتى يتم دفع العربون والتحقق منه.')
                                : localized(
                                    arabic,
                                    'The payment window ended. Choose another available time to reserve.',
                                    'انتهت مهلة الدفع. اختر وقتاً آخر متاحاً للحجز.'),
                            style: const TextStyle(
                              color: kMuted,
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        if (booking.serviceNames.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            booking.serviceNames.join(' · '),
                            style: const TextStyle(
                              color: kMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        if (booking.promoCode.isNotEmpty &&
                            booking.discountAmount > 0) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: kSurfaceTint,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kGreen.withValues(alpha: 0.25)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.local_offer_rounded,
                                    size: 13, color: kGreen),
                                const SizedBox(width: 6),
                                Text(
                                  localized(
                                    arabic,
                                    'Promo ${booking.promoCode} applied (-${formatMoney(booking.discountAmount)} EGP)',
                                    'تم تطبيق كود ${booking.promoCode} (-${formatMoney(booking.discountAmount)} ج)',
                                  ),
                                  style: const TextStyle(
                                    color: kGreen,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: booking.isPendingPayment
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: PressableScale(
                                        scaleDown: 0.97,
                                        onTap: () =>
                                            widget.onChoosePayment(booking),
                                        child: FilledButton.icon(
                                          onPressed: () =>
                                              widget.onChoosePayment(booking),
                                          icon: const Icon(Icons
                                              .account_balance_wallet_outlined),
                                          label: Text(localized(
                                              arabic,
                                              'Pay Deposit · ${formatMoney(booking.dueNow ?? booking.price)} EGP',
                                              'ادفع العربون · ${formatMoney(booking.dueNow ?? booking.price)} جنيه')),
                                        ),
                                      ),
                                    ),
                                    if (widget.onCancelBooking != null) ...[
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: localized(
                                            arabic,
                                            'Cancel Reservation Hold',
                                            'إلغاء الحجز'),
                                        onPressed: () =>
                                            widget.onCancelBooking!(booking),
                                        icon: const Icon(Icons.delete_outline,
                                            color: kMuted),
                                      ),
                                    ],
                                  ],
                                )
                              : Row(
                                  children: [
                                    Icon(Icons.verified_rounded,
                                        size: 16, color: statusColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showQrPassModal(booking, venue, space),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.qr_code_2_rounded,
                                  size: 17, color: kGreen),
                              label: Text(
                                localized(arabic, 'QR Check-In Pass',
                                    'بطاقة الدخول QR'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _openMaps(venue),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.directions_outlined,
                                  size: 16, color: kGreen),
                              label: Text(
                                localized(arabic, 'Directions', 'الاتجاهات'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showAddToCalendarModal(booking, venue, space),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.event_available_outlined,
                                  size: 16, color: kGreen),
                              label: Text(
                                localized(
                                    arabic, 'Add to Calendar', 'أضف للتقويم'),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            if (widget.onBookAgain != null && venue != null)
                              OutlinedButton.icon(
                                onPressed: () => widget.onBookAgain!(venue.id),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                icon: const Icon(Icons.replay_rounded,
                                    size: 16, color: kGreen),
                                label: Text(
                                  localized(arabic, 'Book Again',
                                      'احجز مرة أخرى'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Future<void> _showQrPassModal(
      Booking booking, Venue? venue, VenueItem? space) async {
    final arabic = widget.arabic;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const HagzyLogoMark(size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localized(
                                arabic, 'HAGZY CHECK-IN PASS', 'بطاقة دخول حجزي'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: kGreen,
                              letterSpacing: 0.8,
                            ),
                          ),
                          Text(
                            venue?.name ?? booking.venueId,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: kInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: kBorder, width: 1.5),
                    boxShadow: HagzyTheme.softShadow,
                  ),
                  child: CustomPaint(
                    size: const Size(168, 168),
                    painter: _QrPassMatrixPainter(seedText: booking.id),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '${space?.name ?? booking.itemId} · ${formatDateTime(booking.startsAt)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'REF: ${booking.id}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: kMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: booking.isConfirmed
                        ? kSurfaceTint
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    booking.isConfirmed
                        ? localized(arabic, 'CONFIRMED PASS', 'حجز مؤكد')
                        : localized(
                            arabic, 'HOLD · AWAITING DEPOSIT', 'حجز مؤقت'),
                    style: TextStyle(
                      color: booking.isConfirmed
                          ? kGreen
                          : const Color(0xFFB45309),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _openMaps(venue);
                        },
                        icon: const Icon(Icons.directions_outlined,
                            size: 15, color: kGreen),
                        label: Text(
                          localized(arabic, 'Directions', 'الاتجاهات'),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showAddToCalendarModal(booking, venue, space);
                        },
                        icon: const Icon(Icons.event_available_outlined,
                            size: 15, color: kGreen),
                        label: Text(
                          localized(arabic, 'Calendar', 'التقويم'),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMaps(Venue? venue) async {
    if (venue == null) return;
    final rawUrl = venue.googleMapsUrl.trim();
    final uri = rawUrl.isNotEmpty
        ? Uri.parse(rawUrl)
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': '${venue.name} ${venue.location} Egypt'.trim(),
          });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _showAddToCalendarModal(
      Booking booking, Venue? venue, VenueItem? space) async {
    final arabic = widget.arabic;
    final title = '${venue?.name ?? 'Booking'} · Hagzy';
    final location = '${venue?.name ?? ''}, ${venue?.location ?? ''}'.trim();
    final desc =
        'Hagzy Reservation\nVenue: ${venue?.name ?? ''}\nSpace: ${space?.name ?? ''}\nDuration: ${booking.durationMinutes} min\nPrice: ${formatMoney(booking.price)} EGP\nBooking ID: ${booking.id}';

    final startUtc = booking.startsAt.toUtc();
    final endUtc =
        booking.startsAt.add(Duration(minutes: booking.durationMinutes)).toUtc();
    String pad(int n) => n.toString().padLeft(2, '0');
    final startStr =
        '${startUtc.year}${pad(startUtc.month)}${pad(startUtc.day)}T${pad(startUtc.hour)}${pad(startUtc.minute)}${pad(startUtc.second)}Z';
    final endStr =
        '${endUtc.year}${pad(endUtc.month)}${pad(endUtc.day)}T${pad(endUtc.hour)}${pad(endUtc.minute)}${pad(endUtc.second)}Z';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: kBorder,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      gradient: HagzyTheme.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.event_available_rounded,
                        color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localized(arabic, 'Add to Calendar', 'أضف للتقويم'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${formatDateTime(booking.startsAt)} · ${booking.durationMinutes} min',
                          style: const TextStyle(
                            color: kMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: kPage,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storefront_rounded,
                            size: 16, color: kGreen),
                        const SizedBox(width: 8),
                        Text(
                          venue?.name ?? 'Hagzy Reservation',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: kMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            location.isEmpty ? 'Egypt' : location,
                            style: const TextStyle(
                                color: kMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final gCalUrl = Uri.parse(
                    'https://calendar.google.com/calendar/render?action=TEMPLATE'
                    '&text=${Uri.encodeComponent(title)}'
                    '&dates=$startStr/$endStr'
                    '&details=${Uri.encodeComponent(desc)}'
                    '&location=${Uri.encodeComponent(location)}',
                  );
                  await launchUrl(gCalUrl,
                      mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 19),
                label: Text(
                  localized(arabic, 'Google Calendar',
                      'تقويم جوجل (Google Calendar)'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  Navigator.pop(ctx);
                  final nowUtc = DateTime.now().toUtc();
                  final nowStr =
                      '${nowUtc.year}${pad(nowUtc.month)}${pad(nowUtc.day)}T${pad(nowUtc.hour)}${pad(nowUtc.minute)}${pad(nowUtc.second)}Z';
                  final icsContent =
                      'BEGIN:VCALENDAR\r\n'
                      'VERSION:2.0\r\n'
                      'PRODID:-//Hagzy//Reservation//EN\r\n'
                      'CALSCALE:GREGORIAN\r\n'
                      'METHOD:PUBLISH\r\n'
                      'BEGIN:VEVENT\r\n'
                      'UID:${booking.id}-$nowStr@hagzy.com\r\n'
                      'DTSTAMP:$nowStr\r\n'
                      'DTSTART:$startStr\r\n'
                      'DTEND:$endStr\r\n'
                      'SUMMARY:$title\r\n'
                      'DESCRIPTION:$desc\r\n'
                      'LOCATION:$location\r\n'
                      'STATUS:CONFIRMED\r\n'
                      'BEGIN:VALARM\r\n'
                      'TRIGGER:-PT1H\r\n'
                      'ACTION:DISPLAY\r\n'
                      'DESCRIPTION:Reminder: $title\r\n'
                      'END:VALARM\r\n'
                      'END:VEVENT\r\n'
                      'END:VCALENDAR\r\n';
                  final dataUri = Uri.dataFromString(
                    icsContent,
                    mimeType: 'text/calendar',
                    encoding: utf8,
                  );
                  await launchUrl(dataUri,
                      mode: LaunchMode.externalApplication);
                },
                icon:
                    const Icon(Icons.download_rounded, size: 19, color: kGreen),
                label: Text(
                  localized(arabic, 'Apple Calendar / iCal (.ics)',
                      'تقويم آبل / تحميل ملف (.ics)'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: kInk),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrPassMatrixPainter extends CustomPainter {
  _QrPassMatrixPainter({required this.seedText});

  final String seedText;

  @override
  void paint(Canvas canvas, Size size) {
    const grid = 21;
    final cell = size.width / grid;
    final darkPaint = Paint()
      ..color = kInk
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = kGreen
      ..style = PaintingStyle.fill;

    bool isFinderPattern(int r, int c) {
      final topLeft = r < 7 && c < 7;
      final topRight = r < 7 && c >= grid - 7;
      final bottomLeft = r >= grid - 7 && c < 7;
      return topLeft || topRight || bottomLeft;
    }

    void drawFinder(int startR, int startC) {
      final outer = RRect.fromRectAndRadius(
        Rect.fromLTWH(startC * cell, startR * cell, 7 * cell, 7 * cell),
        Radius.circular(cell * 1.4),
      );
      final innerWhite = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            (startC + 1) * cell, (startR + 1) * cell, 5 * cell, 5 * cell),
        Radius.circular(cell * 0.9),
      );
      final centerDot = RRect.fromRectAndRadius(
        Rect.fromLTWH(
            (startC + 2) * cell, (startR + 2) * cell, 3 * cell, 3 * cell),
        Radius.circular(cell * 0.7),
      );
      canvas.drawRRect(outer, darkPaint);
      canvas.drawRRect(
          innerWhite,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill);
      canvas.drawRRect(centerDot, accentPaint);
    }

    drawFinder(0, 0);
    drawFinder(0, grid - 7);
    drawFinder(grid - 7, 0);

    var hash = 2166136261;
    for (final unit in seedText.codeUnits) {
      hash ^= unit;
      hash = (hash * 16777619) & 0x7fffffff;
    }

    for (var r = 0; r < grid; r++) {
      for (var c = 0; c < grid; c++) {
        if (isFinderPattern(r, c)) continue;
        final bit = ((hash ^ (r * 31 + c * 17)) + (r * c)) % 3 == 0;
        if (bit) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                c * cell + cell * 0.08,
                r * cell + cell * 0.08,
                cell * 0.84,
                cell * 0.84,
              ),
              Radius.circular(cell * 0.25),
            ),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrPassMatrixPainter oldDelegate) =>
      oldDelegate.seedText != seedText;
}

class _TicketPerforatedDivider extends StatelessWidget {
  const _TicketPerforatedDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            children: List.generate(
              28,
              (index) => Expanded(
                child: Container(
                  height: 1.5,
                  color: index.isEven ? kBorder : Colors.transparent,
                ),
              ),
            ),
          ),
          Positioned(
            left: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: kPage,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
            ),
          ),
          Positioned(
            right: -10,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: kPage,
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
