import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import '../core/models/models_v2.dart';
import '../features/passport_wallet/passport_wallet.dart';
import 'unified_payment_screen.dart';

class CustomerProfileTab extends StatefulWidget {
  const CustomerProfileTab({
    super.key,
    required this.arabic,
    required this.customerName,
    required this.customerEmail,
    required this.customerPhone,
    required this.isSignedIn,
    required this.bookingCount,
    required this.walletBalance,
    this.onWalletUpdated,
    required this.currentArea,
    required this.api,
    required this.apiConfigured,
    required this.onSignIn,
    required this.onSignOut,
    this.onDeleteAccount,
    required this.onUpdateProfile,
    required this.onChangeLanguage,
    required this.onViewBookings,
    required this.onSelectArea,
    required this.onAutoAssignGps,
    this.onSwitchToAdmin,
    this.onToggleDarkMode,
    this.onGoToSignIn,
  });

  final bool arabic;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final bool isSignedIn;
  final int bookingCount;
  final double walletBalance;
  final ValueChanged<double>? onWalletUpdated;
  final String currentArea;
  final HagzyApi api;
  final bool apiConfigured;
  final Future<void> Function({
    required String name,
    required String email,
    required String phone,
    String? token,
    double? walletBalance,
  }) onSignIn;
  final Future<void> Function() onSignOut;
  final Future<void> Function()? onDeleteAccount;
  final Future<void> Function({
    required String name,
    required String email,
    required String phone,
    String? token,
    double? walletBalance,
  }) onUpdateProfile;
  final VoidCallback onChangeLanguage;
  final VoidCallback onViewBookings;
  final VoidCallback onSelectArea;
  final VoidCallback onAutoAssignGps;
  final VoidCallback? onSwitchToAdmin;
  final VoidCallback? onToggleDarkMode;
  final VoidCallback? onGoToSignIn;

