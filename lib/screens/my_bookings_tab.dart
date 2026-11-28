import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import 'unified_payment_screen.dart';
import '../core/models/models_v2.dart';
import '../features/checkout_psychology/checkout_psychology.dart';
import '../features/passport_wallet/passport_wallet.dart';

class MyBookingsTab extends StatefulWidget {
  const MyBookingsTab({
    super.key,
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onChoosePayment,
    required this.api,
    required this.apiConfigured,
    this.walletBalance = HagzyWallet.defaultWelcomeBalance,
    this.isSignedIn = false,
    this.onSignIn,
    this.onWalletUpdated,
    this.onGoToSignIn,
    this.onCancelBooking,
    this.onBookAgain,
    this.onExplore,
    this.onRefresh,
    this.onScreenOpened,
    this.onUpdateReminder,
  });

  /// Pull-to-refresh handler (re-syncs bookings from the server).
  final Future<void> Function()? onRefresh;
  final Future<void> Function()? onScreenOpened;
  final Future<void> Function(Booking booking, int offsetMinutes)?
      onUpdateReminder;
  final List<Venue> venues;
  final List<Booking> bookings;
  final double walletBalance;
  final ValueChanged<double>? onWalletUpdated;
  final bool arabic;
  final bool isSignedIn;
  final Future<void> Function({
    required String name,
    required String email,
    required String phone,
    String? token,
    double? walletBalance,
  })? onSignIn;
  final VoidCallback? onGoToSignIn;
  final Future<void> Function(Booking booking) onChoosePayment;
  final HagzyApi api;
  final bool apiConfigured;
  final ValueChanged<Booking>? onCancelBooking;
  final ValueChanged<String>? onBookAgain;

  /// Takes the customer to the Explore tab from the empty state.
  final VoidCallback? onExplore;

  @override
  State<MyBookingsTab> createState() => _MyBookingsTabState();
}

class _MyBookingsTabState extends State<MyBookingsTab> {
  bool _lookingUp = false;
  String? _lookupError;
  Timer? _liveRefreshTimer;

  @override
  void initState() {
    super.initState();
    final onScreenOpened = widget.onScreenOpened;
    if (onScreenOpened != null) unawaited(onScreenOpened());
    _startLiveRefreshTimer();
  }

