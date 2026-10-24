import 'package:flutter/material.dart';

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
    required this.onUpdateProfile,
    required this.onChangeLanguage,
    required this.onViewBookings,
    required this.onSelectArea,
    required this.onAutoAssignGps,
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
  }) onSignIn;
  final Future<void> Function() onSignOut;
  final Future<void> Function({
    required String name,
    required String email,
    required String phone,
  }) onUpdateProfile;
  final VoidCallback onChangeLanguage;
  final VoidCallback onViewBookings;
  final VoidCallback onSelectArea;
  final VoidCallback onAutoAssignGps;

  @override
  State<CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<CustomerProfileTab> {
  // 0: Email, 1: Phone
  int _authMethod = 0;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
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
    if (widget.customerPhone.isNotEmpty && widget.customerEmail.isEmpty) {
      _authMethod = 1;
    }
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
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleSignInOrUpdate() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    if (_authMethod == 0) {
      if (email.isEmpty) {
        setState(() {
          _errorMessage = localized(
            widget.arabic,
            'Please enter your email address.',
            'يرجى إدخال البريد الإلكتروني.',
          );
        });
        return;
      }
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
        setState(() {
          _errorMessage = localized(
            widget.arabic,
            'Please enter a valid email address (e.g. user@example.com).',
            'يرجى إدخال بريد إلكتروني صحيح (مثال: user@example.com).',
          );
        });
        return;
      }
    } else {
      if (phone.isEmpty) {
        setState(() {
          _errorMessage = localized(
            widget.arabic,
            'Please enter your phone number.',
            'يرجى إدخال رقم الموبايل.',
          );
        });
        return;
      }
      final digits = phone.replaceAll(RegExp(r'\D'), '');
      if (digits.length < 9 || digits.length > 15) {
        setState(() {
          _errorMessage = localized(
            widget.arabic,
            'Please enter a valid Egyptian phone number (e.g. 01012345678).',
            'يرجى إدخال رقم هاتف مصري صحيح (مثال: 01012345678).',
          );
        });
        return;
      }
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      if (widget.isSignedIn && _isEditing) {
        await widget.onUpdateProfile(
          name: name.isEmpty
              ? (_authMethod == 0 ? email.split('@')[0] : 'Customer')
              : name,
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
      } else {
        await widget.onSignIn(
          name: name.isEmpty
              ? (_authMethod == 0 ? email.split('@')[0] : 'Customer')
              : name,
          email: email,
          phone: phone,
        );
        if (mounted) {
          setState(() {
            _loading = false;
            _isEditing = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localized(
                widget.arabic,
                'Signed in successfully! Welcome to Hagzy.',
                'تم تسجيل الدخول بنجاح! مرحباً بك في حجزي.',
              )),
              backgroundColor: kInk,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
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
                      child: signedIn
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
                              size: 32,
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
                                signedIn
                                    ? (widget.customerName.isNotEmpty
                                        ? widget.customerName
                                        : localized(arabic, 'Hagzy Member',
                                            'عضو حجزي'))
                                    : localized(arabic, 'Welcome to Hagzy',
                                        'أهلاً بك في حجزي'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                  color: kInk,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (signedIn) ...[
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.verified_rounded,
                                color: kGreen,
                                size: 18,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          signedIn
                              ? (widget.customerEmail.isNotEmpty
                                  ? widget.customerEmail
                                  : widget.customerPhone)
                              : localized(
                                  arabic,
                                  'Sign in to book in 1-tap & track reservations',
                                  'سجّل دخولك لحجز الملاعب والأنشطة بضغطة واحدة',
                                ),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: signedIn ? kInk : kMuted,
                            fontWeight: signedIn
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
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
                        backgroundColor: kSurfaceTint,
                        foregroundColor: kInk,
                      ),
                      icon: Icon(
                        _isEditing ? Icons.close : Icons.edit_outlined,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _isEditing = !_isEditing),
                    ),
                ],
              ),
              if (signedIn && !_isEditing) ...[
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
                    _InfoChip(
                      icon: Icons.location_on_rounded,
                      label: governorateName(widget.currentArea, arabic),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Sign In or Edit Profile Form Card
        if (!signedIn || _isEditing) ...[
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
                      child: Icon(
                        _isEditing ? Icons.badge_outlined : Icons.login_rounded,
                        color: kGreen,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _isEditing
                            ? localized(arabic, 'Edit Your Profile',
                                'تعديل بيانات حسابك')
                            : localized(
                                arabic,
                                'Sign in with Email or Phone',
                                'تسجيل الدخول بالإيميل أو الموبايل',
                              ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: kInk,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Method Switcher (Email vs Phone)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: kSurfaceTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TabButton(
                          icon: Icons.email_rounded,
                          title: localized(arabic, 'Email', 'بالإيميل'),
                          isSelected: _authMethod == 0,
                          onTap: () => setState(() {
                            _authMethod = 0;
                            _errorMessage = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _TabButton(
                          icon: Icons.phone_iphone_rounded,
                          title: localized(arabic, 'Phone Number', 'بالموبايل'),
                          isSelected: _authMethod == 1,
                          onTap: () => setState(() {
                            _authMethod = 1;
                            _errorMessage = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Name Field
                TextField(
                  controller: _nameController,
                  textDirection:
                      arabic ? TextDirection.rtl : TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: localized(
                        arabic, 'Full Name (optional)', 'الاسم بالكامل (اختياري)'),
                    hintText: localized(
                        arabic, 'e.g. Mohamed Hegazy', 'مثال: محمد حجازي'),
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),

                // Conditional Field based on Method
                if (_authMethod == 0) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: localized(arabic, 'Email Address',
                          'البريد الإلكتروني (الإيميل)'),
                      hintText: 'name@example.com',
                      prefixIcon: const Icon(Icons.email_outlined),
                      isDense: true,
                    ),
                  ),
                ] else ...[
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
                ],

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

                // Submit Button
                PressableScale(
                  onTap: _loading ? null : _handleSignInOrUpdate,
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
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              _isEditing
                                  ? localized(
                                      arabic, 'Save Changes', 'حفظ التعديلات')
                                  : localized(
                                      arabic, 'Sign In Now', 'تسجيل الدخول الآن'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
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
            color: kPanel,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder),
            boxShadow: HagzyTheme.softShadow,
          ),
          child: Column(
            children: [
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: kInk,
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
                    const Icon(Icons.arrow_forward_ios_rounded,
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
                trailing: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: kMuted),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Sign Out Button
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
                    'You will need to enter your email or phone number again to access your saved profile.',
                    'سيتعين عليك إدخال إيميلك أو رقم موبايلك مجدداً لتسجيل الدخول.',
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
                      child: Text(localized(arabic, 'Sign Out', 'تسجيل الخروج')),
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
          const SizedBox(height: 24),
        ],

        const Center(
          child: Text(
            'Hagzy v2.4 · Made with ❤️ in Egypt',
            style: TextStyle(
              color: kMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: isSelected ? HagzyTheme.softShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? kGreen : kMuted,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? kInk : kMuted,
                ),
              ),
            ],
          ),
        ),
      );
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
              style: const TextStyle(
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
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
            boxShadow: HagzyTheme.softShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 18, color: kGreen),
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
                        style: const TextStyle(
                          color: kGreen,
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
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
                  color: kInk,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: kMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: kSurfaceTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: kInk),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: kMuted,
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