  @override
  State<CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<CustomerProfileTab> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = false;
  String? _errorMessage;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _populateControllers();
  }

  void _populateControllers() {
    _nameController.text = widget.customerName;
    _emailController.text = widget.customerEmail;
    _phoneController.text = widget.customerPhone;
  }

  @override
  void didUpdateWidget(CustomerProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.customerName != oldWidget.customerName ||
        widget.customerEmail != oldWidget.customerEmail ||
        widget.customerPhone != oldWidget.customerPhone) {
      _populateControllers();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
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

  Future<void> _submitProfileUpdate() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (email.isNotEmpty && !email.contains('@')) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Please enter a valid email address.',
          'يرجى إدخال بريد إلكتروني صحيح.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      await widget.onUpdateProfile(
        name: name,
        email: email,
        phone: phone,
      );

      if (mounted) {
        setState(() {
          _isEditing = false;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localized(
              widget.arabic,
              'Profile updated successfully!',
              'تم تحديث البيانات بنجاح!',
            )),
            backgroundColor: kSnackBarBg,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = friendlyError(e, arabic: widget.arabic);
        });
      }
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return 'U';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    final signedIn = widget.isSignedIn;
    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;

    // Clean Warm Consumer Profile Card
    final profileHeaderCard = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(color: kBorder, width: 1.0),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: kVermilion,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: widget.customerName.trim().isNotEmpty
                      ? Text(
                          _getInitials(widget.customerName),
                          style: hagzyDisplayStyle(
                            arabic: false,
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 27,
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            !signedIn
                                ? localized(
                                    arabic, 'Guest Visitor', 'تصفح كضيف')
                                : (widget.customerName.isNotEmpty
                                    ? widget.customerName
                                    : localized(
                                        arabic, 'Hagzy Member', 'عضو حجزي')),
                            style: hagzyDisplayStyle(
                              arabic: arabic,
                              fontWeight: FontWeight.w800,
                              fontSize: 21,
                              color: kInk,
                              letterSpacing: -0.35,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (signedIn) ...[
                          const SizedBox(width: 6),
                          Icon(
                            Icons.verified_rounded,
                            color: kBrandAccent,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    if (signedIn &&
                        (widget.customerName.trim().isEmpty ||
                            widget.customerName.trim().toLowerCase() ==
                                'customer' ||
                            widget.customerName.trim().toLowerCase() ==
                                'hagzy member')) ...[
                      const SizedBox(height: 3),
                      InkWell(
                        onTap: () => setState(() => _isEditing = true),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_note_rounded,
                                  size: 16, color: kBrandAccent),
                              const SizedBox(width: 4),
                              Text(
                                localized(arabic, 'Tap to set your full name',
                                    'اضغط لإضافة اسمك بالكامل'),
                                style: TextStyle(
                                  color: kBrandAccent,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      !signedIn
                          ? localized(
                              arabic,
                              'Sign in to sync bookings & wallet',
                              'سجل الدخول لمزامنة الحجوزات والمحفظة',
                            )
                          : (widget.customerEmail.isNotEmpty
                              ? widget.customerEmail
                              : (widget.customerPhone.isNotEmpty
                                  ? widget.customerPhone
                                  : localized(
                                      arabic,
                                      'Verified Hagzy Account',
                                      'حساب حجزي موثق',
                                    ))),
                      style: TextStyle(
                        fontSize: 13,
                        color: kMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (signedIn)
                IconButton(
                  tooltip: localized(
                    arabic,
                    _isEditing ? 'Cancel Edit' : 'Edit Profile',
                    _isEditing ? 'إلغاء التعديل' : 'تعديل البيانات',
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    backgroundColor: kSurfaceSubtle,
                    foregroundColor: kInk,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusMedium),
                    ),
                  ),
                  icon: Icon(
                    _isEditing ? Icons.close : Icons.edit_outlined,
                    size: 19,
                  ),
                  onPressed: () {
                    HagzyHaptics.selection();
                    setState(() {
                      _isEditing = !_isEditing;
                      _errorMessage = null;
                    });
                  },
                ),
            ],
          ),
          if (signedIn && !_isEditing) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.customerPhone.isNotEmpty)
                  _InfoChip(
                    icon: Icons.phone_android_rounded,
                    label: widget.customerPhone,
                  ),
                if (widget.customerEmail.isNotEmpty)
                  _InfoChip(
                    icon: Icons.email_outlined,
                    label: widget.customerEmail,
                  ),
                if (widget.customerEmail.endsWith('@privaterelay.appleid.com') ||
                    widget.customerEmail.endsWith('@icloud.com'))
                  const _InfoChip(
                    icon: Icons.apple,
                    label: 'Apple ID',
                  )
                else if (widget.customerEmail.endsWith('@gmail.com') ||
                    widget.customerEmail.endsWith('@google.com'))
                  _InfoChip(
                    icon: Icons.g_mobiledata_rounded,
                    label: localized(arabic, 'Google Account', 'حساب جوجل'),
                  ),
                _InfoChip(
                  icon: Icons.location_on_rounded,
                  label: governorateName(widget.currentArea, arabic),
                ),
                _InfoChip(
                  icon: Icons.cloud_done_rounded,
                  label: localized(arabic, 'Cloud Synced', 'متزامن سحابياً'),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    final settingsAndActions = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Clean Grouped Settings Card
        Container(
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
            border: Border.all(color: kBorder, width: 1.0),
            boxShadow: HagzyTheme.subtleShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _SettingTile(
                icon: kDarkMode.value
                    ? Icons.dark_mode_rounded
                    : Icons.light_mode_rounded,
                iconWidget: HagzyThemeModeIcon(
                  isDark: kDarkMode.value,
                  size: 19,
                ),
                title: localized(arabic, 'Dark Mode', 'الوضع الليلي'),
                subtitle: kDarkMode.value
                    ? localized(arabic, 'On', 'مُفعّل')
                    : localized(arabic, 'Off', 'الوضع النهاري'),
                trailing: Switch.adaptive(
                  value: kDarkMode.value,
                  activeThumbColor: kVermilion,
                  onChanged: (_) {
                    HagzyHaptics.selection();
                    widget.onToggleDarkMode?.call();
                  },
                ),
                onTap: () {
                  HagzyHaptics.selection();
                  widget.onToggleDarkMode?.call();
                },
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.language_rounded,
                title: localized(arabic, 'Language', 'اللغة'),
                subtitle: arabic ? 'العربية' : 'English',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kSurfaceTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    arabic ? 'English' : 'عربي',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: kInk,
                    ),
                  ),
                ),
                onTap: widget.onChangeLanguage,
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.location_city_rounded,
                title: localized(
                    arabic, 'Current Area & GPS', 'المنطقة وتحديد الـ GPS'),
                subtitle: governorateName(widget.currentArea, arabic),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: localized(
                        arabic,
                        'Detect nearest area via GPS',
                        'تحديد تلقائي عبر GPS',
                      ),
                      icon: Icon(Icons.my_location_rounded,
                          color: kBrandAccent, size: 20),
                      onPressed: widget.onAutoAssignGps,
                    ),
                    const HagzyDirectionalChevron(size: 18),
                  ],
                ),
                onTap: widget.onSelectArea,
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.mark_chat_read_rounded,
                title: localized(
                    arabic, 'WhatsApp Booking Updates', 'إشعارات الواتساب'),
                subtitle: localized(
                  arabic,
                  'Instant confirmations & calendar reminders',
                  'تأكيدات فورية وتذكيرات بالمواعيد',
                ),
                trailing: Icon(
                  Icons.check_circle_rounded,
                  color: kSuccess,
                  size: 20,
                ),
                onTap: () => _showWhatsAppUpdatesModal(context, arabic),
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.verified_user_outlined,
                title:
                    localized(arabic, 'Privacy & Security', 'الخصوصية والأمان'),
                subtitle: localized(
                  arabic,
                  'Payment protection, Privacy Policy & Terms',
                  'حماية المدفوعات، سياسة الخصوصية والشروط',
                ),
                trailing: const HagzyDirectionalChevron(size: 18),
                onTap: () => _showPrivacySecurityModal(context, arabic),
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.description_outlined,
                title: localized(arabic, 'Privacy Policy', 'سياسة الخصوصية'),
                subtitle: localized(
                  arabic,
                  'How Hagzy protects your data',
                  'كيف يحمي تطبيق حجزي بياناتك',
                ),
                trailing: const HagzyDirectionalChevron(size: 18),
                onTap: () => _showLegalDocumentViewer(
                  context,
                  arabic: arabic,
                  isPrivacy: true,
                ),
              ),
              const Divider(height: 1, indent: 64),
              _SettingTile(
                icon: Icons.gavel_rounded,
                title: localized(arabic, 'Terms of Service', 'شروط الاستخدام'),
                subtitle: localized(
                  arabic,
                  'Booking holds, cancellations & guidelines',
                  'سياسات الحجز والإلغاء والاستخدام',
                ),
                trailing: const HagzyDirectionalChevron(size: 18),
                onTap: () => _showLegalDocumentViewer(
                  context,
                  arabic: arabic,
                  isPrivacy: false,
                ),
              ),
              if (widget.onSwitchToAdmin != null) ...[
                const Divider(height: 1, indent: 64),
                _SettingTile(
                  icon: Icons.storefront_rounded,
                  title: localized(
                      arabic, 'Partner Portal', 'بوابة الشركاء وأصحاب الأماكن'),
                  subtitle: localized(
                    arabic,
                    'Manage your venue or request partner access',
                    'إدارة مكانك أو طلب الانضمام كشريك',
                  ),
                  trailing: HagzyDirectionalChevron(
                      size: 18, color: kBrandAccent),
                  onTap: widget.onSwitchToAdmin,
                ),
              ],
            ],
          ),
        ),
      ],
    );

    final statsRow = Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.calendar_month_rounded,
            title: '${widget.bookingCount}',
            subtitle: localized(arabic, 'Bookings', 'حجوزات'),
            onTap: widget.onViewBookings,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.account_balance_wallet_rounded,
            title:
                '${widget.walletBalance.toStringAsFixed(0)} ${localized(arabic, 'EGP', 'ج.م')}',
            subtitle: localized(arabic, 'Wallet', 'المحفظة'),
            badge: signedIn ? localized(arabic, 'Top Up', 'شحن') : null,
            onTap: signedIn
                ? () => _topUpWalletDialog(widget.walletBalance)
                : widget.onGoToSignIn,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.my_location_rounded,
            title: governorateName(widget.currentArea, arabic),
            subtitle: localized(arabic, 'My Area', 'محافظتي'),
            onTap: widget.onSelectArea,
          ),
        ),
      ],
    );

    final passportSection = !signedIn
        ? HagzySurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const IconBox(icon: Icons.verified_user_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            localized(
                              arabic,
                              'Sign In for Hagzy Passport & Wallet',
                              'سجّل الدخول لتفعيل جواز السفر والمحفظة',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              color: kInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            localized(
                              arabic,
                              'Earn reliability perks, sync bookings & top up your wallet.',
                              'اجمع نقاط الموثوقية وزامن حجوزاتك واشحن محفظتك.',
                            ),
                            style: TextStyle(fontSize: 12.5, color: kMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (widget.onGoToSignIn != null) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: widget.onGoToSignIn,
                    icon: const Icon(Icons.login_rounded, size: 18),
                    label: Text(localized(arabic, 'Sign In / Create Account',
                        'تسجيل الدخول / إنشاء حساب')),
                  ),
                ],
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              UserReliabilityPassportCard(
                profile: UserProfile(
                  id: widget.customerPhone.isNotEmpty
                      ? widget.customerPhone
                      : 'member',
                  phoneNumber: widget.customerPhone.isNotEmpty
                      ? widget.customerPhone
                      : '01000000000',
                  displayName: widget.customerName.isNotEmpty
                      ? widget.customerName
                      : 'Hagzy Member',
                  city: widget.currentArea,
                  completedBookingsCount: widget.bookingCount,
                  reliabilityScore: widget.bookingCount == 0
                      ? 85.0
                      : (85.0 + (widget.bookingCount * 5.0)).clamp(85.0, 100.0),
                  hagzyWalletBalance: widget.walletBalance,
                  badges: [
                    if (widget.bookingCount >= 1) 'reliable',
                    if (widget.bookingCount >= 3) 'shilla_leader',
                    if (widget.bookingCount >= 5) 'gamer_vip',
                  ],
                  createdAt: DateTime(2026, 1, 1),
                ),
                isArabic: arabic,
                onTopUpTap: () => _topUpWalletDialog(widget.walletBalance),
              ),
              const SizedBox(height: 12),
              CrossCategoryVouchersCarousel(
                isArabic: arabic,
              ),
            ],
          );

    return ListView(
      // ignore: deprecated_member_use
      cacheExtent: 3000,
      controller: _scrollController,
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 18 : 12,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    profileHeaderCard,
                    const SizedBox(height: 16),
                    statsRow,
                    const SizedBox(height: 16),
                    passportSection,
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_isEditing) ...[
                      _buildEditProfileCard(arabic),
                      const SizedBox(height: 16),
                    ],
                    settingsAndActions,
                  ],
                ),
              ),
            ],
          )
        else ...[
          profileHeaderCard,
          const SizedBox(height: 14),
          if (_isEditing) ...[
            _buildEditProfileCard(arabic),
            const SizedBox(height: 14),
          ],
          statsRow,
          const SizedBox(height: 14),
          settingsAndActions,
          const SizedBox(height: 14),
          passportSection,
        ],
        const SizedBox(height: 20),

        // Sign Out & Account Deletion Buttons
        if (signedIn) ...[
          PressableScale(
            onTap: () async {
              final confirm = await showHagzyAdaptiveModal<bool>(
                context: context,
                builder: (context, isSheet) => HagzyModalCard(
                  isSheet: isSheet,
                  centerHeader: true,
                  destructive: true,
                  icon: Icons.logout_rounded,
                  title: localized(
                    arabic,
                    'Sign out of Hagzy?',
                    'تسجيل الخروج من حجزي؟',
                  ),
                  subtitle: localized(
                    arabic,
                    'You will need to sign in again to access your saved profile and bookings.',
                    'سيتعين عليك تسجيل الدخول مجدداً للوصول إلى حسابك وحجوزاتك.',
                  ),
                  onClose: () => Navigator.pop(context, false),
                  primaryLabel: localized(arabic, 'Sign Out', 'تسجيل الخروج'),
                  onPrimary: () => Navigator.pop(context, true),
                  secondaryLabel: localized(arabic, 'Cancel', 'إلغاء'),
                  onSecondary: () => Navigator.pop(context, false),
                ),
              );
              if (confirm == true) {
                HagzyHaptics.medium();
                await widget.onSignOut();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localized(
                        arabic,
                        'Signed out successfully.',
                        'تم تسجيل الخروج بنجاح.',
                      )),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: kError.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
                border: Border.all(
                  color: kError.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.logout_rounded, color: kError, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    localized(arabic, 'Sign Out', 'تسجيل الخروج'),
                    style: TextStyle(
                      color: kError,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Apple App Store Guideline 5.1.1(v) & Google Play Data Safety requirement
          Center(
            child: TextButton.icon(
              key: const Key('delete_account_button'),
              onPressed: () async {
                final confirm = await showHagzyAdaptiveModal<bool>(
                  context: context,
                  builder: (context, isSheet) => HagzyModalCard(
                    isSheet: isSheet,
                    centerHeader: true,
                    destructive: true,
                    icon: Icons.delete_forever_rounded,
                    title: localized(
                      arabic,
                      'Delete Account Permanently?',
                      'حذف الحساب نهائياً؟',
                    ),
                    subtitle: localized(
                      arabic,
                      'This permanently erases your profile, wallet balance, and reservation history.',
                      'سيتم مسح ملفك الشخصي ورصيد المحفظة وسجل الحجوزات نهائياً.',
                    ),
                    onClose: () => Navigator.pop(context, false),
                    content: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: kError.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: kError.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        localized(
                          arabic,
                          'Are you sure you want to permanently delete your Hagzy account? This will erase your personal profile, phone number, and reservation history from this device and our servers. This action cannot be undone.',
                          'هل أنت متأكد من رغبتك في حذف حسابك في حجزي نهائياً؟ سيتم مسح بياناتك الشخصية ورقم الموبايل وسجل الحجوزات تماماً من هذا الجهاز وسيرفراتنا ولا يمكن التراجع عن هذا الإجراء.',
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          color: kInk,
                          height: 1.48,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    primaryKey: const Key('confirm_delete_account_button'),
                    primaryLabel:
                        localized(arabic, 'Delete Forever', 'حذف نهائياً'),
                    onPrimary: () => Navigator.pop(context, true),
                    secondaryLabel:
                        localized(arabic, 'Keep Account', 'الاحتفاظ بالحساب'),
                    onSecondary: () => Navigator.pop(context, false),
                  ),
                );
                if (confirm == true) {
                  HagzyHaptics.medium();
                  if (widget.onDeleteAccount != null) {
                    await widget.onDeleteAccount!();
                  } else {
                    await widget.onSignOut();
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: Colors.red.shade900,
                        content: Text(localized(
                          arabic,
                          'Your account and personal data have been permanently deleted.',
                          'تم حذف حسابك وكافة بياناتك الشخصية نهائياً.',
                        )),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
              icon: Icon(Icons.delete_forever_rounded,
                  color: kMuted, size: 17),
              label: Text(
                localized(arabic, 'Delete Account & Personal Data',
                    'حذف الحساب والبيانات الشخصية'),
                style: TextStyle(
                  color: kMuted,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: kMuted,
                fontSize: 12.0,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: localized(
                    arabic,
                    'Hagzy v1.0.0 · Made with ',
                    'حجزي v1.0.0 · صُنع بـ ',
                  ),
                ),
                const WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Icons.favorite_rounded,
                    size: 13,
                    color: Color(0xFFE11D48),
                  ),
                ),
                TextSpan(
                  text: localized(
                    arabic,
                    ' in Kafr El-Sheikh',
                    ' في كفر الشيخ',
                  ),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildEditProfileCard(bool arabic) {
    return HagzySurfaceCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconBox(icon: Icons.badge_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localized(arabic, 'Edit Your Profile', 'تعديل بيانات حسابك'),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: kInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
            decoration: InputDecoration(
              labelText: localized(
                  arabic, 'Full Name (optional)', 'الاسم بالكامل (اختياري)'),
              hintText:
                  localized(arabic, 'e.g. Mohamed Hegazy', 'مثال: محمد حجازي'),
              prefixIcon: const Icon(Icons.person_outline_rounded),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: localized(arabic, 'Phone Number', 'رقم الموبايل'),
              hintText: '010XXXXXXXX / 011XXXXXXXX',
              prefixIcon: const Icon(Icons.phone_android_rounded),
              helperText: localized(
                arabic,
                'Enter 11-digit Egyptian mobile number',
                'أدخل رقم موبايل مصري مكون من 11 رقماً',
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: localized(arabic, 'Email Address (optional)',
                  'البريد الإلكتروني (اختياري)'),
              hintText: 'name@example.com',
              prefixIcon: const Icon(Icons.email_outlined),
              isDense: true,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: kError.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: kError),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: kError,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: _loading ? null : _submitProfileUpdate,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      localized(arabic, 'Save Profile Changes', 'حفظ التعديلات'),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLegalDocumentViewer(BuildContext context,
      {required bool arabic, required bool isPrivacy}) {
    showHagzyLegalSheet(
      context,
      arabic: arabic,
      isPrivacy: isPrivacy,
      apiBaseUrl: widget.api.baseUrl,
    );
  }

  void _showPrivacySecurityModal(BuildContext context, bool arabic) {
    showHagzySheet<void>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.verified_user_rounded,
                            color: kGreen,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localized(arabic, 'Privacy & Security',
                                    'الخصوصية والأمان'),
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                  color: kInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                localized(
                                  arabic,
                                  'Protected by Hagzy Escrow & Encrypted Payments',
                                  'حماية كاملة للمدفوعات وحجز مؤكد بنكياً',
                                ),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: kMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.timer_rounded,
                      iconColor: kSuccess,
                      title: localized(arabic, '15-Minute Guaranteed Slot Hold',
                          'ضمان حجز الموعد لمدة 15 دقيقة'),
                      description: localized(
                        arabic,
                        'While you confirm payment, your court or salon appointment is exclusively locked on the system. No other customer can take your slot.',
                        'أثناء مراجعة الحجز والدفع، يتم قفل الموعد حصرياً لك على السيستم ولا يمكن لأي عميل آخر حجزه.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.shield_rounded,
                      iconColor: kInfoBlue,
                      title: localized(
                          arabic,
                          'PCI-DSS Paymob Escrow Protection',
                          'حماية الضمان المالي عبر Paymob'),
                      description: localized(
                        arabic,
                        'Online payments (Cards, InstaPay, Mobile Wallets) are encrypted with bank-grade security. Funds are only transferred after appointment confirmation.',
                        'جميع المعاملات (كروت بنكية، إنستاباي، محافظ المحمول) مؤمنة بأعلى المعايير البنكية دون تخزين بيانات الكارت.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.lock_person_rounded,
                      iconColor: kDarkMode.value
                          ? const Color(0xFFC084FC)
                          : const Color(0xFF7B1FA2),
                      title: localized(
                          arabic,
                          'Personal Data & Zero Spam Policy',
                          'خصوصية بياناتك وسياسة منع الإزعاج'),
                      description: localized(
                        arabic,
                        'Your mobile number is only shared with the venue manager 1 hour prior to your booking. We never sell or share your data with advertisers.',
                        'رقم هاتفك محمي ولا تتم مشاركته إلا مع إدارة الملعب أو الصالون قبل الموعد بساعة لضمان دخولك دون أي رسائل إعلانية.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.delete_sweep_rounded,
                      iconColor: kError,
                      title: localized(
                          arabic,
                          'Right to Permanent Account Deletion',
                          'الحق في الحذف الكامل للبيانات'),
                      description: localized(
                        arabic,
                        'In compliance with Egyptian Data Protection Law & Apple/Google policies, you can erase your account and booking history anytime in 1 click.',
                        'وفقاً لقوانين حماية البيانات، يمكنك في أي وقت مسح حسابك وسجل حجوزاتك بالكامل بضغطة زر واحدة من بروفايلك.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kInk,
                              side: BorderSide(color: kBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: Icon(Icons.description_outlined,
                                size: 18, color: kGreen),
                            label: Text(
                              localized(
                                  arabic, 'Privacy Policy', 'سياسة الخصوصية'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            onPressed: () => _showLegalDocumentViewer(
                              context,
                              arabic: arabic,
                              isPrivacy: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kInk,
                              side: BorderSide(color: kBorder),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: Icon(Icons.gavel_rounded,
                                size: 18, color: kGreen),
                            label: Text(
                              localized(
                                  arabic, 'Terms of Service', 'شروط الاستخدام'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            onPressed: () => _showLegalDocumentViewer(
                              context,
                              arabic: arabic,
                              isPrivacy: false,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    PressableScale(
                      onTap: () => Navigator.pop(ctx),
                      child: Container(
                        height: 46,
                        decoration: BoxDecoration(
                          color: kSurfaceTint,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: kBorder),
                        ),
                        child: Center(
                          child: Text(
                            localized(arabic, 'Done', 'تم'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                              color: kInk,
                            ),
                          ),
                        ),
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
  }

  void _showWhatsAppUpdatesModal(BuildContext context, bool arabic) {
    showHagzySheet<void>(
      context: context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: kBorder,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF25D366).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.mark_chat_read_rounded,
                            color: Color(0xFF25D366),
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localized(arabic, 'WhatsApp Booking Updates',
                                    'إشعارات وتأكيدات الواتساب'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: kInk,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(Icons.check_circle_rounded,
                                      color: kGreen, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    localized(arabic, 'Active on this account',
                                        'مفعلة تلقائياً لحسابك'),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: kGreen,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.qr_code_2_rounded,
                      iconColor: const Color(0xFF25D366),
                      title: localized(
                          arabic,
                          'Instant Digital Match Pass & QR',
                          'تذكرة وتأكيد فوري برمز QR'),
                      description: localized(
                        arabic,
                        'Get your official booking voucher directly on WhatsApp with arrival instructions and QR code for venue check-in.',
                        'تصلك تذكرة الحجز الرسمية فوراً على الواتساب مع كود QR للدخول السريع وتعليمات الوصول للملعب أو الصالون.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.access_alarms_rounded,
                      iconColor: const Color(0xFFFB8C00),
                      title: localized(arabic, '1-Hour Smart Arrival Reminder',
                          'تذكير ذكي قبل الموعد بساعة'),
                      description: localized(
                        arabic,
                        'Automated WhatsApp reminder with 1-tap Google Maps directions so you and your friends arrive right on time.',
                        'رسالة تذكيرية قبل بدء الموعد بساعة متضمنة لوكيشن المكان على خرائط جوجل لسهولة وصولك وفريقك.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildSecurityPillar(
                      arabic: arabic,
                      icon: Icons.support_agent_rounded,
                      iconColor: const Color(0xFF1E88E5),
                      title: localized(arabic, 'Direct Support & Assistance',
                          'دعم فوري ومباشر 24/7'),
                      description: localized(
                        arabic,
                        'Need to reschedule, invite friends, or speak with venue staff? Our official WhatsApp support is available 24/7.',
                        'تحتاج لتعديل موعدك أو إضافة أصدقاء أو سؤال الإدارة؟ خدمة عملاء حجزي متاحة للمساعدة الفورية.',
                      ),
                    ),
                    const SizedBox(height: 20),
                    PressableScale(
                      onTap: () async {
                        Navigator.pop(ctx);
                        final msg = Uri.encodeComponent(
                          arabic
                              ? 'مرحباً خدمة عملاء حجزي، لدي استفسار بخصوص الحجوزات.'
                              : 'Hello Hagzy Support, I have an inquiry about my bookings.',
                        );
                        final uri = Uri.parse(
                            'https://wa.me/$kWhatsappBusinessNumber?text=$msg');
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFF25D366),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF25D366)
                                  .withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline_rounded,
                                color: Colors.white, size: 19),
                            const SizedBox(width: 8),
                            Text(
                              localized(arabic, 'Chat with Hagzy on WhatsApp',
                                  'تواصل مع حجزي على الواتساب'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                          ],
                        ),
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
  }

  Widget _buildSecurityPillar({
    required bool arabic,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kSurfaceTint,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: kMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: kVermilion),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.0,
                fontWeight: FontWeight.w700,
                color: kInk,
              ),
            ),
          ],
        ),
      );
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
          border: Border.all(color: kBorder, width: 1.1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: isDark ? kVermilion : kObsidian,
                    borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
                  ),
                  child: Icon(
                    icon,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 4),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: kSurfaceTint,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(color: kBorder),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          badge!,
                          maxLines: 1,
                          style: hagzyMonoStyle(
                            color: kInk,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            arabic: isArabicMode,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: hagzyMonoStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: kInk,
                arabic: isArabicMode,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12.0,
                color: kMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Widget? iconWidget;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: HagzyTap(
        scaleDown: 0.985,
        pressedOpacity: 0.92,
        haptic: HagzyHapticStyle.selection,
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kSurfaceSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: iconWidget ??
                    Icon(
                      icon,
                      size: 18,
                      color: isDark ? kVolt : kObsidian,
                    ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.0,
                        color: kMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}