  void _startLiveRefreshTimer() {
    _liveRefreshTimer?.cancel();
    _liveRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final hasPending = widget.bookings.any((b) =>
          !b.cancelled &&
          !b.isConfirmed &&
          b.status == 'pending_payment');
      if (hasPending) {
        widget.onRefresh?.call();
      }
    });
  }

  @override
  void dispose() {
    _liveRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _topUpWalletDialog(double currentBalance) async {
    final arabic = widget.arabic;
    TopUpWalletSheet.show(
      context: context,
      currentBalance: currentBalance,
      isArabic: arabic,
      onProceedToPayment: (amount) async {
        await Navigator.push<bool>(
          context,
          hagzyPageRoute(
            builder: (ctx) => UnifiedPaymentScreen(
              bookingId:
                  'wallet_topup_${DateTime.now().millisecondsSinceEpoch}',
              amount: amount,
              arabic: arabic,
              isWalletTopUp: true,
              venueName: localized(arabic, 'Hagzy In-App Wallet', 'محفظة حجزي'),
              slotTimeFormatted: localized(
                  arabic, 'Instant Wallet Credit', 'شحن فوري للرصيد'),
              headcount: 1,
              initialMethod: 'instapay',
              receiverIpa: 'hagzy@instapay',
              receiverWallet: '01041570557',
              onPaymentVerified: () async {
                final newBal = await HagzyWallet.addFunds(amount);
                widget.onWalletUpdated?.call(newBal);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: kGreen,
                      content: Text(localized(
                        arabic,
                        'Wallet successfully credited with ${amount.toStringAsFixed(0)} EGP! Current Balance: ${newBal.toStringAsFixed(0)} EGP',
                        'تم شحن المحفظة بنجاح بمبلغ ${amount.toStringAsFixed(0)} ج.م! الرصيد الحالي: ${newBal.toStringAsFixed(0)} ج.م',
                      )),
                    ),
                  );
                }
              },
              onManualProofSubmitted: (proofMethod, ref) async {
                final newBal = await HagzyWallet.addFunds(amount);
                widget.onWalletUpdated?.call(newBal);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: kGreen,
                      content: Text(localized(
                        arabic,
                        'Top-up reference recorded. ${amount.toStringAsFixed(0)} EGP added to your wallet!',
                        'تم تسجيل كود التحويل وإضافة ${amount.toStringAsFixed(0)} ج.م لمحفظتك بنجاح!',
                      )),
                    ),
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildWalletCard(bool arabic) {
    final balance = widget.walletBalance;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: kBorder,
          width: 1.0,
        ),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kSurfaceTint,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: kBrandAccent,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localized(arabic, 'Hagzy Wallet', 'محفظة حجزي'),
                    style: TextStyle(
                      color: kMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  HagzyAnimatedValue(
                    valueKey: balance.toStringAsFixed(0),
                    child: Text(
                      '${formatMoney(balance)} ${localized(arabic, 'EGP available', 'جنيه متاح')}',
                      style: hagzyMonoStyle(
                        color: kInk,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        arabic: arabic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                HagzyHaptics.light();
                _topUpWalletDialog(balance);
              },
              style: FilledButton.styleFrom(
                backgroundColor: kAccentSurface,
                foregroundColor: kAccentOnSurface,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 17, color: Colors.white),
              label: Text(
                localized(arabic, 'Top Up', 'شحن'),
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookupByPhone() async {
    var phone = '';
    final confirmed = await showHagzyAdaptiveModal<bool>(
      context: context,
      builder: (ctx, isSheet) => HagzyModalCard(
        isSheet: isSheet,
        icon: Icons.phone_outlined,
        title: localized(widget.arabic, 'Find my bookings', 'ابحث عن حجوزاتي'),
        subtitle: localized(
          widget.arabic,
          'Enter the mobile number you booked with to sync your passes.',
          'أدخل رقم الهاتف المستخدم في الحجز لمزامنة حجوزاتك.',
        ),
        onClose: () => Navigator.pop(ctx, false),
        primaryUseFilledButton: true,
        primaryLabel: localized(widget.arabic, 'Search', 'بحث'),
        onPrimary: () => Navigator.pop(ctx, true),
        secondaryLabel: localized(widget.arabic, 'Cancel', 'إلغاء'),
        onSecondary: () => Navigator.pop(ctx, false),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => Navigator.pop(ctx, true),
          decoration: InputDecoration(
            labelText:
                localized(widget.arabic, 'Phone number', 'رقم الهاتف'),
            hintText: '+20 10 1234 5678',
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
          onChanged: (value) => phone = value,
        ),
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
      final otpConfirmed = await showHagzyAdaptiveModal<bool>(
        context: context,
        builder: (ctx, isSheet) => HagzyModalCard(
          isSheet: isSheet,
          icon: Icons.lock_outline_rounded,
          title: localized(
              widget.arabic, 'Verify phone (OTP)', 'رمز التحقق (OTP)'),
          subtitle: localized(
            widget.arabic,
            'Enter the 6-digit code sent to $phone.',
            'أدخل رمز التحقق المرسل إلى $phone.',
          ),
          onClose: () => Navigator.pop(ctx, false),
          primaryUseFilledButton: true,
          primaryLabel: localized(widget.arabic, 'Verify', 'تحقق'),
          onPrimary: () => Navigator.pop(ctx, true),
          secondaryLabel: localized(widget.arabic, 'Cancel', 'إلغاء'),
          onSecondary: () => Navigator.pop(ctx, false),
          content: TextField(
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(ctx, true),
            decoration: InputDecoration(
              labelText: localized(
                  widget.arabic, '6-digit verification code', 'رمز التحقق من ٦ أرقام'),
              hintText: '123456',
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            onChanged: (value) => otpCode = value,
          ),
        ),
      );
      if (otpConfirmed != true || otpCode.trim().isEmpty) return;
      final verified = await widget.api.verifyCustomerOtp(phone, otpCode);
      final customerToken = verified['token'] as String?;
      final cust = verified['customer'] as Map<String, dynamic>?;
      final custName = cust?['name'] as String? ?? '';
      final custEmail = cust?['email'] as String? ?? '';
      final custBalance = (cust?['walletBalance'] as num?)?.toDouble();

      if (widget.onSignIn != null) {
        await widget.onSignIn!(
          name: custName,
          email: custEmail,
          phone: phone,
          token: customerToken,
          walletBalance: custBalance,
        );
      }
      final results = await widget.api.bookingsByPhone(
        phone,
        customerToken: customerToken,
      );
      final found = results
          .map((item) => Booking.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      if (found.isEmpty) {
        await showHagzyAdaptiveModal<void>(
          context: context,
          builder: (ctx, isSheet) => HagzyModalCard(
            isSheet: isSheet,
            centerHeader: true,
            icon: Icons.event_busy_outlined,
            title: localized(
                widget.arabic, 'No bookings found', 'لم يتم العثور على حجوزات'),
            subtitle: localized(
                widget.arabic,
                'No active bookings were found for this phone number.',
                'لا توجد حجوزات نشطة لهذا الرقم.'),
            onClose: () => Navigator.pop(ctx),
            primaryLabel: localized(widget.arabic, 'OK', 'حسناً'),
            onPrimary: () => Navigator.pop(ctx),
          ),
        );
      } else {
        await showHagzyAdaptiveModal<void>(
          context: context,
          maxWidth: 460,
          builder: (ctx, isSheet) => HagzyModalCard(
            isSheet: isSheet,
            scrollable: false,
            icon: Icons.event_available_rounded,
            title: localized(
                widget.arabic, 'Bookings found', 'تم العثور على حجوزات'),
            onClose: () => Navigator.pop(ctx),
            primaryLabel: localized(widget.arabic, 'Close', 'إغلاق'),
            onPrimary: () => Navigator.pop(ctx),
            content: SizedBox(
              height: 300,
              child: ListView.separated(
                itemCount: found.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
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
                  return HagzyGroupedRow(
                    icon: venue?.type.icon ?? Icons.calendar_today_rounded,
                    title: b.customer,
                    subtitle:
                        '${venue != null ? displayLocalizedTitle(venue.name, widget.arabic) : b.venueId} · ${formatDateTime(b.startsAt)} · $statusLabel',
                    trailing: Text(
                      '${formatMoney(b.price)} EGP',
                      style: TextStyle(
                        color: kSuccess,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _lookupError = friendlyError(error, arabic: widget.arabic));
    } finally {
      if (mounted) setState(() => _lookingUp = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildBookings(context);
  }

  Widget _buildBookings(BuildContext context) {
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
    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    if (active.isEmpty) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh ?? () async {},
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 880 : double.infinity,
            ),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isWide ? 24 : 16,
                isWide ? 16 : 12,
                isWide ? 24 : 16,
                isWide ? 48 : 104,
              ),
              children: [
          IntroCard(
            title: localized(arabic, 'Your Bookings', 'حجوزاتك'),
            subtitle: localized(
                arabic,
                'Reservations you make will appear here.',
                'ستظهر حجوزاتك هنا.'),
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 14),
          _buildWalletCard(arabic),
          if (!widget.isSignedIn) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: kSurfaceTint,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kBrandAccent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.account_circle_outlined,
                        color: kBrandAccent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          localized(arabic, 'Sign in to see all your bookings', 'سجل دخولك لعرض جميع حجوزاتك'),
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: kInk),
                        ),
                        Text(
                          localized(arabic, 'Sync wallet balance & active reservations', 'مزامنة رصيد المحفظة والحجوزات'),
                          style: TextStyle(fontSize: 12.0, color: kMuted),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onGoToSignIn != null)
                    FilledButton(
                      onPressed: widget.onGoToSignIn,
                      style: FilledButton.styleFrom(
                        backgroundColor: kAccentSurface,
                        foregroundColor: kAccentOnSurface,
                        minimumSize: const Size(44, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium)),
                      ),
                      child: Text(localized(arabic, 'Sign In', 'دخول'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 2),
          EmptyCard(
            icon: Icons.event_available_outlined,
            title:
                localized(arabic, 'Nothing Booked Yet', 'لا توجد حجوزات بعد'),
            body: localized(
                arabic,
                'Explore a venue and choose a time to get started.',
                'استكشف الأماكن واختر وقتاً للبدء.'),
            action: widget.onExplore,
            actionLabel: widget.onExplore == null
                ? null
                : localized(arabic, 'Explore venues', 'استكشف الأماكن'),
            actionIcon: Icons.explore_outlined,
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
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: widget.onRefresh ?? () async {},
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isWide ? 880 : double.infinity,
          ),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              isWide ? 24 : 16,
              isWide ? 16 : 10,
              isWide ? 24 : 16,
              isWide ? 48 : 104,
            ),
            children: [
        if (isWide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: IntroCard(
                  title: localized(arabic, 'Your Bookings', 'حجوزاتك'),
                  subtitle: localized(arabic, 'Keep track of upcoming reservations.',
                      'تابع حجوزاتك القادمة.'),
                  icon: Icons.calendar_month_outlined,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: _buildWalletCard(arabic)),
            ],
          )
        else ...[
          IntroCard(
            title: localized(arabic, 'Your Bookings', 'حجوزاتك'),
            subtitle: localized(arabic, 'Keep track of upcoming reservations.',
                'تابع حجوزاتك القادمة.'),
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 10),
          _buildWalletCard(arabic),
        ],
        const SizedBox(height: 4),
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
                  : booking.isHoldExpired
                      ? localized(arabic, 'Hold Expired', 'انتهى الحجز المؤقت')
                      : localized(arabic, 'Confirmed', 'مؤكد');
          final statusColor = booking.isConfirmed
              ? kSuccess
              : booking.isPendingPayment
                  ? kWarning
                  : booking.isHoldExpired
                      ? kMuted
                      : kSuccess;
          final remainingMin = booking.holdExpiresAt
              ?.difference(DateTime.now())
              .inMinutes
              .clamp(1, 120);

          final hagzyB = HagzyBooking(
            id: booking.id,
            unitId: booking.itemId,
            venueId: booking.venueId,
            hostUserId: booking.customer,
            startTime: booking.startsAt,
            endTime: booking.endsAt,
            headcount: booking.splitCount,
            totalPriceEgp: booking.price,
            depositRequiredEgp: booking.dueNow ?? (booking.price * 0.1),
            status: booking.isConfirmed ? BookingStatus.confirmed : BookingStatus.pendingDeposit,
            confirmedAt: booking.confirmedAt,
            createdAt: booking.createdAt ?? booking.startsAt,
          );

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              if (booking.isConfirmed && hagzyB.isGracePeriodActive()) ...[
                GracePeriodCountdownBanner(
                  booking: hagzyB,
                  isArabic: arabic,
                  onCancelUnderGrace: () {
                    widget.onCancelBooking?.call(booking);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: kSnackBarBg,
                        content: Text(
                          localized(
                            arabic,
                            'Booking cancelled within grace period. 100% deposit refunded to your Hagzy Wallet!',
                            'تم إلغاء الحجز ضمن فترة السماح. تم استرداد العربون ١٠٠٪ فوراً في محفظة حجزي!',
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 6),
              ],
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
                  boxShadow: HagzyTheme.subtleShadow,
                ),
                child: Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  color: kPanel,
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(HagzyTokens.radiusLarge),
                    side: BorderSide(
                      color: booking.isConfirmed
                          ? kAccentSurface
                          : kBorder,
                      width: booking.isConfirmed ? 1.5 : 1.1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                        color: kObsidian,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: booking.isConfirmed
                                    ? kVermilion
                                    : const Color(0xFF26231F),
                                borderRadius:
                                    BorderRadius.circular(HagzyTokens.radiusSmall),
                                border: Border.all(
                                  color: booking.isConfirmed
                                      ? kVermilion
                                      : const Color(0xFF3D3831),
                                ),
                              ),
                              child: Icon(
                                venue?.type.icon ??
                                    Icons.event_available_rounded,
                                color: Colors.white,
                                size: 21,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    venue != null
                                        ? displayLocalizedTitle(
                                            venue.name, arabic)
                                        : localized(arabic, 'Hagzy Reservation',
                                            'حجز حجزي'),
                                    style: hagzyDisplayStyle(
                                      arabic: arabic,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      letterSpacing: -0.35,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    [
                                      if (space != null)
                                        displayLocalizedTitle(
                                            space.name, arabic),
                                      if (venue?.location.isNotEmpty ?? false)
                                        displayLocalizedLocation(
                                            venue!.location, arabic),
                                    ].join(' · '),
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.72),
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: booking.isConfirmed
                                    ? kVermilion
                                    : const Color(0xFF2A2111),
                                borderRadius: BorderRadius.circular(
                                    HagzyTokens.radiusXs),
                                border: Border.all(
                                  color: booking.isConfirmed
                                      ? kVermilion
                                      : const Color(0xFFFBBF24)
                                          .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LivePulseDot(
                                    color: booking.isConfirmed
                                        ? Colors.white
                                        : const Color(0xFFFBBF24),
                                    size: 6,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    status.toUpperCase(),
                                    style: hagzyMonoStyle(
                                      color: booking.isConfirmed
                                          ? Colors.white
                                          : const Color(0xFFFDE68A),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.6,
                                      arabic: arabic,
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
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: kSurfaceSubtle.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(
                                    HagzyTokens.radiusMedium),
                                border: Border.all(color: kBorder),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.schedule_rounded,
                                      color: kDarkMode.value ? kVolt : kObsidian,
                                      size: 17),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      '${formatDateTime(booking.startsAt)} · ${booking.durationMinutes} ${localized(arabic, 'min', 'دقيقة')}',
                                      style: hagzyMonoStyle(
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.w800,
                                        color: kInk,
                                        arabic: arabic,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${formatMoney(booking.price)} ${localized(arabic, 'EGP', 'جنيه')}',
                                    style: hagzyMonoStyle(
                                      color: kDarkMode.value ? kVolt : kObsidian,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14.5,
                                      arabic: arabic,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        if (booking.paymentReference.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final isDark = Theme.of(context).brightness ==
                                      Brightness.dark ||
                                  kDarkMode.value;
                              final accent =
                                  booking.isConfirmed ? kSuccess : kInfoBlue;
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: booking.isConfirmed
                                      ? (isDark
                                          ? const Color(0xFF13261E)
                                          : const Color(0xFFECFDF5))
                                      : (isDark
                                          ? const Color(0xFF162033)
                                          : const Color(0xFFEFF6FF)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: booking.isConfirmed
                                        ? (isDark
                                            ? kSuccess.withValues(alpha: 0.35)
                                            : const Color(0xFFA7F3D0))
                                        : (isDark
                                            ? kInfoBlue.withValues(alpha: 0.35)
                                            : const Color(0xFFBFDBFE)),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      booking.isConfirmed
                                          ? Icons.check_circle_outline_rounded
                                          : Icons.verified_user_outlined,
                                      size: 16,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        booking.isConfirmed
                                            ? localized(
                                                arabic,
                                                'Payment verified (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · Deposit received ✓',
                                                'تم التحقق من الدفع (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · تم استلام العربون ✓',
                                              )
                                            : localized(
                                                arabic,
                                                'Payment proof submitted (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · Awaiting venue verification',
                                                'تم إرسال إثبات الدفع (${booking.paymentMethod.toUpperCase()}: ${booking.paymentReference}) · بانتظار مراجعة المكان',
                                              ),
                                        style: TextStyle(
                                          color: booking.isConfirmed
                                              ? (isDark
                                                  ? kSuccess
                                                  : const Color(0xFF065F46))
                                              : (isDark
                                                  ? kInfoBlue
                                                  : const Color(0xFF1E40AF)),
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
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
                            style: TextStyle(
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
                            style: TextStyle(
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
                              color: kSuccess.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: kSuccess.withValues(alpha: 0.30)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.local_offer_rounded,
                                    size: 13, color: kSuccess),
                                const SizedBox(width: 6),
                                Text(
                                  localized(
                                    arabic,
                                    'Promo ${booking.promoCode} applied (-${formatMoney(booking.discountAmount)} EGP)',
                                    'تم تطبيق كود ${booking.promoCode} (-${formatMoney(booking.discountAmount)} ج)',
                                  ),
                                  style: TextStyle(
                                    color: kSuccess,
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (booking.staffMember.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.content_cut_rounded,
                                  size: 13, color: kBrandAccent),
                              const SizedBox(width: 5),
                              Text(
                                '${localized(arabic, "Specialist", "المصفف")}: ${booking.staffMember}',
                                style: TextStyle(
                                  color: kBrandAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: booking.isPendingPayment
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.icon(
                                        onPressed: () {
                                          HagzyHaptics.light();
                                          widget.onChoosePayment(booking);
                                        },
                                        icon: const Icon(Icons
                                            .account_balance_wallet_outlined),
                                        label: Text(localized(
                                            arabic,
                                            'Pay Deposit · ${formatMoney(booking.dueNow ?? booking.price)} EGP',
                                            'ادفع العربون · ${formatMoney(booking.dueNow ?? booking.price)} جنيه')),
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
                                        icon: Icon(Icons.delete_outline,
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
                        const SizedBox(height: 12),
                        // Primary Boarding Pass CTA when confirmed, clean secondary actions below
                        if (booking.isConfirmed) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () =>
                                  _showQrPassModal(booking, venue, space),
                              style: FilledButton.styleFrom(
                                backgroundColor: kAccentSurface,
                                foregroundColor: kAccentOnSurface,
                                minimumSize: const Size(0, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      HagzyTokens.radiusSmall),
                                ),
                              ),
                              icon: const Icon(
                                Icons.qr_code_2_rounded,
                                size: 19,
                                color: Colors.white,
                              ),
                              label: Text(
                                localized(arabic, 'QR Check-In Pass',
                                    'بطاقة الدخول QR'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!booking.isConfirmed)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _showQrPassModal(booking, venue, space),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kInk,
                                  side: BorderSide(color: kBorder),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                icon: Icon(Icons.qr_code_2_rounded,
                                    size: 16,
                                    color:
                                        kDarkMode.value ? kVolt : kObsidian),
                                label: Text(
                                  localized(arabic, 'QR Check-In Pass',
                                      'بطاقة الدخول QR'),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: () => _openMaps(venue),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kInk,
                                side: BorderSide(color: kBorder),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: Icon(Icons.directions_outlined,
                                  size: 16,
                                  color: kDarkMode.value ? kVolt : kObsidian),
                              label: Text(
                                localized(arabic, 'Directions', 'الاتجاهات'),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (widget.onBookAgain != null && venue != null)
                              OutlinedButton.icon(
                                onPressed: () => widget.onBookAgain!(venue.id),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kInk,
                                  side: BorderSide(color: kBorder),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                icon: Icon(Icons.replay_rounded,
                                    size: 16,
                                    color:
                                        kDarkMode.value ? kVolt : kObsidian),
                                label: Text(
                                  localized(arabic, 'Book Again',
                                      'احجز مرة أخرى'),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  _showReceiptModal(booking, venue, space),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kInk,
                                side: BorderSide(color: kBorder),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                              icon: Icon(Icons.receipt_long_rounded,
                                  size: 16,
                                  color: kDarkMode.value ? kVolt : kObsidian),
                              label: Text(
                                localized(arabic, 'Receipt', 'الفاتورة'),
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (widget.onUpdateReminder != null &&
                                !booking.cancelled &&
                                !booking.checkedIn &&
                                booking.startsAt.isAfter(DateTime.now()))
                              OutlinedButton.icon(
                                onPressed: () => _showReminderPicker(booking),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kInk,
                                  side: BorderSide(color: kBorder),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                                icon: Icon(
                                    Icons.notifications_active_outlined,
                                    size: 16,
                                    color:
                                        kDarkMode.value ? kVolt : kObsidian),
                                label: Text(
                                  _reminderLabel(
                                      booking.reminderOffsetMinutes, arabic),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
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
          ),
        ],
      ),
            ),
          );
    }),
      ],
    ),
        ),
      ),
  );
}

  String _reminderLabel(int mins, bool arabic) {
    if (mins <= 0) return localized(arabic, 'Reminder Off', 'التذكير متوقف');
    if (mins < 60) {
      return localized(arabic, '$mins min before', 'قبل الموعد بـ $mins د');
    }
    if (mins == 1440) {
      return localized(arabic, '24h before', 'قبل الموعد بـ ٢٤ س');
    }
    final hrs = mins ~/ 60;
    return localized(arabic, '${hrs}h before', 'قبل الموعد بـ $hrs س');
  }

  Future<void> _showReminderPicker(Booking booking) async {
    if (widget.onUpdateReminder == null) return;
    final arabic = widget.arabic;
    const options = [30, 60, 120, 360, 1440, 0];
    final picked = await showHagzyAdaptiveModal<int>(
      context: context,
      builder: (ctx, isSheet) => HagzyModalCard(
        isSheet: isSheet,
        icon: Icons.notifications_active_outlined,
        title: localized(
            arabic, 'WhatsApp Reminder Time', 'موعد التذكير عبر واتساب'),
        subtitle: localized(
          arabic,
          'Choose when we should send your WhatsApp reminder.',
          'اختر موعد إرسال التذكير قبل الحجز.',
        ),
        onClose: () => Navigator.pop(ctx),
        secondaryLabel: localized(arabic, 'Cancel', 'إلغاء'),
        onSecondary: () => Navigator.pop(ctx),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: HagzyGroupedRow(
                      icon: m == 0
                          ? Icons.notifications_off_outlined
                          : Icons.alarm_rounded,
                      title: _reminderLabel(m, arabic),
                      selected: booking.reminderOffsetMinutes == m,
                      onTap: () => Navigator.pop(ctx, m),
                    ),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null && picked != booking.reminderOffsetMinutes) {
      await widget.onUpdateReminder!(booking, picked);
    }
  }

  Future<void> _showQrPassModal(
      Booking booking, Venue? venue, VenueItem? space) async {
    final arabic = widget.arabic;
    final qrPayload = booking.qrCheckInUrl.isNotEmpty
        ? booking.qrCheckInUrl
        : 'https://hagzy.shop/partner?scanBooking=${Uri.encodeComponent(booking.id)}'
            '${booking.qrSignature.isNotEmpty ? '&sig=${Uri.encodeComponent(booking.qrSignature)}' : ''}';
    final paidAmount = booking.actualPaidAmount ??
        (booking.isConfirmed
            ? (booking.dueNow != null && booking.dueNow! > 0
                ? booking.dueNow!
                : (venue != null
                    ? booking.price * venue.depositPercent / 100
                    : booking.price * 0.25))
            : 0.0);
    final remainingDue = (booking.price - paidAmount).clamp(0.0, booking.price);

    await showHagzyDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kObsidian,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: kVolt.withValues(alpha: 0.40), width: 1.2),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 372),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Architectural Boarding Pass Header
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFF26262F)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const HagzyBrandSymbol(
                        size: 36,
                        variant: HagzyBrandVariant.volt,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localized(arabic, 'HAGZY CHECK-IN PASS',
                                  'بطاقة دخول حجزي'),
                              style: hagzyMonoStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                color: kVolt,
                                letterSpacing: 1.0,
                                arabic: arabic,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              venue?.name ?? booking.venueId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          fixedSize: const Size(44, 44),
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            size: 19, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                  child: Column(
                    children: [
                      // Optical White QR Chamber with Electric Volt Frame
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusLarge),
                          border: Border.all(
                              color: kVolt.withValues(alpha: 0.85), width: 2.0),
                          boxShadow: [
                            BoxShadow(
                              color: kVolt.withValues(alpha: 0.18),
                              blurRadius: 24,
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: qrPayload,
                          version: QrVersions.auto,
                          size: 180,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: kObsidian,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: kObsidian,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 2,
                        children: [
                          Text(
                            space?.name ?? booking.itemId,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            '·',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                          ),
                          Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              formatDateTime(booking.startsAt),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'REF: ${booking.id}',
                        style: hagzyMonoStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.56),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      HagzyMonoTag(
                        label: booking.checkedIn
                            ? localized(
                                arabic, 'CHECKED IN ✓', 'تم تسجيل الحضور ✓')
                            : (booking.isConfirmed
                                ? localized(
                                    arabic, 'CONFIRMED PASS', 'حجز مؤكد')
                                : localized(arabic, 'HOLD · AWAITING DEPOSIT',
                                    'حجز مؤقت')),
                        backgroundColor: booking.isConfirmed
                            ? kVermilion
                            : const Color(0xFF292112),
                        foregroundColor: booking.isConfirmed
                            ? Colors.white
                            : const Color(0xFFFBBF24),
                        borderColor: booking.isConfirmed
                            ? kVermilion
                            : const Color(0xFFF59E0B).withValues(alpha: 0.45),
                        dotColor: booking.isConfirmed ? Colors.white : kSignal,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1917),
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusSmall),
                          border: Border.all(color: const Color(0xFF2E2A25)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  localized(
                                      arabic, 'Deposit Paid', 'العربون المدفوع'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.65)),
                                ),
                                Text(
                                  '${formatMoney(paidAmount)} EGP',
                                  style: hagzyMonoStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: kVermilion,
                                    arabic: arabic,
                                  ),
                                ),
                              ],
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child:
                                  Divider(height: 1, color: Color(0xFF2E2A25)),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  localized(arabic, 'Due at Venue',
                                      'المتبقي عند الوصول'),
                                  style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          Colors.white.withValues(alpha: 0.65)),
                                ),
                                Text(
                                  '${formatMoney(remainingDue)} EGP',
                                  style: hagzyMonoStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                    color: Colors.white,
                                    arabic: arabic,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: kVermilion,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  HagzyTokens.radiusSmall),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _openMaps(venue);
                          },
                          icon: const Icon(Icons.directions_outlined,
                              size: 16, color: Colors.white),
                          label: Text(
                            localized(arabic, 'Directions', 'الاتجاهات'),
                            style: const TextStyle(
                              fontSize: 13.0,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (widget.onUpdateReminder != null &&
                          !booking.cancelled &&
                          !booking.checkedIn) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Color(0xFF2D2D38)),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    HagzyTokens.radiusMedium),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showReminderPicker(booking);
                            },
                            icon: Icon(Icons.notifications_active_outlined,
                                size: 15, color: kVolt),
                            label: Text(
                              '${localized(arabic, "WhatsApp Reminder:", "تذكير واتساب:")} ${_reminderLabel(booking.reminderOffsetMinutes, arabic)}',
                              style: const TextStyle(
                                  fontSize: 12.0, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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

  Future<void> _showReceiptModal(
      Booking booking, Venue? venue, VenueItem? space) async {
    final arabic = widget.arabic;
    final depositPaid = booking.isConfirmed
        ? (booking.dueNow ?? (booking.price * 0.25))
        : 0.0;
    final remainingBalance =
        (booking.price - depositPaid).clamp(0.0, booking.price);

    await showHagzyDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: kPanel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: kBorder, width: 1.0),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: kGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.receipt_long_rounded,
                            color: kGreen, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localized(
                                  arabic, 'OFFICIAL RECEIPT', 'إيصال رسمي معتمد'),
                              style: TextStyle(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w900,
                                color: kGreen,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              localized(
                                  arabic, 'Payment Breakdown', 'تفاصيل الفاتورة'),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: kInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          fixedSize: const Size(44, 44),
                          backgroundColor: kSurfaceSubtle,
                          foregroundColor: kInk,
                          shape: const CircleBorder(),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, size: 19),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kPage,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              venue?.name ?? 'Venue',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: kInk,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: booking.isConfirmed
                                    ? kGreen.withValues(alpha: 0.15)
                                    : const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                booking.isConfirmed
                                    ? localized(arabic, 'CONFIRMED', 'مؤكد')
                                    : localized(
                                        arabic, 'HELD (PENDING)', 'معلق'),
                                style: TextStyle(
                                  color: booking.isConfirmed
                                      ? kGreen
                                      : const Color(0xFFB45309),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (venue?.location.isNotEmpty == true) ...[
                          const SizedBox(height: 4),
                          Text(
                            venue!.location,
                            style: TextStyle(color: kMuted, fontSize: 12),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        _receiptRow(localized(arabic, 'Booking ID', 'رقم الحجز'),
                            booking.id),
                        _receiptRow(
                            localized(arabic, 'Customer', 'العميل'),
                            booking.customer),
                        _receiptRow(
                            localized(arabic, 'Space / Service', 'المكان / الخدمة'),
                            space?.name ??
                                (booking.serviceNames.isNotEmpty
                                    ? booking.serviceNames.join(', ')
                                    : 'Standard')),
                        _receiptRow(
                            localized(arabic, 'Date & Time', 'الموعد'),
                            formatDateTime(booking.startsAt)),
                        _receiptRow(
                            localized(arabic, 'Duration', 'المدة'),
                            '${booking.durationMinutes} ${localized(arabic, 'min', 'دقيقة')}'),
                        if (booking.paymentMethod.isNotEmpty)
                          _receiptRow(
                              localized(arabic, 'Payment Method', 'طريقة الدفع'),
                              booking.paymentMethod.toUpperCase()),
                        if (booking.paymentReference.isNotEmpty)
                          _receiptRow(
                              localized(arabic, 'Reference #', 'رقم العملية'),
                              booking.paymentReference),
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        _receiptRow(
                            localized(arabic, 'Total Price', 'إجمالي المبلغ'),
                            '${formatMoney(booking.price)} EGP',
                            isBold: true),
                        if (booking.discountAmount > 0)
                          _receiptRow(
                              localized(arabic, 'Discount (${booking.promoCode})',
                                  'الخصم (${booking.promoCode})'),
                              '-${formatMoney(booking.discountAmount)} EGP',
                              color: kGreen),
                        _receiptRow(
                            localized(arabic, 'Deposit Status', 'حالة العربون'),
                            booking.isConfirmed
                                ? '${formatMoney(depositPaid)} EGP (${localized(arabic, 'Paid', 'مدفوع')})'
                                : localized(arabic, 'Awaiting Verification',
                                    'قيد المراجعة'),
                            color: booking.isConfirmed
                                ? kGreen
                                : const Color(0xFFB45309)),
                        _receiptRow(
                            localized(arabic, 'Due Upon Check-In',
                                'المتبقي عند الحضور'),
                            '${formatMoney(remainingBalance)} EGP',
                            isBold: true,
                            color: kInk),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: Text(localized(arabic, 'Close', 'إغلاق')),
                        ),
                      ),
                      if (widget.onBookAgain != null && venue != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              widget.onBookAgain!(venue.id);
                            },
                            icon: const Icon(Icons.replay_rounded, size: 16),
                            label: Text(localized(
                                arabic, 'Book Again', 'احجز مرة أخرى')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value,
      {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isBold ? kInk : kMuted,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                color: color ?? (isBold ? kInk : kInk),
                fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
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
              32,
              (index) => Expanded(
                child: Container(
                  height: 1.5,
                  color: index.isEven ? kBorderStrong.withValues(alpha: 0.35) : Colors.transparent,
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
                border: Border.all(color: kBorderStrong, width: 1.3),
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
                border: Border.all(color: kBorderStrong, width: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
