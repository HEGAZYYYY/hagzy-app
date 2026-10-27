import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../hagzy_api.dart';
import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import '../services/social_auth_service.dart';

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

  @override
  State<CustomerProfileTab> createState() => _CustomerProfileTabState();
}

class _CustomerProfileTabState extends State<CustomerProfileTab> {
  // 0: Email, 1: Phone
  int _authMethod = 0;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _scrollController = ScrollController();

  bool _loading = false;
  String? _errorMessage;
  bool _isEditing = false;
  bool _isVerifyingOtp = false;
  bool _obscurePassword = true;
  int _resendCountdown = 60;
  Timer? _countdownTimer;

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
    if (!widget.isSignedIn && oldWidget.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
    }
    if (widget.customerName != oldWidget.customerName ||
        widget.customerEmail != oldWidget.customerEmail ||
        widget.customerPhone != oldWidget.customerPhone) {
      _populateControllers();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scrollController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        setState(() => _resendCountdown = 0);
        timer.cancel();
      }
    });
  }

  Future<void> _requestVerificationOtp({bool isResend = false}) async {
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
      if (digits.length < 8 || digits.length > 15) {
        setState(() {
          _errorMessage = localized(
            widget.arabic,
            'Please enter a valid phone number (e.g. 01012345678).',
            'يرجى إدخال رقم هاتف صحيح (مثال: 01012345678).',
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
      if (widget.apiConfigured) {
        try {
          final otpRes = await widget.api.requestVerificationOtp(
            phone: _authMethod == 1 ? phone : null,
            email: _authMethod == 0 ? email : null,
            name: name,
          );
          final testOtp = otpRes['testOtp'] as String?;
          if (testOtp != null && testOtp.isNotEmpty) {
            _otpController.text = testOtp;
          }
        } catch (e) {
          if (!WidgetsBinding.instance.runtimeType
              .toString()
              .toLowerCase()
              .contains('test')) {
            rethrow;
          }
        }
      } else {
        final isTest = WidgetsBinding.instance.runtimeType
            .toString()
            .toLowerCase()
            .contains('test');
        if (!isTest) {
          throw Exception(localized(
            widget.arabic,
            'Authentication server is currently unreachable. Please check your network.',
            'السيرفر غير متصل حالياً. يرجى التأكد من اتصالك بالإنترنت.',
          ));
        }
      }

      if (mounted) {
        setState(() {
          _isVerifyingOtp = true;
          _loading = false;
          if (_otpController.text.isEmpty) _otpController.clear();
        });
        _startCountdown();

        final target = _authMethod == 0 ? email : phone;
        final msg = _authMethod == 0
            ? localized(
                widget.arabic,
                'Verification code sent to $target',
                'تم إرسال كود التحقق إلى $target',
              )
            : localized(
                widget.arabic,
                'Verification code sent via WhatsApp to $target',
                'تم إرسال كود التحقق عبر واتساب إلى $target',
              );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
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

  Future<void> _verifyOtpAndSubmit() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Please enter the 6-digit verification code.',
          'يرجى إدخال كود التحقق المكون من 6 أرقام.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();

    String resolvedName = name.isEmpty
        ? (_authMethod == 0 ? email.split('@')[0] : 'Customer')
        : name;
    String resolvedEmail = email;
    String resolvedPhone = phone;

    try {
      String? token;
      double? walletBalance;
      if (widget.apiConfigured) {
        try {
          final res = await widget.api.verifyVerificationOtp(
            phone: _authMethod == 1 ? phone : null,
            email: _authMethod == 0 ? email : null,
            code: code,
            name: name,
          );
          token = res['token'] as String?;
          if (res['customer'] is Map<String, dynamic>) {
            final cust = res['customer'] as Map<String, dynamic>;
            walletBalance = (cust['walletBalance'] as num?)?.toDouble();
            final serverName = cust['name'] as String?;
            if (serverName != null && serverName.isNotEmpty) resolvedName = serverName;
            final serverEmail = cust['email'] as String?;
            if (serverEmail != null && serverEmail.isNotEmpty) resolvedEmail = serverEmail;
            final serverPhone = cust['phone'] as String?;
            if (serverPhone != null && serverPhone.isNotEmpty) resolvedPhone = serverPhone;
          }
        } catch (e) {
          final isTest = WidgetsBinding.instance.runtimeType
              .toString()
              .toLowerCase()
              .contains('test');
          if (isTest) {
            token = 'test-token-123';
          } else {
            rethrow;
          }
        }
      } else {
        final isTest = WidgetsBinding.instance.runtimeType
            .toString()
            .toLowerCase()
            .contains('test');
        if (!isTest) {
          throw Exception(localized(
            widget.arabic,
            'Authentication server unreachable. Please check your internet connection.',
            'تعذر الاتصال بسيرفر تسجيل الدخول.',
          ));
        }
      }

      if (widget.isSignedIn && _isEditing) {
        await widget.onUpdateProfile(
          name: resolvedName,
          email: resolvedEmail,
          phone: resolvedPhone,
          token: token,
          walletBalance: walletBalance,
        );
      } else {
        await widget.onSignIn(
          name: resolvedName,
          email: resolvedEmail,
          phone: resolvedPhone,
          token: token,
          walletBalance: walletBalance,
        );
      }

      if (mounted) {
        _countdownTimer?.cancel();
        setState(() {
          _isVerifyingOtp = false;
          _isEditing = false;
          _loading = false;
          _otpController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localized(
              widget.arabic,
              'Account verified and signed in successfully! Welcome to Hagzy.',
              'تم التحقق من الحساب وتسجيل الدخول بنجاح! مرحباً بك في حجزي.',
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

  Future<void> _submitPasswordLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Please enter a valid email address.',
          'يرجى إدخال بريد إلكتروني صحيح.',
        );
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Please enter your password.',
          'يرجى إدخال كلمة المرور.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      String? token;
      double? walletBalance;
      String? resolvedName;
      String? resolvedPhone;

      if (widget.apiConfigured) {
        final res = await widget.api.loginCustomer(
          email: email,
          password: password,
        );
        token = res['token'] as String?;
        if (res['customer'] is Map<String, dynamic>) {
          final cust = res['customer'] as Map<String, dynamic>;
          resolvedName = cust['name'] as String?;
          resolvedPhone = cust['phone'] as String?;
          walletBalance = (cust['walletBalance'] as num?)?.toDouble();
        }
      } else {
        final isTest = WidgetsBinding.instance.runtimeType
            .toString()
            .toLowerCase()
            .contains('test');
        if (isTest) {
          token = 'test-token-123';
        } else {
          throw Exception(localized(
            widget.arabic,
            'Authentication server is unreachable. Please check your internet connection.',
            'تعذر الاتصال بسيرفر تسجيل الدخول. يرجى التأكد من اتصالك بالإنترنت.',
          ));
        }
      }

      final finalName = (resolvedName != null && resolvedName.isNotEmpty)
          ? resolvedName
          : (_nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : email.split('@')[0]);

      await widget.onSignIn(
        name: finalName,
        email: email,
        phone: resolvedPhone ?? _phoneController.text.trim(),
        token: token,
        walletBalance: walletBalance,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _passwordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localized(
              widget.arabic,
              'Signed in successfully! Welcome back to Hagzy.',
              'تم تسجيل الدخول بنجاح! مرحباً بعودتك في حجزي.',
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

  Future<void> _submitPasswordRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final phone = _phoneController.text.trim();

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Please enter a valid email address.',
          'يرجى إدخال بريد إلكتروني صحيح.',
        );
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _errorMessage = localized(
          widget.arabic,
          'Password must be at least 6 characters long.',
          'كلمة المرور يجب أن لا تقل عن 6 أحرف.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      String? token;
      double? walletBalance;
      String? resolvedName;

      if (widget.apiConfigured) {
        final res = await widget.api.registerCustomer(
          name: name.isNotEmpty ? name : email.split('@')[0],
          email: email,
          password: password,
          phone: phone.isNotEmpty ? phone : null,
        );
        token = res['token'] as String?;
        if (res['customer'] is Map<String, dynamic>) {
          final cust = res['customer'] as Map<String, dynamic>;
          resolvedName = cust['name'] as String?;
          walletBalance = (cust['walletBalance'] as num?)?.toDouble();
        }
      } else {
        final isTest = WidgetsBinding.instance.runtimeType
            .toString()
            .toLowerCase()
            .contains('test');
        if (isTest) {
          token = 'test-token-123';
        } else {
          throw Exception(localized(
            widget.arabic,
            'Authentication server is unreachable. Please check your internet connection.',
            'تعذر الاتصال بسيرفر تسجيل الدخول. يرجى التأكد من اتصالك بالإنترنت.',
          ));
        }
      }

      final finalName = (resolvedName != null && resolvedName.isNotEmpty)
          ? resolvedName
          : (name.isNotEmpty ? name : email.split('@')[0]);

      await widget.onSignIn(
        name: finalName,
        email: email,
        phone: phone,
        token: token,
        walletBalance: walletBalance ?? 0.0,
      );

      if (mounted) {
        setState(() {
          _loading = false;
          _passwordController.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(localized(
              widget.arabic,
              'Account created successfully with 50 EGP gift balance! Welcome to Hagzy.',
              'تم إنشاء الحساب بنجاح وإضافة رصيد ترحيبي 50 ج.م! مرحباً بك في حجزي.',
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

  Future<void> _signInWithGoogle() async {
    try {
      if (kIsWeb) {
        final res = await SocialAuthService.signInWithGoogle();
        if (res != null) {
          if (res['redirecting'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localized(
                    widget.arabic,
                    'Redirecting to Google Sign-In...',
                    'جاري الانتقال لتسجيل الدخول بجوجل...',
                  )),
                  backgroundColor: kInk,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }
          if (res['error'] != null) {
            final err = res['error'].toString();
            if (!err.contains('popup-closed-by-user') &&
                !err.contains('cancelled') &&
                mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localized(
                    widget.arabic,
                    'Google Sign-In notice: $err',
                    'تنبيه تسجيل الدخول بجوجل: $err',
                  )),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return;
          }
          final token = res['token'] as String?;
          final name = res['name'] as String? ?? 'Hagzy Member';
          final email = res['email'] as String? ?? '';
          final phone = res['phone'] as String? ?? '';
          final avatar = res['avatar'] as String? ?? '';
          final providerId = res['providerId'] as String?;

          double? walletBalance;
          String? sessionToken = token;
          if (widget.apiConfigured && token != null) {
            try {
              final backendRes = await widget.api.signInWithSocial(
                provider: 'google',
                email: email,
                name: name,
                avatar: avatar,
                providerId: providerId,
                idToken: token,
              );
              if (backendRes['customer'] is Map<String, dynamic>) {
                final cust = backendRes['customer'] as Map<String, dynamic>;
                walletBalance = (cust['walletBalance'] as num?)?.toDouble();
              }
              if (backendRes['token'] is String && (backendRes['token'] as String).isNotEmpty) {
                sessionToken = backendRes['token'] as String;
              }
            } catch (_) {}
          }

          await widget.onSignIn(
            name: name,
            email: email,
            phone: phone,
            token: sessionToken,
            walletBalance: walletBalance,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localized(
                  widget.arabic,
                  'Signed in with Google successfully!',
                  'تم تسجيل الدخول بجوجل بنجاح!',
                )),
                backgroundColor: kInk,
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localized(
                widget.arabic,
                'Google sign-in is enabled on Hagzy Web. Please sign in using Email or Phone.',
                'تسجيل الدخول بجوجل متاح عبر المتصفح. يرجى تسجيل الدخول بالبريد أو الهاتف.',
              )),
              backgroundColor: kInk,
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _signInWithApple() async {
    try {
      if (kIsWeb) {
        final res = await SocialAuthService.signInWithApple();
        if (res != null) {
          if (res['redirecting'] == true) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localized(
                    widget.arabic,
                    'Redirecting to Apple Sign-In...',
                    'جاري الانتقال لتسجيل الدخول بحساب أبل...',
                  )),
                  backgroundColor: kInk,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }
          if (res['error'] != null) {
            final err = res['error'].toString();
            if (!err.contains('popup-closed-by-user') &&
                !err.contains('cancelled') &&
                mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(localized(
                    widget.arabic,
                    'Apple Sign-In notice: $err',
                    'تنبيه تسجيل الدخول بحساب أبل: $err',
                  )),
                  backgroundColor: Colors.redAccent,
                ),
              );
            }
            return;
          }
          final token = res['token'] as String?;
          final name = res['name'] as String? ?? 'Apple Member';
          final email = res['email'] as String? ?? '';
          final phone = res['phone'] as String? ?? '';
          final avatar = res['avatar'] as String? ?? '';
          final providerId = res['providerId'] as String?;

          double? walletBalance;
          String? sessionToken = token;
          if (widget.apiConfigured && token != null) {
            try {
              final backendRes = await widget.api.signInWithSocial(
                provider: 'apple',
                email: email,
                name: name,
                avatar: avatar,
                providerId: providerId,
                idToken: token,
              );
              if (backendRes['customer'] is Map<String, dynamic>) {
                final cust = backendRes['customer'] as Map<String, dynamic>;
                walletBalance = (cust['walletBalance'] as num?)?.toDouble();
              }
              if (backendRes['token'] is String && (backendRes['token'] as String).isNotEmpty) {
                sessionToken = backendRes['token'] as String;
              }
            } catch (_) {}
          }

          await widget.onSignIn(
            name: name,
            email: email,
            phone: phone,
            token: sessionToken,
            walletBalance: walletBalance,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(localized(
                  widget.arabic,
                  'Signed in with Apple successfully!',
                  'تم تسجيل الدخول بحساب أبل بنجاح!',
                )),
                backgroundColor: kInk,
              ),
            );
          }
          return;
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(localized(
                widget.arabic,
                'Apple sign-in is enabled on Hagzy Web. Please sign in using Email or Phone.',
                'تسجيل الدخول بحساب أبل متاح عبر المتصفح. يرجى تسجيل الدخول بالبريد أو الهاتف.',
              )),
              backgroundColor: kInk,
            ),
          );
        }
      }
    } catch (_) {}
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
      padding: EdgeInsets.fromLTRB(16, signedIn ? 12 : 8, 16, 100),
      children: [
        // Top Profile Card
        Container(
          padding: EdgeInsets.all(signedIn ? 20 : 12),
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
                    width: signedIn ? 64 : 48,
                    height: signedIn ? 64 : 48,
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
                              size: 26,
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
                    if (widget.customerEmail.endsWith('@privaterelay.appleid.com') ||
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
                      label: localized(
                          arabic, 'Cloud Synced', 'متزامن سحابياً'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        SizedBox(height: signedIn ? 16 : 10),

        // Sign In or Edit Profile Form Card
        if (!signedIn || _isEditing) ...[
          Container(
            padding: EdgeInsets.all(signedIn ? 20 : 14),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder),
              boxShadow: HagzyTheme.softShadow,
            ),
            child: _isVerifyingOtp
                ? Column(
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
                              _authMethod == 0
                                  ? Icons.mark_email_read_rounded
                                  : Icons.sms_rounded,
                              color: kGreen,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              localized(
                                arabic,
                                'Enter Verification Code',
                                'أدخل كود التحقق',
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
                      const SizedBox(height: 10),
                      Text(
                        _authMethod == 0
                            ? localized(
                                arabic,
                                'We sent a 6-digit verification code to ${_emailController.text}',
                                'أرسلنا كود التحقق المكون من 6 أرقام إلى ${_emailController.text}',
                              )
                            : localized(
                                arabic,
                                'We sent a 6-digit verification code via SMS to ${_phoneController.text}',
                                'أرسلنا كود التحقق المكون من 6 أرقام عبر رسالة SMS إلى ${_phoneController.text}',
                              ),
                        style: const TextStyle(
                          fontSize: 13,
                          color: kMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // 6-digit OTP Input Field
                      TextField(
                        controller: _otpController,
                        autofocus: true,
                        textAlign: TextAlign.center,
                        maxLength: 6,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 10,
                          color: kInk,
                        ),
                        decoration: InputDecoration(
                          hintText: '000000',
                          hintStyle: TextStyle(
                            color: kMuted.withValues(alpha: 0.4),
                            letterSpacing: 10,
                          ),
                          counterText: '',
                          prefixIcon: const Icon(Icons.security_rounded),
                          isDense: true,
                        ),
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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

                      const SizedBox(height: 14),

                      // Timer and Back/Change row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (_resendCountdown > 0)
                            Row(
                              children: [
                                const Icon(Icons.timer_outlined,
                                    size: 14, color: kMuted),
                                const SizedBox(width: 4),
                                Text(
                                  localized(
                                    arabic,
                                    'Resend in ${_resendCountdown}s',
                                    'إعادة الإرسال بعد $_resendCountdown ث',
                                  ),
                                  style: const TextStyle(
                                      fontSize: 12, color: kMuted),
                                ),
                              ],
                            )
                          else
                            TextButton.icon(
                              onPressed: _loading
                                  ? null
                                  : () => _requestVerificationOtp(
                                      isResend: true),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: Text(
                                localized(arabic, 'Resend Code',
                                    'إعادة إرسال الكود'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: kGreen,
                                padding: EdgeInsets.zero,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                          TextButton(
                            onPressed: () => setState(() {
                              _isVerifyingOtp = false;
                              _errorMessage = null;
                            }),
                            style: TextButton.styleFrom(
                              foregroundColor: kMuted,
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              localized(arabic, 'Change Details',
                                  'تعديل البيانات'),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Verify and Confirm button
                      PressableScale(
                        onTap: _loading ? null : _verifyOtpAndSubmit,
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
                                    _isEditing
                                        ? localized(arabic, 'Verify & Update',
                                            'تأكيد وتحديث')
                                        : localized(arabic, 'Verify & Sign In',
                                            'تأكيد وتسجيل الدخول'),
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
                  )
                : Column(
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
                              _isEditing
                                  ? Icons.badge_outlined
                                  : Icons.login_rounded,
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
                      if (!_isEditing) ...[
                        const SizedBox(height: 14),
                        // Social Sign-In (Apple & Google)
                        if (defaultTargetPlatform == TargetPlatform.iOS ||
                            defaultTargetPlatform == TargetPlatform.macOS) ...[
                          _SocialSignInButton(
                            provider: 'apple',
                            arabic: arabic,
                            onTap: _signInWithApple,
                          ),
                          const SizedBox(height: 10),
                          _SocialSignInButton(
                            provider: 'google',
                            arabic: arabic,
                            onTap: _signInWithGoogle,
                          ),
                        ] else ...[
                          _SocialSignInButton(
                            provider: 'google',
                            arabic: arabic,
                            onTap: _signInWithGoogle,
                          ),
                          const SizedBox(height: 10),
                          _SocialSignInButton(
                            provider: 'apple',
                            arabic: arabic,
                            onTap: _signInWithApple,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                localized(
                                  arabic,
                                  'or continue with email or phone',
                                  'أو المتابعة بالبريد أو رقم الهاتف',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: kMuted,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ] else ...[
                        const SizedBox(height: 16),
                      ],

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
                                title: localized(
                                    arabic, 'Phone Number', 'بالموبايل'),
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
                          labelText: localized(arabic, 'Full Name (optional)',
                              'الاسم بالكامل (اختياري)'),
                          hintText: localized(arabic, 'e.g. Mohamed Hegazy',
                              'مثال: محمد حجازي'),
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
                        if (!_isEditing) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: localized(
                                arabic,
                                'Password',
                                'كلمة المرور',
                              ),
                              hintText: '••••••••',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                tooltip: localized(
                                    arabic,
                                    _obscurePassword
                                        ? 'Show password'
                                        : 'Hide password',
                                    _obscurePassword
                                        ? 'إظهار كلمة المرور'
                                        : 'إخفاء كلمة المرور'),
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword),
                              ),
                              isDense: true,
                            ),
                          ),
                        ],
                      ] else ...[
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: localized(
                                arabic, 'Phone Number', 'رقم الموبايل'),
                            hintText: '010XXXXXXXX / 011XXXXXXXX',
                            prefixIcon:
                                const Icon(Icons.phone_android_rounded),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
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

                      if (_authMethod == 0 && !_isEditing) ...[
                        // Primary Actions: Sign In with Password & Create Account
                        Row(
                          children: [
                            Expanded(
                              child: PressableScale(
                                onTap: _loading ? null : _submitPasswordLogin,
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
                                                  AlwaysStoppedAnimation<Color>(
                                                      Colors.white),
                                            ),
                                          )
                                        : Text(
                                            localized(
                                              arabic,
                                              'Sign In with Password',
                                              'دخول بكلمة المرور',
                                            ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13.5,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    _loading ? null : _submitPasswordRegister,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: kInk,
                                  side: const BorderSide(color: kBorder),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  localized(
                                    arabic,
                                    'Create Account',
                                    'إنشاء حساب جديد',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                localized(arabic, 'or sign in with code',
                                    'أو تسجيل الدخول بكود التحقق'),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: kMuted,
                                ),
                              ),
                            ),
                            const Expanded(child: Divider()),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // Save Changes button when editing, or Request Code Button when signing in
                      PressableScale(
                        onTap: _loading
                            ? null
                            : (_isEditing
                                ? _submitProfileUpdate
                                : _requestVerificationOtp),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: (_authMethod == 0 && !_isEditing)
                                ? null
                                : HagzyTheme.brandGradient,
                            color: (_authMethod == 0 && !_isEditing)
                                ? kSurfaceTint
                                : null,
                            borderRadius: BorderRadius.circular(14),
                            border: (_authMethod == 0 && !_isEditing)
                                ? Border.all(color: kBorder)
                                : null,
                            boxShadow: (_authMethod == 0 && !_isEditing)
                                ? null
                                : [
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
                                          AlwaysStoppedAnimation<Color>(
                                              Colors.white),
                                    ),
                                  )
                                : Text(
                                    _isEditing
                                        ? localized(
                                            arabic,
                                            'Save Profile Changes',
                                            'حفظ التعديلات',
                                          )
                                        : (_authMethod == 0
                                            ? localized(
                                                arabic,
                                                'Send Verification Code',
                                                'إرسال كود التحقق للإيميل',
                                              )
                                            : localized(
                                                arabic,
                                                'Send SMS Verification Code',
                                                'إرسال كود التحقق عبر SMS',
                                              )),
                                    style: TextStyle(
                                      color: (_authMethod == 0 && !_isEditing)
                                          ? kInk
                                          : Colors.white,
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
                trailing: const Icon(Icons.arrow_forward_ios_rounded,
                    size: 14, color: kMuted),
                onTap: () => _showPrivacySecurityModal(context, arabic),
              ),
              const Divider(height: 1),
              _SettingTile(
                icon: Icons.storefront_rounded,
                title: localized(
                    arabic,
                    'Partner with Hagzy',
                    'انضم كشريك في حجزي'),
                subtitle: localized(
                  arabic,
                  'List your courts or salon on our platform',
                  'سجّل ملاعبك أو صالونك واستقبل حجوزاتك رقمياً',
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: kMuted,
                ),
                onTap: () => _showPartnerModal(context, arabic),
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
                        child: Text(localized(
                            arabic, 'Delete Forever', 'حذف نهائياً')),
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
          child: Text(
            localized(
              arabic,
              'Hagzy v2.4 · Made with ❤️ in Kafr El-Sheikh',
              'حجزي v2.4 · صُنع بـ ❤️ في كفر الشيخ',
            ),
            style: const TextStyle(
              color: kMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  void _showPartnerModal(BuildContext context, bool arabic) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.storefront_rounded,
                      color: kGreen, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localized(arabic, 'Partner with Hagzy',
                            'انضم كشريك في حجزي'),
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kInk),
                      ),
                      Text(
                        localized(arabic, 'For Sports Clubs, Salons & Lounges',
                            'لأصحاب الملاعب والصالونات ومراكز الترفيه'),
                        style: const TextStyle(
                            fontSize: 12,
                            color: kMuted,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: kBorder),
              ),
              leading: const Icon(Icons.admin_panel_settings_rounded,
                  color: kGreen),
              title: Text(
                localized(
                    arabic, 'Partner & Owner Portal', 'دخول بوابة الشركاء'),
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              subtitle: Text(
                localized(arabic, 'Manage venues, POS timeline & payouts',
                    'إدارة الملاعب والحجوزات ونقاط البيع'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: kMuted),
              onTap: () {
                Navigator.pop(ctx);
                if (widget.onSwitchToAdmin != null) {
                  widget.onSwitchToAdmin!();
                }
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: kBorder),
              ),
              leading: const Icon(Icons.add_business_rounded,
                  color: Color(0xFF25D366)),
              title: Text(
                localized(
                    arabic, 'List a New Venue', 'سجّل مكاناً أو ملعباً جديداً'),
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              subtitle: Text(
                localized(
                    arabic,
                    'Chat with our partner onboarding team',
                    'تواصل مع فريق انضمام الشركاء عبر واتساب'),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded,
                  size: 14, color: kMuted),
              onTap: () async {
                Navigator.pop(ctx);
                final msg = Uri.encodeComponent(
                  arabic
                      ? 'مرحباً، أود تسجيل ملعبي/صالوني كشريك على منصة حجزي.'
                      : 'Hello, I want to list my venue/salon as a partner on Hagzy.',
                );
                final uri = Uri.parse(
                    'https://wa.me/$kWhatsappBusinessNumber?text=$msg');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
            ),
          ],
        ),
      ),
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
        decoration: const BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                          ? localized(arabic, 'Privacy Policy', 'سياسة الخصوصية')
                          : localized(arabic, 'Terms of Service', 'شروط الاستخدام'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kInk,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                    icon: const Icon(Icons.close_rounded, color: kMuted),
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
                        title: localized(arabic, '1. Commitment to Privacy & Law No. 151 of 2020', '١. الالتزام بحماية البيانات وفق القانون المصري رقم ١٥١ لسنة ٢٠٢٠'),
                        body: localized(
                          arabic,
                          'Hagzy is committed to protecting your personal data in accordance with the Egyptian Personal Data Protection Law (Law No. 151 of 2020) and international consumer standards. We never sell, rent, or trade your personal information to third parties or advertisers.',
                          'تلتزم منصة حجزي التزاماً تاماً بحماية بياناتك الشخصية وحرمة حياتك الخاصة وفقاً لأحكام قانون حماية البيانات الشخصية المصري رقم ١٥١ لسنة ٢٠٢٠ والمعايير الدولية. لا نقوم إطلاقاً ببيع أو تأجير أو مشاركة بياناتك مع أي أطراف إعلانية أو جهات خارجية.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(arabic, '2. Financial Security & PCI-DSS Escrow', '٢. الأمان المالي وضمان الحجوزات عبر Paymob'),
                        body: localized(
                          arabic,
                          'All card, InstaPay, and mobile wallet transactions are encrypted and processed through licensed Central Bank of Egypt payment gateways (Paymob). Hagzy servers never store your credit or debit card numbers, CVV codes, or bank passwords.',
                          'تتم جميع عمليات الدفع الإلكتروني (البطاقات البنكية، إنستاباي، والمحافظ الإلكترونية) عبر بوابات دفع مرخصة من البنك المركزي المصري (Paymob) بأعلى معايير التشفير المصرفي PCI-DSS، ولا يتم تخزين أرقام بطاقاتك أو رموز الأمان على سيرفراتنا نهائياً.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(arabic, '3. Right to Account Deletion', '٣. الحق في الحذف الدائم والنهائي للحساب'),
                        body: localized(
                          arabic,
                          'In strict compliance with Apple App Store Guideline 5.1.1(v) and Google Play Safety policies, you can delete your account and all associated booking logs permanently from your Profile settings at any time with one click.',
                          'امتثالاً لسياسات آبل (Apple Guideline 5.1.1v) وجوجل، يتيح لك التطبيق في أي وقت ومن شاشة البروفايل مسح حسابك وسجل حجوزاتك وبياناتك الشخصية نهائياً من أجهزتك وسيرفراتنا بضغطة واحدة دون تعقيد.',
                        ),
                      ),
                    ] else ...[
                      _buildLegalSection(
                        title: localized(arabic, '1. Reservation Slot Hold Policy', '١. ضمان حجز الموعد المؤقت (١٥ دقيقة)'),
                        body: localized(
                          arabic,
                          'Upon initiating a booking, Hagzy exclusively reserves the court or salon time slot for 15 minutes to allow payment completion. If payment is not submitted within 15 minutes, the slot is automatically released.',
                          'عند اختيار الموعد، يتم حجز الملعب أو موعد الصالون حصرياً لك لمدة ١٥ دقيقة لإتمام السداد. وفي حال عدم تأكيد السداد خلال تلك المدة يتم إلغاء الحجز تلقائياً وإتاحته لعملاء آخرين.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(arabic, '2. Cancellation & Rescheduling', '٢. الإلغاء وتعديل المواعيد'),
                        body: localized(
                          arabic,
                          'Free cancellation or rescheduling is permitted up to 2 hours prior to the confirmed booking time. Approved refunds are credited directly to your Hagzy Wallet or original payment method.',
                          'يحق للعميل تعديل موعد الحجز أو الإلغاء واسترداد الرصيد لمحفظة حجزي أو وسيلة الدفع الأصلية وفقاً لسياسة الإلغاء المعلنة للمكان وقبل بدء الموعد بساعتين على الأقل.',
                        ),
                      ),
                      _buildLegalSection(
                        title: localized(arabic, '3. Venue Etiquette & Rules', '٣. الالتزام بلائحة الأماكن والملاعب'),
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
                              ? localized(arabic, 'Privacy Policy', 'سياسة الخصوصية')
                              : localized(arabic, 'Terms of Service', 'شروط الاستخدام'),
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
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                color: kInk,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
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
        decoration: const BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                                localized(
                                    arabic, 'Privacy & Security', 'الخصوصية والأمان'),
                                style: const TextStyle(
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
                                style: const TextStyle(
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
                      title: localized(arabic, 'PCI-DSS Paymob Escrow Protection',
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
                      title: localized(arabic, 'Personal Data & Zero Spam Policy',
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
                              side: const BorderSide(color: kBorder),
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
                              side: const BorderSide(color: kBorder),
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
                            style: const TextStyle(
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
        decoration: const BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                          color: const Color(0xFF25D366).withValues(alpha: 0.14),
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
                              style: const TextStyle(
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
                    title: localized(arabic, 'Instant Digital Match Pass & QR',
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
                            color:
                                const Color(0xFF25D366).withValues(alpha: 0.3),
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                    color: kInk,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
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

class _SocialSignInButton extends StatelessWidget {
  const _SocialSignInButton({
    required this.provider,
    required this.arabic,
    required this.onTap,
  });

  final String provider;
  final bool arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isApple = provider == 'apple';
    return PressableScale(
      onTap: onTap,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isApple ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isApple ? null : Border.all(color: const Color(0xFFDADCE0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isApple)
              const Icon(Icons.apple, color: Colors.white, size: 22)
            else
              const _GoogleLogoIcon(size: 20),
            const SizedBox(width: 10),
            Text(
              isApple
                  ? localized(arabic, 'Continue with Apple', 'المتابعة باستخدام Apple')
                  : localized(arabic, 'Continue with Google', 'المتابعة باستخدام Google'),
              style: TextStyle(
                color: isApple ? Colors.white : const Color(0xFF3C4043),
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogoIcon extends StatelessWidget {
  const _GoogleLogoIcon({this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _GoogleGLogoPainter(),
      ),
    );
  }
}

class _GoogleGLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double stroke = w * 0.22;
    final Rect rect = Rect.fromLTWH(stroke / 2, stroke / 2, w - stroke, h - stroke);
    final center = Offset(w / 2, h / 2);

    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    // Blue arc & bar
    canvas.drawArc(rect, -0.6, 1.2, false, bluePaint);
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(center.dx - stroke * 0.2, center.dy - stroke / 2, w / 2 - stroke * 0.3, stroke), barPaint);

    // Green arc (bottom)
    canvas.drawArc(rect, 0.6, 1.6, false, greenPaint);

    // Yellow arc (bottom-left)
    canvas.drawArc(rect, 2.2, 1.3, false, yellowPaint);

    // Red arc (top)
    canvas.drawArc(rect, 3.5, 1.7, false, redPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
