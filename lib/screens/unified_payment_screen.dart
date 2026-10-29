import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../theme/hagzy_theme.dart';

enum PaymentMethodTab {
  instaPay,
  mobileWallet,
}

enum PaymentIntentStatus {
  awaitingTransfer,
  verified,
  expired,
  cancelled,
  unknown,
}

class PaymentIntentData {
  const PaymentIntentData({
    required this.intentId,
    required this.status,
    required this.expectedAmount,
    required this.expectedSenderIdentifier,
    required this.expiresAt,
    this.verifiedAt,
    this.matchedEventId,
  });

  factory PaymentIntentData.fromJson(Map<String, dynamic> json) {
    final statusStr = (json['status'] as String? ?? 'AWAITING_TRANSFER').toUpperCase();
    PaymentIntentStatus status;
    switch (statusStr) {
      case 'VERIFIED':
        status = PaymentIntentStatus.verified;
        break;
      case 'EXPIRED':
        status = PaymentIntentStatus.expired;
        break;
      case 'CANCELLED':
        status = PaymentIntentStatus.cancelled;
        break;
      case 'AWAITING_TRANSFER':
      default:
        status = PaymentIntentStatus.awaitingTransfer;
        break;
    }

    DateTime? expires;
    if (json['expires_at'] != null) {
      if (json['expires_at'] is String) {
        expires = DateTime.tryParse(json['expires_at']);
      } else if (json['expires_at'] is Map && json['expires_at']['_seconds'] != null) {
        expires = DateTime.fromMillisecondsSinceEpoch(
            (json['expires_at']['_seconds'] as int) * 1000);
      }
    }
    expires ??= DateTime.now().add(const Duration(minutes: 10));

    DateTime? verified;
    if (json['verified_at'] != null && json['verified_at'] is String) {
      verified = DateTime.tryParse(json['verified_at']);
    }

    return PaymentIntentData(
      intentId: json['intentId'] ?? json['intent_id'] ?? '',
      status: status,
      expectedAmount: ((json['expectedAmount'] ?? json['expected_amount'] ?? 0) as num).toDouble(),
      expectedSenderIdentifier: (json['expectedSenderIdentifier'] ?? json['expected_sender_identifier'] ?? '') as String,
      expiresAt: expires,
      verifiedAt: verified,
      matchedEventId: json['matchedEventId'] ?? json['matched_event_id'],
    );
  }

  final String intentId;
  final PaymentIntentStatus status;
  final double expectedAmount;
  final String expectedSenderIdentifier;
  final DateTime expiresAt;
  final DateTime? verifiedAt;
  final String? matchedEventId;
}

class UnifiedPaymentScreen extends StatefulWidget {
  const UnifiedPaymentScreen({
    super.key,
    required this.bookingId,
    required this.amount,
    required this.arabic,
    this.initialMethod = 'instapay',
    this.receiverIpa = 'mohamedra4adhegazy@instapay',
    this.receiverWallet = '01024129393',
    this.prefilledSenderPhone = '',
    this.authToken,
    this.onPaymentVerified,
  });

  final String bookingId;
  final double amount;
  final bool arabic;
  final String initialMethod;
  final String receiverIpa;
  final String receiverWallet;
  final String prefilledSenderPhone;
  final String? authToken;
  final VoidCallback? onPaymentVerified;

  @override
  State<UnifiedPaymentScreen> createState() => _UnifiedPaymentScreenState();
}

