import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';

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
  });

  final bool arabic;
  final String customerName;
  final String customerEmail;
  final String customerPhone;
  final bool isSignedIn;
  final int bookingCount;
  final double walletBalance;
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
            backgroundColor: kInk,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        // Top Profile Card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
            boxShadow: HagzyTheme.softShadow,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: HagzyTheme.brandGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: kGreen.withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: widget.customerName.trim().isNotEmpty
                          ? Text(
                              _getInitials(widget.customerName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 22,
                              ),
                            )
                          : const Icon(
                              Icons.person_rounded,
                              color: Colors.white,
                              size: 28,
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.customerName.isNotEmpty
                                    ? widget.customerName
                                    : localized(
                                        arabic, 'Hagzy Member', 'عضو حجزي'),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: kInk,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified_rounded,
                              color: kGreen,
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.customerEmail.isNotEmpty
                              ? widget.customerEmail
                              : (widget.customerPhone.isNotEmpty
                                  ? widget.customerPhone
                                  : localized(
                                      arabic,
                                      'Verified Hagzy Account',
                                      'حساب حجزي موثق',
                                    )),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: kInk,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: localized(
                      arabic,
                      _isEditing ? 'Cancel Edit' : 'Edit Profile',
                      _isEditing ? 'إلغاء التعديل' : 'تعديل البيانات',
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: kSurfaceTint,
                      foregroundColor: kInk,
                    ),
                    icon: Icon(
                      _isEditing ? Icons.close : Icons.edit_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() {
                      _isEditing = !_isEditing;
                      _errorMessage = null;
                    }),
                  ),
                ],
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                // Quick info pills
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
                    if (widget.customerEmail
                            .endsWith('@privaterelay.appleid.com') ||
                        widget.customerEmail.endsWith('@icloud.com'))
                      const _InfoChip(
                        icon: Icons.apple,
                        label: 'Apple ID',
                      )
                    else if (widget.customerEmail.endsWith('@gmail.com') ||
                        widget.customerEmail.endsWith('@google.com'))
                      const _InfoChip(
                        icon: Icons.g_mobiledata_rounded,
                        label: 'Google Account',
                      ),
                    _InfoChip(
                      icon: Icons.location_on_rounded,
                      label: governorateName(widget.currentArea, arabic),
                    ),
                    _InfoChip(
                      icon: Icons.cloud_done_rounded,
                      label:
                          localized(arabic, 'Cloud Synced', 'متزامن سحابياً'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Edit Profile Form Card (only shown when editing profile details)
        if (_isEditing) ...[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder),
              boxShadow: HagzyTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.badge_outlined,
                        color: kGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        localized(
                            arabic, 'Edit Your Profile', 'تعديل بيانات حسابك'),
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
                    labelText: localized(arabic, 'Full Name (optional)',
                        'الاسم بالكامل (اختياري)'),
                    hintText: localized(
                        arabic, 'e.g. Mohamed Hegazy', 'مثال: محمد حجازي'),
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
                    labelText:
                        localized(arabic, 'Phone Number', 'رقم الموبايل'),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            size: 16, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.redAccent,
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
                PressableScale(
                  onTap: _loading ? null : _submitProfileUpdate,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: HagzyTheme.brandGradient,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: kGreen.withValues(alpha: 0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : Text(
                              localized(
                                arabic,
                                'Save Profile Changes',
                                'حفظ التعديلات',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Stats & Quick Performed Actions
        Row(
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
                title: '${widget.walletBalance.toStringAsFixed(0)} EGP',
                subtitle: localized(arabic, 'Wallet', 'المحفظة'),
                badge: localized(arabic, 'Active', 'نشطة'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(localized(
                        arabic,
                        'Your Hagzy Wallet balance is ${widget.walletBalance.toStringAsFixed(0)} EGP. It is automatically applied at checkout.',
                        'رصيد محفظتك ${widget.walletBalance.toStringAsFixed(0)} ج.م ويتم خصمه تلقائياً عند الدفع.',
                      )),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
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
        ),

        const SizedBox(height: 16),

        // Settings & Options Card
        Container(
          decoration: BoxDecoration(
            color: kDarkMode.value ? const Color(0xFF131C31) : kPanel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: kDarkMode.value ? const Color(0xFF283552) : kBorder),
            boxShadow: HagzyTheme.softShadow,
          ),
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
                    ? localized(arabic, 'Enabled (Obsidian Emerald)',
                        'مُفعّل (مريح للعين)')
                    : localized(
                        arabic, 'Light Mode Active', 'الوضع النهاري مُفعّل'),
                trailing: Switch.adaptive(
                  value: kDarkMode.value,
                  activeThumbColor: kGreenLight,
                  onChanged: (_) => widget.onToggleDarkMode?.call(),
                ),
                onTap: widget.onToggleDarkMode,
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.language_rounded,
                title: localized(arabic, 'Language', 'اللغة'),
                subtitle: arabic ? 'العربية' : 'English',
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kDarkMode.value
                        ? const Color(0xFF19243D)
                        : kSurfaceTint,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: kDarkMode.value
                            ? const Color(0xFF283552)
                            : kBorder),
                  ),
                  child: Text(
                    arabic ? 'English' : 'عربي',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color:
                          kDarkMode.value ? const Color(0xFFF8FAFC) : kInk,
                    ),
                  ),
                ),
                onTap: widget.onChangeLanguage,
              ),
              const Divider(height: 1),
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
                      icon: const Icon(Icons.my_location_rounded,
                          color: kGreen, size: 20),
                      onPressed: widget.onAutoAssignGps,
                    ),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 14, color: kMuted),
                  ],
                ),
                onTap: widget.onSelectArea,
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.mark_chat_read_rounded,
                title: localized(
                    arabic, 'WhatsApp Booking Updates', 'إشعارات الواتساب'),
                subtitle: localized(
                  arabic,
                  'Instant confirmations & calendar reminders',
                  'تأكيدات فورية وتذكيرات بالمواعيد',
                ),
                trailing: const Icon(
                  Icons.check_circle_rounded,
                  color: kGreen,
                  size: 20,
                ),
                onTap: () => _showWhatsAppUpdatesModal(context, arabic),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.verified_user_outlined,
                title:
                    localized(arabic, 'Privacy & Security', 'الخصوصية والأمان'),
                subtitle: localized(
                  arabic,
                  'End-to-end booking protection & Paymob escrow',
                  'حماية كاملة للمدفوعات وحجز مؤكد',
                ),
                trailing: Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: kMuted),
                onTap: () => _showPrivacySecurityModal(context, arabic),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Sign Out & Account Deletion Buttons
        if (signedIn) ...[
          PressableScale(
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(localized(
                    arabic,
                    'Sign out of Hagzy?',
                    'تسجيل الخروج من حجزي؟',
                  )),
                  content: Text(localized(
                    arabic,
                    'You will need to sign in again to access your saved profile and bookings.',
                    'سيتعين عليك تسجيل الدخول مجدداً للوصول إلى حسابك وحجوزاتك.',
                  )),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(localized(arabic, 'Cancel', 'إلغاء')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child:
                          Text(localized(arabic, 'Sign Out', 'تسجيل الخروج')),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
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
                color: Colors.redAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded,
                      color: Colors.redAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    localized(arabic, 'Sign Out', 'تسجيل الخروج'),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Apple App Store Guideline 5.1.1(v) & Google Play Data Safety requirement
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(localized(
                            arabic,
                            'Delete Account Permanently?',
                            'حذف الحساب نهائياً؟',
                          )),
                        ),
                      ],
                    ),
                    content: Text(localized(
                      arabic,
                      'Are you sure you want to permanently delete your Hagzy account? This will erase your personal profile, phone number, and reservation history from this device and our servers. This action cannot be undone.',
                      'هل أنت متأكد من رغبتك في حذف حسابك في حجزي نهائياً؟ سيتم مسح بياناتك الشخصية ورقم الموبايل وسجل الحجوزات تماماً من هذا الجهاز وسيرفراتنا ولا يمكن التراجع عن هذا الإجراء.',
                    )),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(localized(arabic, 'Cancel', 'إلغاء')),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade800,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                            localized(arabic, 'Delete Forever', 'حذف نهائياً')),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
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
                  color: Colors.grey.shade500, size: 17),
              label: Text(
                localized(arabic, 'Delete Account & Personal Data',
                    'حذف الحساب والبيانات الشخصية'),
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12.5,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        Center(
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                color: kMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: localized(
                    arabic,
                    'Hagzy v2.4 · Made with ',
                    'حجزي v2.4 · صُنع بـ ',
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

  Future<void> _openLegalWebPage(
      BuildContext context, String path, String title) async {
    Uri uri;
    if (kIsWeb) {
      uri = Uri.base.resolve(path);
    } else {
      uri = Uri.parse('https://hagzy-api.onrender.com/$path');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localized(
              widget.arabic,
              'Opening $title...',
              'جاري فتح $title...',
            )),
          ),
        );
      }
    }
  }

  void _showLegalDocumentViewer(BuildContext context,
      {required bool arabic, required bool isPrivacy}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isPrivacy ? Icons.shield_rounded : Icons.gavel_rounded,
                      color: kGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      isPrivacy
                          ? localized(
                              arabic, 'Privacy Policy', 'سياسة الخصوصية')
                          : localized(
                              arabic, 'Terms of Service', 'شروط الاستخدام'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kInk,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                    icon: Icon(Icons.close_rounded, color: kMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isPrivacy) ...[
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '1. Commitment to Privacy & Law No. 151 of 2020',
                            '١. الالتزام بحماية البيانات وفق القانون المصري رقم ١٥١ لسنة ٢٠٢٠'),
                        body: localized(
                          arabic,
                          'Hagzy is committed to protecting your personal data in accordance with the Egyptian Personal Data Protection Law (Law No. 151 of 2020) and international consumer standards. We never sell, rent, or trade your personal information to third parties or advertisers.',
                          'تلتزم منصة حجزي التزاماً تاماً بحماية بياناتك الشخصية وحرمة حياتك الخاصة وفقاً لأحكام قانون حماية البيانات الشخصية المصري رقم ١٥١ لسنة ٢٠٢٠ والمعايير الدولية. لا نقوم إطلاقاً ببيع أو تأجير أو مشاركة بياناتك مع أي أطراف إعلانية أو جهات خارجية.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '2. Financial Security & PCI-DSS Escrow',
                            '٢. الأمان المالي وضمان الحجوزات عبر Paymob'),
                        body: localized(
                          arabic,
                          'All card, InstaPay, and mobile wallet transactions are encrypted and processed through licensed Central Bank of Egypt payment gateways (Paymob). Hagzy servers never store your credit or debit card numbers, CVV codes, or bank passwords.',
                          'تتم جميع عمليات الدفع الإلكتروني (البطاقات البنكية، إنستاباي، والمحافظ الإلكترونية) عبر بوابات دفع مرخصة من البنك المركزي المصري (Paymob) بأعلى معايير التشفير المصرفي PCI-DSS، ولا يتم تخزين أرقام بطاقاتك أو رموز الأمان على سيرفراتنا نهائياً.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '3. Right to Account Deletion',
                            '٣. الحق في الحذف الدائم والنهائي للحساب'),
                        body: localized(
                          arabic,
                          'In strict compliance with Apple App Store Guideline 5.1.1(v) and Google Play Safety policies, you can delete your account and all associated booking logs permanently from your Profile settings at any time with one click.',
                          'امتثالاً لسياسات آبل (Apple Guideline 5.1.1v) وجوجل، يتيح لك التطبيق في أي وقت ومن شاشة البروفايل مسح حسابك وسجل حجوزاتك وبياناتك الشخصية نهائياً من أجهزتك وسيرفراتنا بضغطة واحدة دون تعقيد.',
                        ),
                      ),
                    ] else ...[
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '1. Reservation Slot Hold Policy',
                            '١. ضمان حجز الموعد المؤقت (١٥ دقيقة)'),
                        body: localized(
                          arabic,
                          'Upon initiating a booking, Hagzy exclusively reserves the court or salon time slot for 15 minutes to allow payment completion. If payment is not submitted within 15 minutes, the slot is automatically released.',
                          'عند اختيار الموعد، يتم حجز الملعب أو موعد الصالون حصرياً لك لمدة ١٥ دقيقة لإتمام السداد. وفي حال عدم تأكيد السداد خلال تلك المدة يتم إلغاء الحجز تلقائياً وإتاحته لعملاء آخرين.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '2. Cancellation & Rescheduling',
                            '٢. الإلغاء وتعديل المواعيد'),
                        body: localized(
                          arabic,
                          'Free cancellation or rescheduling is permitted up to 2 hours prior to the confirmed booking time. Approved refunds are credited directly to your Hagzy Wallet or original payment method.',
                          'يحق للعميل تعديل موعد الحجز أو الإلغاء واسترداد الرصيد لمحفظة حجزي أو وسيلة الدفع الأصلية وفقاً لسياسة الإلغاء المعلنة للمكان وقبل بدء الموعد بساعتين على الأقل.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(
                            arabic,
                            '3. Venue Etiquette & Rules',
                            '٣. الالتزام بلائحة الأماكن والملاعب'),
                        body: localized(
                          arabic,
                          'Users agree to adhere to all rules, safety guidelines, and dress codes established by the venue partner. Proper athletic footwear is required on padel and football courts.',
                          'يلتزم العميل بالحضور في الموعد المحدد ومراعاة تعليمات الأمن والسلامة والزي الرياضي المناسب لملاعب البادل وكرة القدم وصالونات الحلاقة والعناية.',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kGreen,
                        side: const BorderSide(color: kGreen),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: Text(
                        localized(
                          arabic,
                          'Open Full Web Document in Browser',
                          'فتح المستند الرسمي بالمتصفح',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _openLegalWebPage(
                          context,
                          isPrivacy ? 'privacy.html' : 'terms.html',
                          isPrivacy
                              ? localized(
                                  arabic, 'Privacy Policy', 'سياسة الخصوصية')
                              : localized(
                                  arabic, 'Terms of Service', 'شروط الاستخدام'),
                        );
                      },
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

  Widget _buildLegalSection({required String title, required String body}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: kInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: TextStyle(
                fontSize: 13,
                color: kMuted,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );

  void _showPrivacySecurityModal(BuildContext context, bool arabic) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                          child: const Icon(
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
                      iconColor: kGreen,
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
                      iconColor: const Color(0xFF1E88E5),
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
                      iconColor: const Color(0xFF7B1FA2),
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
                      iconColor: const Color(0xFFE53935),
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
                            icon: const Icon(Icons.description_outlined,
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
                            icon: const Icon(Icons.gavel_rounded,
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                                  const Icon(Icons.check_circle_rounded,
                                      color: kGreen, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    localized(arabic, 'Active on this account',
                                        'مفعلة تلقائياً لحسابك'),
                                    style: const TextStyle(
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kSurfaceTint,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: kGreen),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
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
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return PressableScale(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131C31) : kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isDark ? const Color(0xFF283552) : kBorder),
          boxShadow: HagzyTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, size: 18, color: isDark ? kGreenLight : kGreen),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        color: isDark ? kGreenLight : kGreen,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
                color: isDark ? const Color(0xFFF8FAFC) : kInk,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? const Color(0xFF94A3B8) : kMuted,
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
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF19243D) : kSurfaceTint,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark ? const Color(0xFF283552) : kBorder,
                ),
              ),
              child: iconWidget ??
                  Icon(
                    icon,
                    size: 18,
                    color: isDark ? kGreenLight : kInk,
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
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: isDark ? const Color(0xFFF8FAFC) : kInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? const Color(0xFF94A3B8) : kMuted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}