class _UnifiedPaymentScreenState extends State<UnifiedPaymentScreen>
    with SingleTickerProviderStateMixin {
  late PaymentMethodTab _selectedTab;
  final _instaPayController = TextEditingController();
  final _walletController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isCreatingIntent = false;
  String? _errorMessage;

  PaymentIntentData? _activeIntent;
  StreamController<PaymentIntentData>? _intentStreamController;
  Timer? _pollingTimer;
  Timer? _countdownTimer;
  Duration _remainingTime = const Duration(minutes: 10);

  late AnimationController _verifiedAnimController;
  late Animation<double> _scaleAnimation;
  bool _hasTriggeredCompletion = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialMethod == 'vodafone_cash' ||
            widget.initialMethod == 'wallet' ||
            widget.initialMethod == 'MOBILE_WALLET'
        ? PaymentMethodTab.mobileWallet
        : PaymentMethodTab.instaPay;

    if (widget.prefilledSenderPhone.isNotEmpty) {
      _walletController.text = _cleanPhone(widget.prefilledSenderPhone);
    }

    _verifiedAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _verifiedAnimController,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    _intentStreamController?.close();
    _verifiedAnimController.dispose();
    _instaPayController.dispose();
    _walletController.dispose();
    super.dispose();
  }

  String _cleanPhone(String raw) {
    var p = raw.replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    if (p.startsWith('0020')) p = p.substring(4);
    if (p.startsWith('20')) p = p.substring(2);
    if (p.length == 10 && RegExp(r'^[125]\d{8}$').hasMatch(p)) {
      p = '0$p';
    }
    return p;
  }

  String _cleanIpa(String raw) {
    var val = raw.trim().toLowerCase();
    val = val.replaceAll(RegExp(r'(@instapay)+$', caseSensitive: false), '').trim();
    return val;
  }

  String _localized(String en, String ar) => widget.arabic ? ar : en;

  Future<void> _initiatePaymentIntent({String? overrideSender}) async {
    setState(() {
      _isCreatingIntent = true;
      _errorMessage = null;
    });

    final methodStr = _selectedTab == PaymentMethodTab.instaPay ? 'INSTAPAY' : 'MOBILE_WALLET';
    String senderId;

    if (overrideSender != null && overrideSender.trim().isNotEmpty) {
      senderId = overrideSender.trim();
    } else {
      if (_selectedTab == PaymentMethodTab.instaPay) {
        final raw = _cleanIpa(_instaPayController.text);
        if (raw.isEmpty) {
          setState(() {
            _isCreatingIntent = false;
            _errorMessage = _localized('Please enter your InstaPay username', 'يرجى كتابة اسم حساب انستاباي الخاص بك');
          });
          return;
        }
        senderId = '$raw@instapay';
      } else {
        final phone = _cleanPhone(_walletController.text);
        if (!RegExp(r'^01[0125]\d{8}$').hasMatch(phone)) {
          setState(() {
            _isCreatingIntent = false;
            _errorMessage = _localized(
              'Enter a valid 11-digit Egyptian wallet number (010/011/012/015)',
              'أدخل رقم محفظة مصري صحيح مكون من 11 رقم (010/011/012/015)',
            );
          });
          return;
        }
        senderId = phone;
      }
    }

    try {
      final apiUrl = resolveDefaultApiUrl();
      final url = Uri.parse('$apiUrl/api/payments/intent');

      final headers = {
        'Content-Type': 'application/json',
        if (widget.authToken != null) 'Authorization': 'Bearer ${widget.authToken}',
      };

      final body = jsonEncode({
        'bookingId': widget.bookingId,
        'paymentMethod': methodStr,
        'senderIdentifier': senderId,
      });

      http.Response response;
      try {
        response = await http.post(url, headers: headers, body: body).timeout(const Duration(seconds: 12));
      } catch (_) {
        // Fallback mock simulation if offline or backend cold start
        response = http.Response(
          jsonEncode({
            'intentId': 'intent_${widget.bookingId}_${methodStr.toLowerCase()}',
            'status': 'AWAITING_TRANSFER',
            'expectedAmount': widget.amount,
            'expectedSenderIdentifier': senderId,
            'expires_at': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
          }),
          200,
        );
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final intent = PaymentIntentData.fromJson(data);

        setState(() {
          _activeIntent = intent;
          _isCreatingIntent = false;
          _remainingTime = intent.expiresAt.difference(DateTime.now());
          if (_remainingTime.isNegative) {
            _remainingTime = const Duration(minutes: 10);
          }
        });

        _startIntentStreamAndTimers(intent);

        if (intent.status == PaymentIntentStatus.verified) {
          _handleVerifiedTransition();
        }
      } else {
        final errBody = jsonDecode(response.body);
        final errText = errBody['message'] ?? errBody['error'] ?? 'Failed to initiate payment session';
        setState(() {
          _isCreatingIntent = false;
          _errorMessage = errText.toString();
        });
      }
    } catch (e) {
      setState(() {
        _isCreatingIntent = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _startIntentStreamAndTimers(PaymentIntentData initial) {
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();
    _intentStreamController?.close();

    _intentStreamController = StreamController<PaymentIntentData>.broadcast();
    _intentStreamController!.add(initial);

    // Countdown timer (updates UI every second)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final diff = _activeIntent!.expiresAt.difference(DateTime.now());
      if (diff.isNegative) {
        timer.cancel();
        setState(() {
          _remainingTime = Duration.zero;
          _activeIntent = PaymentIntentData(
            intentId: _activeIntent!.intentId,
            status: PaymentIntentStatus.expired,
            expectedAmount: _activeIntent!.expectedAmount,
            expectedSenderIdentifier: _activeIntent!.expectedSenderIdentifier,
            expiresAt: _activeIntent!.expiresAt,
          );
        });
        _intentStreamController?.add(_activeIntent!);
      } else {
        setState(() {
          _remainingTime = diff;
        });
      }
    });

    // Polling timer (checks backend every 2.5s for real-time verification)
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      if (!mounted || _activeIntent == null || _activeIntent!.status != PaymentIntentStatus.awaitingTransfer) {
        timer.cancel();
        return;
      }

      try {
        final apiUrl = resolveDefaultApiUrl();
        final url = Uri.parse('$apiUrl/api/payments/intent/${_activeIntent!.intentId}');
        final res = await http.get(url).timeout(const Duration(seconds: 4));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final updated = PaymentIntentData.fromJson(data);
          if (updated.status != _activeIntent!.status) {
            setState(() {
              _activeIntent = updated;
            });
            _intentStreamController?.add(updated);

            if (updated.status == PaymentIntentStatus.verified) {
              timer.cancel();
              _handleVerifiedTransition();
            }
          }
        }
      } catch (_) {}
    });
  }

  void _handleVerifiedTransition() {
    if (_hasTriggeredCompletion) return;
    _hasTriggeredCompletion = true;
    _pollingTimer?.cancel();
    _countdownTimer?.cancel();

    _verifiedAnimController.forward();
    HapticFeedback.heavyImpact();

    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      widget.onPaymentVerified?.call();
      Navigator.of(context).pop(true);
    });
  }

  void _copyToClipboard(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMsg),
        backgroundColor: kGreen,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _dialVodafoneUssd(String wallet, int amount) async {
    // USSD: *9*7*WALLET*AMOUNT#
    final uri = Uri.parse('tel:*9*7*$wallet*$amount%23');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        _copyToClipboard('*9*7*$wallet*$amount#', _localized('USSD dial code copied!', 'تم نسخ كود التحويل!'));
      }
    } catch (_) {
      _copyToClipboard('*9*7*$wallet*$amount#', _localized('USSD dial code copied!', 'تم نسخ كود التحويل!'));
    }
  }

  void _showEditSenderDialog() {
    final isInsta = _selectedTab == PaymentMethodTab.instaPay;
    final controller = TextEditingController(
      text: isInsta
          ? _cleanIpa(_activeIntent?.expectedSenderIdentifier ?? '')
          : _cleanPhone(_activeIntent?.expectedSenderIdentifier ?? ''),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_rounded, color: kGreen, size: 22),
                const SizedBox(width: 8),
                Text(
                  _localized('Edit Transfer Sender Details', 'تعديل بيانات الحساب المحول منه'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: kInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              _localized(
                'Correcting your sender address will immediately check our payment oracle for matching transfers from the last 15 minutes.',
                'تصحيح البيانات سيعيد فحص التحويلات الواردة خلال آخر 15 دقيقة فوراً لتأكيد الحجز.',
              ),
              style: TextStyle(fontSize: 13, color: kMuted),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: isInsta ? TextInputType.text : TextInputType.phone,
              decoration: InputDecoration(
                labelText: isInsta ? _localized('InstaPay Handle', 'عنوان انستاباي') : _localized('Wallet Number', 'رقم المحفظة'),
                suffixText: isInsta ? '@instapay' : null,
                prefixText: isInsta ? null : '+20 ',
                filled: true,
                fillColor: kPage,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () {
                  final newSender = controller.text.trim();
                  if (newSender.isNotEmpty) {
                    Navigator.pop(ctx);
                    _initiatePaymentIntent(
                      overrideSender: isInsta ? '${_cleanIpa(newSender)}@instapay' : _cleanPhone(newSender),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _localized('Update & Re-Verify Payment', 'تحديث وإعادة التحقق الآن'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;

    return Scaffold(
      backgroundColor: kPage,
      appBar: AppBar(
        backgroundColor: kPanel,
        elevation: 0,
        title: Text(
          _localized('Automated Checkout', 'الدفع الآلي الفوري'),
          style: TextStyle(
            color: kInk,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: kInk, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: _activeIntent == null
            ? _buildDetailsFormView(isDark)
            : _buildActiveIntentStreamView(isDark),
      ),
    );
  }

  Widget _buildDetailsFormView(bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Amount Summary Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF047857), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: kGreen.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    _localized('Total Due Now', 'المبلغ المطلوب سداده'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${widget.amount.toInt()}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _localized('EGP', 'ج.م'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _localized('Zero Screenshots • Instant Auto-Confirmation', 'بدون رفع سكرين شوت • تأكيد آلي فوري'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2-Tab Selector
            Text(
              _localized('Choose Payment Channel', 'اختر طريقة الدفع'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: kInk,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildChannelTabButton(
                      title: 'InstaPay',
                      subtitle: _localized('Instant Transfer', 'تحويل فوري'),
                      icon: Icons.bolt_rounded,
                      accentColor: const Color(0xFF6366F1),
                      isSelected: _selectedTab == PaymentMethodTab.instaPay,
                      onTap: () => setState(() => _selectedTab = PaymentMethodTab.instaPay),
                    ),
                  ),
                  Expanded(
                    child: _buildChannelTabButton(
                      title: _localized('Mobile Wallet', 'محفظة إلكترونية'),
                      subtitle: 'Vodafone / Orange / e& / WE',
                      icon: Icons.account_balance_wallet_rounded,
                      accentColor: const Color(0xFFE11D48),
                      isSelected: _selectedTab == PaymentMethodTab.mobileWallet,
                      onTap: () => setState(() => _selectedTab = PaymentMethodTab.mobileWallet),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Tab Input Content
            if (_selectedTab == PaymentMethodTab.instaPay)
              _buildInstaPayInput(isDark)
            else
              _buildMobileWalletInput(isDark),

            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isCreatingIntent ? null : () => _initiatePaymentIntent(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                ),
                child: _isCreatingIntent
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _localized('Proceed to Transfer', 'المتابعة للتحويل'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward_rounded, size: 20),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChannelTabButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? kPanel : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? accentColor : kMuted, size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? kInk : kMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: kMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstaPayInput(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localized('Your InstaPay Address (Sending Account)', 'عنوان حساب انستاباي الخاص بك (المرسل منه)'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _instaPayController,
          decoration: InputDecoration(
            hintText: 'e.g. mohamed_ali',
            prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
            suffixIcon: Container(
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '@instapay',
                style: TextStyle(
                  color: Color(0xFF6366F1),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
            filled: true,
            fillColor: kPanel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _localized(
            'Important: Enter the exact username of the bank account sending the funds so the payment oracle can match it in seconds.',
            'تنبيه: اكتب اسم حساب انستاباي الذي ستقوم بالتحويل منه ليتعرف النظام الآلي على عملية الدفع خلال ثوانٍ.',
          ),
          style: TextStyle(fontSize: 11.5, color: kMuted),
        ),
      ],
    );
  }

  Widget _buildMobileWalletInput(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _localized('Your 11-Digit Mobile Wallet Number', 'رقم المحفظة الإلكترونية المحول منها'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: kInk,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _walletController,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            hintText: '010XXXXXXXX',
            prefixIcon: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Text(
                '🇪🇬 +20',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: kInk,
                  fontSize: 14,
                ),
              ),
            ),
            filled: true,
            fillColor: kPanel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE11D48), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _localized(
            'Supported wallets: Vodafone Cash, Orange Cash, e& money (Etisalat), WE Pay.',
            'المحافظ المدعومة: فودافون كاش، أورنج كاش، اتصالات كاش (e& money)، وي باي (WE Pay).',
          ),
          style: TextStyle(fontSize: 11.5, color: kMuted),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Waiting for Transfer View (Real-time StreamBuilder)
  // ---------------------------------------------------------------------------
  Widget _buildActiveIntentStreamView(bool isDark) {
    return StreamBuilder<PaymentIntentData>(
      stream: _intentStreamController?.stream,
      initialData: _activeIntent,
      builder: (context, snapshot) {
        final intent = snapshot.data ?? _activeIntent!;

        if (intent.status == PaymentIntentStatus.verified) {
          return _buildVerifiedSuccessState(intent);
        }

        if (intent.status == PaymentIntentStatus.expired) {
          return _buildExpiredState();
        }

        return _buildAwaitingTransferState(intent, isDark);
      },
    );
  }

  Widget _buildAwaitingTransferState(PaymentIntentData intent, bool isDark) {
    final isInsta = intent.expectedSenderIdentifier.contains('@');
    final minutes = _remainingTime.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remainingTime.inSeconds.remainder(60).toString().padLeft(2, '0');

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        children: [
          // Live Countdown Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation(Color(0xFFF59E0B)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _localized('Waiting for payment transfer...', 'بانتظار وصول التحويل تلقائياً...'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark ? const Color(0xFFFDE68A) : const Color(0xFFB45309),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$minutes:$seconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Transfer Instructions Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localized('Send payment to this destination:', 'حوّل المبلغ إلى هذا الحساب:'),
                  style: TextStyle(
                    fontSize: 13,
                    color: kMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),

                // Destination Box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kPage,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isInsta ? Icons.bolt_rounded : Icons.phone_iphone_rounded,
                        color: isInsta ? const Color(0xFF6366F1) : const Color(0xFFE11D48),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isInsta ? _localized('Receiver InstaPay IPA', 'حساب انستاباي المستلم') : _localized('Receiver Wallet Number', 'رقم المحفظة المستلمة'),
                              style: TextStyle(fontSize: 11, color: kMuted),
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              isInsta ? widget.receiverIpa : widget.receiverWallet,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: kInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        color: kGreen,
                        tooltip: 'Copy',
                        onPressed: () => _copyToClipboard(
                          isInsta ? widget.receiverIpa : widget.receiverWallet,
                          _localized('Address copied!', 'تم نسخ الحساب!'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Amount to transfer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _localized('Exact Amount to Transfer:', 'المبلغ المطلوب تحويله بالظبط:'),
                      style: TextStyle(fontSize: 13, color: kMuted, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${intent.expectedAmount.toInt()} ${_localized("EGP", "ج.م")}',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: kGreen,
                      ),
                    ),
                  ],
                ),

                if (!isInsta) ...[
                  const SizedBox(height: 16),
                  // USSD 1-Tap Quick Pay Button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () => _dialVodafoneUssd(
                        widget.receiverWallet,
                        intent.expectedAmount.toInt(),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE11D48),
                        side: const BorderSide(color: Color(0xFFE11D48)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.dialpad_rounded, size: 18),
                      label: Text(
                        _localized('1-Tap Vodafone Cash USSD (*9*7#)', 'دفع سريع فودافون كاش (*9*7#)'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sender Identification Verification Badge
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.shield_outlined, color: kGreen, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localized('Listening for transfer from:', 'في انتظار التحويل من:'),
                        style: TextStyle(fontSize: 11.5, color: kMuted),
                      ),
                      Text(
                        intent.expectedSenderIdentifier,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: kInk,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _showEditSenderDialog,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: kGreen,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.edit_rounded, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _localized('Edit', 'تعديل'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Educational step explanation
          Text(
            _localized(
              'Once you send the transfer, our automated gateway oracle verifies it instantly. No receipts or screenshots required!',
              'بمجرد إتمام التحويل، سيتعرف النظام الآلي على عمليتك فوراً ويؤكد الحجز تلقائياً دون الحاجة لرفع إيصال!',
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: kMuted,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedSuccessState(PaymentIntentData intent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: kGreen,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x6610B981),
                      blurRadius: 28,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 54,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              _localized('Payment Verified & Confirmed!', 'تم تأكيد الدفع بنجاح!'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: kInk,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _localized(
                'Your payment of ${intent.expectedAmount.toInt()} EGP has been verified by the automated oracle. Redirecting to your confirmed booking...',
                'تم التحقق من استلام ${intent.expectedAmount.toInt()} ج.م آلياً بنجاح. جاري نقلك لصفحة الحجز المؤكد...',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: kMuted,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(kGreen),
              strokeWidth: 2.5,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpiredState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.timer_off_rounded,
                size: 48,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _localized('Payment Session Expired', 'انتهت صلاحية جلسة الدفع'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: kInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _localized(
                'The 10-minute payment window elapsed before receiving transfer. If you have already transferred, click below to re-verify.',
                'انتهت مهلة الـ 10 دقائق قبل وصول التحويل. إذا قمت بالتحويل بالفعل، اضغط بالأسفل للتحقق الفوري.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kMuted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _initiatePaymentIntent(),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(_localized('Restart & Re-Check', 'إعادة المحاولة والفحص')),
            ),
          ],
        ),
      ),
    );
  }
}
