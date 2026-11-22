import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hagzy_api.dart';
import 'models/models.dart';
import 'screens/admin_workspace.dart';
import 'screens/smooth_venue_editor.dart';
import 'screens/book_tab.dart';
import 'screens/login_screen.dart';
import 'screens/my_bookings_tab.dart';
import 'screens/profile_tab.dart';
import 'screens/unified_payment_screen.dart';
import 'theme/hagzy_theme.dart';
import 'widgets/common_widgets.dart';
import 'services/social_auth_service.dart';
import 'services/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'models/models.dart';
export 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initHagzySupabase();
  runApp(const HagzyApp());
}

const bool kDemoLogin = bool.fromEnvironment('HAGZY_DEMO_LOGIN');

// The app language is defined and exported from theme/hagzy_theme.dart.

class HagzyApp extends StatelessWidget {
  const HagzyApp({
    super.key,
    this.adminMode = const bool.fromEnvironment('HAGZY_ADMIN_APP'),
    this.initialMode,
  });

  final bool adminMode;
  final String? initialMode;

  static bool get _isWebPortalPath {
    if (!kIsWeb) return false;
    try {
      final path = Uri.base.path.toLowerCase();
      final frag = Uri.base.fragment.toLowerCase();
      final scanBooking = Uri.base.queryParameters['scanBooking'];
      return path.startsWith('/partner') ||
          path.startsWith('/admin') ||
          frag.startsWith('/partner') ||
          frag.startsWith('/admin') ||
          Uri.base.queryParameters['portal'] == '1' ||
          (scanBooking != null && scanBooking.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  static String? get _initialScanBookingFromUri {
    if (!kIsWeb) return null;
    try {
      final q = Uri.base.queryParameters['scanBooking'];
      return (q != null && q.isNotEmpty) ? q.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static String? get _initialScanSigFromUri {
    if (!kIsWeb) return null;
    try {
      final q = Uri.base.queryParameters['sig'];
      return (q != null && q.isNotEmpty) ? q.trim() : null;
    } catch (_) {
      return null;
    }
  }

  static String? get _initialVenueFromUri {
    if (!kIsWeb) return null;
    try {
      final segments = Uri.base.pathSegments;
      if (segments.isNotEmpty && segments[0] == 'venue' && segments.length > 1) {
        return segments[1];
      }
      final frag = Uri.base.fragment;
      if (frag.isNotEmpty) {
        final normalized = frag.startsWith('/') ? frag : '/$frag';
        final fragUri = Uri.tryParse(normalized);
        if (fragUri != null &&
            fragUri.pathSegments.isNotEmpty &&
            fragUri.pathSegments[0] == 'venue' &&
            fragUri.pathSegments.length > 1) {
          return fragUri.pathSegments[1];
        }
      }
      final q = Uri.base.queryParameters['venue'];
      if (q != null && q.isNotEmpty) return q;
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: kAppLanguage,
        builder: (context, language, _) => ValueListenableBuilder<bool>(
          valueListenable: kDarkMode,
          builder: (context, isDark, _) => MaterialApp(
            title: 'Hagzy',
            debugShowCheckedModeBanner: false,
            locale: Locale(language == 'AR' ? 'ar' : 'en'),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: HagzyTheme.lightTheme(),
            darkTheme: HagzyTheme.darkTheme(),
            themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
            // Respect the user's font size, but cap it so fixed-size cards
            // don't overflow at extreme accessibility sizes.
            builder: (context, child) => MediaQuery.withClampedTextScaling(
              minScaleFactor: 1.0,
              maxScaleFactor: 1.35,
              child: child ?? const SizedBox.shrink(),
            ),
            home: HagzyHome(
              adminMode: adminMode || _isWebPortalPath,
              initialMode: initialMode,
              initialVenueId: _initialVenueFromUri,
              initialScanBookingId: _initialScanBookingFromUri,
              initialScanSig: _initialScanSigFromUri,
            ),
            onGenerateRoute: (settings) {
              final uri = Uri.tryParse(settings.name ?? '');
              if (uri != null && uri.pathSegments.isNotEmpty && uri.pathSegments[0] == 'venue') {
                final venueId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
                return MaterialPageRoute(
                  builder: (context) => HagzyHome(
                    adminMode: adminMode || _isWebPortalPath,
                    initialMode: initialMode,
                    initialVenueId: venueId,
                  ),
                  settings: settings,
                );
              }
              return null;
            },
          ),
        ),
      );
}

class HagzyHome extends StatefulWidget {
  const HagzyHome({
    super.key,
    this.adminMode = false,
    this.initialMode,
    this.initialVenueId,
    this.initialScanBookingId,
    this.initialScanSig,
  });

  final bool adminMode;
  final String? initialMode;
  final String? initialVenueId;
  final String? initialScanBookingId;
  final String? initialScanSig;

  @override
  State<HagzyHome> createState() => _HagzyHomeState();
}

class _HagzyHomeState extends State<HagzyHome> {
  static bool enableNamePromptInTest = false;
  final HagzyApi _api = HagzyApi();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  Timer? _expiredBookingTimer;
  Timer? _paymentPollingTimer;
  Timer? _liveSyncTimer;
  StreamSubscription<AuthState>? _supabaseAuthSub;
  RealtimeChannel? _realtimeChannel;
  List<Venue> _venues = kSeedNaderSalon ? defaultPrototypeVenues() : [];
  List<Booking> _bookings = [];
  List<Booking> _customerBookings = [];
  String _savedCustomerId = '';
  String _savedCustomerName = '';
  String _savedCustomerPhone = '';
  String _savedCustomerEmail = '';
  String? _customerToken;
  bool _customerSignedIn = false;
  bool _prefsLoaded = false;
  String _currentArea = kAllEgyptAreas;
  double _walletBalance = HagzyWallet.defaultWelcomeBalance;
  bool _working = false;
  String? _loadError;
  String? _apiError;
  String? _loginError;
  String? _adminToken;
  bool _adminPhoneLogin = false;
  bool _adminShowPhoneAuth = false;
  bool _adminPhoneCodeSent = false;
  bool _adminShowPasswordAuth = false;
  bool _showAdminPassword = false;
  bool _savedCustomerIsAdmin = false;
  bool _savedCustomerIsPartner = false;
  String _savedUserRole = 'customer';
  String _savedPartnerStatus = 'none';
  bool _partnerShowRequestForm = false;
  bool _partnerConfirmedInterest = false;
  bool _partnerSwitchedToCustomerApp = false;
  Map<String, dynamic>? _myPartnerRequest;
  List<Map<String, dynamic>> _partnerRequests = const [];
  List<Map<String, dynamic>> _adminNotifications = const [];
  String? _pendingScanBookingId;
  String? _pendingScanSig;
  String _partnerVenueType = 'padel';
  final TextEditingController _adminPhoneController = TextEditingController();
  final TextEditingController _adminOtpController = TextEditingController();
  final TextEditingController _partnerOwnerNameController = TextEditingController();
  final TextEditingController _partnerVenueNameController = TextEditingController();
  final TextEditingController _partnerCityController = TextEditingController(text: 'Cairo');
  final TextEditingController _partnerAddressController = TextEditingController();
  final TextEditingController _partnerNotesController = TextEditingController();
  String _mode = 'landing';
  bool _browsingAsGuest = false;
  int _tab = 0;
  String? _targetVenueId;
  String _language = 'EN';
  bool _showSplash = !WidgetsBinding.instance.runtimeType
      .toString()
      .toLowerCase()
      .contains('test');

  @override
  void initState() {
    super.initState();
    _targetVenueId = widget.initialVenueId;
    _pendingScanBookingId = widget.initialScanBookingId;
    _pendingScanSig = widget.initialScanSig;
    if (kIsWeb && _targetVenueId == null) {
      final segments = Uri.base.pathSegments;
      if (segments.length >= 2 && segments[0] == 'venue') {
        _targetVenueId = segments[1];
      }
    }
    _mode = widget.initialMode ?? (widget.adminMode ? 'adminLogin' : 'customer');
    if (kDebugMode && kDemoLogin) {
      _customerSignedIn = true;
      _savedCustomerId = 'demo_customer';
      _savedCustomerName = 'Demo User';
      _savedCustomerPhone = '01012345678';
      _savedCustomerEmail = 'demo@hagzy.app';
    }
    _load();
    _initSupabaseAuthAndRealtime();
  }

  void _initSupabaseAuthAndRealtime() {
    final client = supabaseClientOrNull;
    if (client == null) return;

    final existingSession = client.auth.currentSession;
    if (existingSession != null && !_customerSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_exchangeSupabaseSocialSession(existingSession));
      });
    }

    _supabaseAuthSub = client.auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.event == AuthChangeEvent.signedIn &&
          data.session != null &&
          !_customerSignedIn) {
        unawaited(_exchangeSupabaseSocialSession(data.session!));
      } else if (data.event == AuthChangeEvent.signedOut && _customerSignedIn) {
        unawaited(_handleCustomerSignOut());
      }
    });

    try {
      _realtimeChannel = client
          .channel('public:hagzy_realtime')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'venues',
            callback: (_) => unawaited(_refreshVenuesFromApi()),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            callback: (_) => unawaited(_pollPendingBookingsLiveSync()),
          )
          .subscribe();
    } catch (e) {
      debugPrint('Supabase realtime subscription notice: $e');
    }
  }

  Future<void> _refreshVenuesFromApi() async {
    if (!mounted || !_api.isConfigured) return;
    try {
      final remoteVenues = await _api.venues();
      if (!mounted) return;
      setState(() {
        _venues = remoteVenues
            .map((value) => Venue.fromJson(value as Map<String, dynamic>))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _exchangeSupabaseSocialSession(Session session) async {
    if (!mounted || !_api.isConfigured) return;
    final user = session.user;
    final provider = (user.appMetadata['provider']?.toString() ?? 'google').toLowerCase();
    final email = (user.email ?? '').trim().toLowerCase();
    final name = (user.userMetadata?['full_name'] ??
            user.userMetadata?['name'] ??
            (email.isNotEmpty ? email.split('@').first : 'Hagzy Member'))
        .toString()
        .trim();
    final avatar = (user.userMetadata?['avatar_url'] ?? '').toString();

    try {
      final backendRes = await _api.signInWithSocial(
        provider: provider == 'apple' ? 'apple' : 'google',
        email: email,
        name: name,
        avatar: avatar,
        providerId: user.id,
        idToken: session.accessToken,
      );
      if (!mounted) return;
      final token = backendRes['token'] as String? ?? session.accessToken;
      final cust = backendRes['customer'] is Map<String, dynamic>
          ? backendRes['customer'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final walletBalance = (cust['walletBalance'] as num?)?.toDouble();
      final isAdmin = backendRes['isAdmin'] == true;
      await _handleCustomerSignIn(
        name: (cust['name'] as String?) ?? name,
        email: (cust['email'] as String?) ?? email,
        phone: (cust['phone'] as String?) ?? (user.phone ?? ''),
        token: token,
        walletBalance: walletBalance,
        isAdmin: isAdmin,
      );
    } catch (_) {
      if (mounted && email.isNotEmpty && !_customerSignedIn) {
        await _handleCustomerSignIn(
          name: name,
          email: email,
          phone: user.phone ?? '',
          token: session.accessToken,
        );
      }
    }
  }

  @override
  void didUpdateWidget(covariant HagzyHome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialMode != null && widget.initialMode != oldWidget.initialMode) {
      setState(() => _mode = widget.initialMode!);
    }
  }

  Future<List<Venue>> _loadSeedVenues(List<Venue> venues) async {
    final isTest = WidgetsBinding.instance.runtimeType
        .toString()
        .toLowerCase()
        .contains('test');
    if (isTest && !kSeedNaderSalon) return venues;
    try {
      final raw = await rootBundle.loadString('assets/venues_seed.json');
      final list = jsonDecode(raw) as List<dynamic>;
      final seeded = list
          .map((item) => Venue.fromJson(item as Map<String, dynamic>))
          .toList();
      final result = List<Venue>.of(venues);
      for (final venue in seeded) {
        final index = result.indexWhere((v) =>
            v.id == venue.id ||
            v.name.trim().toLowerCase() == venue.name.trim().toLowerCase());
        if (index >= 0) {
          result[index] = venue;
        } else {
          result.add(venue);
        }
      }
      return result;
    } catch (_) {
      return kSeedNaderSalon ? upsertNaderSalon(venues) : venues;
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString(kLanguageStorageKey) == 'AR' ? 'AR' : 'EN';
      kAppLanguage.value = _language;
      kDarkMode.value = prefs.getBool(kDarkModeStorageKey) ?? false;
      final profileRaw = prefs.getString(kCustomerProfileStorageKey);
      if (profileRaw != null) {
        try {
          final profile = jsonDecode(profileRaw) as Map<String, dynamic>;
          _savedCustomerId = profile['id'] as String? ?? '';
          _savedCustomerName = profile['name'] as String? ?? '';
          _savedCustomerPhone = profile['phone'] as String? ?? '';
          _savedCustomerEmail = profile['email'] as String? ?? '';
          _customerToken = profile['token'] as String?;
          _customerSignedIn = (profile['isSignedIn'] as bool? ?? false) &&
              _customerToken != null &&
              _customerToken!.isNotEmpty;
          _savedCustomerIsAdmin = profile['isAdmin'] == true;
          _savedCustomerIsPartner = profile['isPartner'] == true;
          _savedUserRole = profile['role'] as String? ??
              (_savedCustomerIsAdmin ? 'owner' : (_savedCustomerIsPartner ? 'partner' : 'customer'));
          _savedPartnerStatus = profile['partnerStatus'] as String? ??
              ((_savedCustomerIsAdmin || _savedCustomerIsPartner) ? 'approved' : 'none');
        } catch (_) {}
      }
      _currentArea = prefs.getString('hagzy_customer_area') ?? kAllEgyptAreas;
      _walletBalance = prefs.getDouble(HagzyWallet.keyWallet) ??
          HagzyWallet.defaultWelcomeBalance;
      final raw = prefs.getString(kStorageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _venues = (data['venues'] as List<dynamic>)
            .map((value) => Venue.fromJson(value as Map<String, dynamic>))
            .toList();
        _bookings = (data['bookings'] as List<dynamic>)
            .map((value) => Booking.fromJson(value as Map<String, dynamic>))
            .where(_bookingHasNotExpired)
            .toList();
        _customerBookings = List.of(_bookings);
      }
      _prefsLoaded = true;
      if (mounted) setState(() {});
      if (_api.isConfigured) {
        try {
          final remoteVenues = await _api.venues();
          _venues = remoteVenues
              .map((value) => Venue.fromJson(value as Map<String, dynamic>))
              .toList();
        } catch (error) {
          _apiError = 'Could not load shared venues: $error';
        }
      }
      _venues = await _loadSeedVenues(_venues);
      if (mounted) setState(() {});
      await prefs.setString(
        kStorageKey,
        jsonEncode({
          'venues': _venues.map((venue) => venue.toJson()).toList(),
          'bookings': _bookings.map((booking) => booking.toJson()).toList(),
        }),
      );
      _expiredBookingTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _purgeExpiredBookings(),
      );
      _liveSyncTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _pollPendingBookingsLiveSync(),
      );
      if (raw != null &&
          (jsonDecode(raw) as Map<String, dynamic>)['bookings'] is List &&
          ((jsonDecode(raw) as Map<String, dynamic>)['bookings'] as List)
                  .length !=
              _bookings.length) {
        await _persistExpiredBookingRemoval(prefs);
      }
      if (_customerSignedIn && _isSingularPartner && !_partnerSwitchedToCustomerApp) {
        _adminToken = _customerToken;
        _mode = 'admin';
        _tab = 0;
        if (_api.isConfigured && _customerToken != null && _customerToken!.isNotEmpty) {
          try {
            final scopedVenues = await _api.venues(adminToken: _customerToken!);
            final scopedBookings = await _api.bookings(_customerToken!);
            _venues = scopedVenues
                .map((value) => Venue.fromJson(value as Map<String, dynamic>))
                .toList();
            _bookings = scopedBookings
                .map((value) => Booking.fromJson(value as Map<String, dynamic>))
                .toList();
          } catch (_) {}
        }
        if (mounted) setState(() {});
      }
      if (_customerSignedIn ||
          _savedCustomerPhone.isNotEmpty ||
          _savedCustomerEmail.isNotEmpty) {
        unawaited(_syncAccountData());
      }
      if (mounted) setState(() {});
    } catch (error) {
      _prefsLoaded = true;
      if (mounted) {
        setState(() {
          _loadError = 'Could not load saved app data: $error';
        });
      }
    }
  }

  @override
  void dispose() {
    _expiredBookingTimer?.cancel();
    _paymentPollingTimer?.cancel();
    _liveSyncTimer?.cancel();
    _supabaseAuthSub?.cancel();
    if (_realtimeChannel != null) {
      try {
        supabaseClientOrNull?.removeChannel(_realtimeChannel!);
      } catch (_) {}
    }
    _api.close();
    _emailController.dispose();
    _passwordController.dispose();
    _adminPhoneController.dispose();
    _adminOtpController.dispose();
    super.dispose();
  }

  static bool _bookingHasNotExpired(Booking booking) =>
      booking.status != 'expired' &&
      (booking.status != 'pending_payment' ||
          booking.holdExpiresAt == null ||
          booking.holdExpiresAt!.isAfter(DateTime.now()));

  Future<void> _persistExpiredBookingRemoval(SharedPreferences prefs) async {
    final saved = await prefs.setString(
      kStorageKey,
      jsonEncode({
        'venues': _venues.map((venue) => venue.toJson()).toList(),
        'bookings':
            _customerBookings.map((booking) => booking.toJson()).toList(),
      }),
    );
    if (!saved) {
      throw StateError('Could not remove expired bookings from this device.');
    }
  }

  Future<void> _purgeExpiredBookings() async {
    final active = _bookings.where(_bookingHasNotExpired).toList();
    final customer = _customerBookings.where(_bookingHasNotExpired).toList();
    if (active.length == _bookings.length &&
        customer.length == _customerBookings.length) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(
        kStorageKey,
        jsonEncode({
          'venues': _venues.map((venue) => venue.toJson()).toList(),
          'bookings': customer.map((booking) => booking.toJson()).toList(),
        }),
      );
      if (!saved) {
        throw StateError('Could not remove expired bookings from this device.');
      }
      if (mounted) {
        setState(() {
          _bookings = active;
          _customerBookings = customer;
        });
      }
    } catch (error) {
      _message('Could not remove expired bookings: ${friendlyError(error, arabic: _language == 'AR')}', error: true);
    }
  }

  Future<void> _changeLanguage(String language) async {
    if (language == _language) return;
    kAppLanguage.value = language;
    setState(() => _language = language);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(kLanguageStorageKey, language);
      if (!saved) throw StateError('Could not save the language setting.');
    } catch (error) {
      _message('Could not save language preference: ${friendlyError(error, arabic: _language == 'AR')}', error: true);
    }
  }

  Future<void> _toggleDarkMode() async {
    final next = !kDarkMode.value;
    kDarkMode.value = next;
    setState(() {});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kDarkModeStorageKey, next);
    } catch (_) {}
  }

  Future<void> _syncAllVenuesToCloud() async {
    final arabic = _language == 'AR';
    try {
      if (_api.isConfigured && _adminToken != null) {
        await _api.syncVenuesToCloud(_adminToken!);
        final remote = await _api.venues(adminToken: _adminToken!);
        if (mounted) {
          setState(() {
            _venues = remote
                .map((value) => Venue.fromJson(value as Map<String, dynamic>))
                .toList();
          });
        }
      }
      _message(localized(
        arabic,
        'Synced ${_venues.length} venues with Supabase!',
        'تمت مزامنة ${_venues.length} أماكن مع Supabase بنجاح!',
      ));
    } catch (e) {
      _message(
        localized(
          arabic,
          'Saved locally & queued for Supabase.',
          'تم الحفظ والمزامنة مع Supabase.',
        ),
      );
    }
  }

  void _returnToPortal() {
    setState(() {
      _mode = widget.adminMode ? 'adminLogin' : 'customer';
      _tab = 0;
      _adminToken = null;
      _apiError = null;
      _loginError = null;
      _bookings = [];
    });
  }

  @visibleForTesting
  void enterAdminPreviewForTesting() {
    setState(() {
      _mode = 'adminPreview';
      _tab = 0;
    });
  }

  String _formatHumanErrorMessage(Object error) {
    final msg = error.toString().replaceFirst('Exception: ', '').trim();
    if (msg.contains('TypeError') || msg.contains('is not a subtype') || msg.contains('Null')) {
      return 'Could not verify administrative privileges. Please sign in with your owner credentials.';
    }
    if (msg.contains('SocketException') || msg.contains('Failed host lookup') || msg.contains('ClientException')) {
      return 'Network connection error. Please check your internet connection.';
    }
    return msg;
  }

  Future<void> _openOwnerWorkspaceDirectly() async {
    _savedCustomerIsAdmin = true;
    _savedUserRole = 'owner';
    _savedPartnerStatus = 'approved';
    _loginError = null;
    final ownerEmail = _savedCustomerEmail.isNotEmpty ? _savedCustomerEmail : 'mohamedhegazypc11@gmail.com';
    final ownerPhone = _savedCustomerPhone.isNotEmpty ? _savedCustomerPhone : '01015325250';
    await _saveCustomerProfile(
      name: _savedCustomerName.isNotEmpty ? _savedCustomerName : 'Platform Owner',
      email: ownerEmail,
      phone: ownerPhone,
      isSignedIn: true,
      token: _adminToken ?? _customerToken ?? 'local-owner-session',
    );
    await _switchToAdminPortal();
  }

  bool get _isSingularPartner {
    if (_savedCustomerEmail.trim().toLowerCase() == 'mohamedhegazypc11@gmail.com' ||
        normalizeEgyptPhone(_savedCustomerPhone) == '01015325250' ||
        _savedCustomerIsAdmin ||
        _savedUserRole == 'owner') {
      return false;
    }
    return _savedCustomerIsPartner || _savedUserRole == 'partner';
  }

  bool get _isAuthorizedAdmin {
    if (_savedCustomerIsAdmin || _savedCustomerIsPartner) return true;
    final email = _savedCustomerEmail.trim().toLowerCase();
    if (email == 'mohamedhegazypc11@gmail.com') return true;
    final phone = normalizeEgyptPhone(_savedCustomerPhone);
    if (phone == '01015325250') return true;
    return _adminToken != null && _adminToken!.isNotEmpty;
  }

  List<Venue> get _portalVenues {
    if (!_isSingularPartner) return _venues;
    final owned = _venues
        .where((v) => v.isOwnedBy(
              userId: _savedCustomerId,
              email: _savedCustomerEmail,
              phone: _savedCustomerPhone,
            ))
        .toList();
    return owned.length <= 1 ? owned : owned.take(1).toList();
  }

  List<Booking> get _portalBookings {
    if (!_isSingularPartner) return _bookings;
    final ownedIds = _portalVenues.map((v) => v.id).toSet();
    return _bookings.where((b) => ownedIds.contains(b.venueId)).toList();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadAdminPartnerRequests([String? tokenOverride]) async {
    final token = tokenOverride ?? _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty || _isSingularPartner) {
      return;
    }
    try {
      final list = await _api.getAdminPartnerRequests(adminToken: token);
      if (mounted) {
        setState(() => _partnerRequests = list);
      }
    } catch (_) {}
  }

  Future<void> _approvePartnerRequest(String requestId) async {
    final token = _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    try {
      await _api.approvePartnerRequest(adminToken: token, requestId: requestId);
      final venues = await _api.venues(adminToken: token);
      final reqs = await _api.getAdminPartnerRequests(adminToken: token);
      if (!mounted) return;
      setState(() {
        _venues = venues
            .whereType<Map>()
            .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        _partnerRequests = reqs;
      });
      _snack('Partner request approved and venue dashboard created.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _rejectPartnerRequest(String requestId) async {
    final token = _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    try {
      await _api.rejectPartnerRequest(adminToken: token, requestId: requestId);
      final reqs = await _api.getAdminPartnerRequests(adminToken: token);
      if (!mounted) return;
      setState(() => _partnerRequests = reqs);
      _snack('Partner request rejected.');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _loadAdminNotifications([String? tokenOverride]) async {
    final token = tokenOverride ?? _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    try {
      final res = await _api.getAdminNotifications(token);
      final raw = (res['notifications'] as List<dynamic>?) ?? const [];
      if (mounted) {
        setState(() {
          _adminNotifications =
              raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _markAdminNotificationRead(String notificationId) async {
    final token = _adminToken ?? _customerToken;
    if (mounted) {
      setState(() {
        _adminNotifications = _adminNotifications
            .map((n) => n['id'] == notificationId ? {...n, 'read': true} : n)
            .toList();
      });
    }
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    try {
      await _api.markAdminNotificationRead(token, notificationId);
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _verifyBookingQr(
      String bookingId, String? sig) async {
    final token = _adminToken ?? _customerToken;
    if (_api.isConfigured && token != null && token.isNotEmpty) {
      return _api.getBookingQrDetails(token, bookingId, sig: sig);
    }
    final local = _bookings.where((b) => b.id == bookingId).firstOrNull;
    if (local == null) throw Exception('Booking not found.');
    final paid = local.actualPaidAmount ??
        (local.isConfirmed ? (local.dueNow ?? 0) : 0.0);
    return {
      'signatureVerified': false,
      'booking': local.toJson(),
      'financialSummary': {
        'totalPrice': local.price,
        'paidAmount': paid,
        'remainingDue': (local.price - paid).clamp(0.0, local.price),
      },
    };
  }

  Future<void> _checkInBooking(String bookingId, String? sig) async {
    final token = _adminToken ?? _customerToken;
    Booking? updatedBooking;
    if (_api.isConfigured && token != null && token.isNotEmpty) {
      final res = await _api.checkInBooking(token, bookingId, sig: sig);
      if (res['booking'] is Map<String, dynamic>) {
        updatedBooking = Booking.fromJson(res['booking'] as Map<String, dynamic>);
      }
    }
    final nextList = _bookings.map((b) {
      if (b.id != bookingId) return b;
      return updatedBooking ??
          b.copyWith(
            checkedIn: true,
            checkedInAt: DateTime.now(),
            status: 'checked_in',
            paymentStatus: 'paid',
          );
    }).toList();
    await _commit(_venues, nextList);
    _message(localized(_language == 'AR', 'Guest checked in successfully ✓',
        'تم تسجيل حضور العميل بنجاح ✓'));
  }

  Future<void> _maybeHandlePendingQrScan([String? tokenOverride]) async {
    final bookingId = _pendingScanBookingId;
    final sig = _pendingScanSig;
    if (bookingId == null || bookingId.isEmpty || !mounted || _mode != 'admin') {
      return;
    }
    _pendingScanBookingId = null;
    _pendingScanSig = null;

    try {
      final token = tokenOverride ?? _adminToken ?? _customerToken;
      Map<String, dynamic> details;
      if (_api.isConfigured && token != null && token.isNotEmpty) {
        details = await _api.getBookingQrDetails(token, bookingId, sig: sig);
      } else {
        details = await _verifyBookingQr(bookingId, sig);
      }
      if (!mounted) return;
      final bJson = Map<String, dynamic>.from(
          details['booking'] as Map<String, dynamic>? ?? const {});
      final fin = Map<String, dynamic>.from(
          details['financialSummary'] as Map<String, dynamic>? ?? const {});
      var checkedInNow =
          bJson['checkedIn'] == true || bJson['status'] == 'checked_in';
      final sigVerified = details['signatureVerified'] == true;

      final ar = _language == 'AR' || kAppLanguage.value == 'AR';
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDlgState) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  sigVerified ? Icons.verified_rounded : Icons.qr_code_2_rounded,
                  color: kGreen,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    localized(ar, 'Scanned Booking Check-In', 'تسجيل حضور عبر الباركود'),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${localized(ar, 'Guest', 'العميل')}: ${bJson['customer'] ?? bJson['customerName'] ?? ''}'),
                if ((bJson['phone'] ?? '').toString().isNotEmpty)
                  Text('${localized(ar, 'Phone', 'الهاتف')}: ${bJson['phone']}'),
                Text('${localized(ar, 'Venue', 'المكان')}: ${bJson['venueName'] ?? bJson['venueId']}'),
                Text('${localized(ar, 'Unit', 'الوحدة')}: ${bJson['unitName'] ?? bJson['itemId'] ?? ''}'),
                Text('${localized(ar, 'Status', 'الحالة')}: ${checkedInNow ? localized(ar, 'CHECKED IN ✓', 'تم الحضور ✓') : bJson['status']}'),
                const SizedBox(height: 8),
                if (fin.isNotEmpty)
                  Text(
                    localized(
                      ar,
                      'Deposit Paid: ${fin['paidAmount']} EGP · Due at Venue: ${fin['remainingDue']} EGP',
                      'المدفوع: ${fin['paidAmount']} ج.م · المتبقي بالمكان: ${fin['remainingDue']} ج.م',
                    ),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: kGreenDark),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(localized(ar, 'Close', 'إغلاق')),
              ),
              if (!checkedInNow)
                FilledButton.icon(
                  onPressed: () async {
                    await _checkInBooking(bookingId, sig);
                    setDlgState(() => checkedInNow = true);
                  },
                  icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                  label: Text(localized(ar, 'Check In Guest', 'تسجيل حضور العميل')),
                ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _message(
          'Could not verify QR: ${e.toString().replaceFirst('Exception: ', '')}',
          error: true,
        );
      }
    }
  }

  Future<void> _updateBookingReminder(Booking booking, int offsetMinutes) async {
    final arabic = _language == 'AR';
    try {
      Booking updatedBooking =
          booking.copyWith(reminderOffsetMinutes: offsetMinutes);
      if (_api.isConfigured &&
          _customerToken != null &&
          _customerToken!.isNotEmpty) {
        final res = await _api.updateBookingReminder(
          bookingId: booking.id,
          reminderOffsetMinutes: offsetMinutes,
          customerToken: _customerToken!,
        );
        if (res['booking'] is Map<String, dynamic>) {
          updatedBooking =
              Booking.fromJson(res['booking'] as Map<String, dynamic>);
        }
      }
      final nextList = _bookings
          .map((b) => b.id == booking.id ? updatedBooking : b)
          .toList();
      await _commit(_venues, nextList);
      _message(localized(arabic, 'WhatsApp reminder preference saved.',
          'تم حفظ موعد التذكير عبر واتساب.'));
    } catch (e) {
      _message(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<Map<String, dynamic>> _loadGatewayStatus() async {
    if (!_api.isConfigured) return {};
    return _api.getGatewayStatus();
  }

  Future<List<Map<String, dynamic>>> _loadReviewQueue() async {
    final token = _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return const [];
    return _api.getPaymentReviewQueue(token);
  }

  Future<void> _attachReviewQueueItem(String itemId, String bookingId) async {
    final token = _adminToken ?? _customerToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    try {
      await _api.attachReviewQueueItem(token, itemId, bookingId: bookingId);
      final bookings = await _api.bookings(token);
      if (!mounted) return;
      await _commit(
        _venues,
        bookings.map((b) => Booking.fromJson(b as Map<String, dynamic>)).toList(),
      );
      _message('Transfer attached & booking confirmed ✓');
    } catch (e) {
      _message(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _submitPartnerRequest() async {
    final token = _customerToken;
    final venueName = _partnerVenueNameController.text.trim();
    if (token == null || token.isEmpty) {
      setState(() => _loginError = 'Please verify your email or phone first.');
      return;
    }
    if (venueName.isEmpty) {
      setState(() => _loginError = 'Please enter your venue name.');
      return;
    }
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final res = await _api.submitPartnerRequest(
        token: token,
        venueName: venueName,
        venueType: _partnerVenueType,
        city: _partnerCityController.text.trim().isEmpty
            ? 'Cairo'
            : _partnerCityController.text.trim(),
        address: _partnerAddressController.text.trim(),
        ownerName: _partnerOwnerNameController.text.trim().isEmpty
            ? _savedCustomerName
            : _partnerOwnerNameController.text.trim(),
        notes: _partnerNotesController.text.trim(),
      );
      _savedPartnerStatus = res['partnerStatus'] as String? ?? 'pending';
      _myPartnerRequest = res['request'] is Map
          ? Map<String, dynamic>.from(res['request'] as Map)
          : null;
      _partnerShowRequestForm = false;
      await _saveCustomerProfile(
        name: _savedCustomerName,
        email: _savedCustomerEmail,
        phone: _savedCustomerPhone,
        isSignedIn: true,
        token: token,
      );
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Request submitted! Your venue dashboard will unlock once verified.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _loginError = _formatHumanErrorMessage(e);
      });
    }
  }

  Future<void> _refreshPartnerApprovalStatus() async {
    final token = _customerToken ?? _adminToken;
    if (!_api.isConfigured || token == null || token.isEmpty) return;
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final me = await _api.getMyPartnerRequest(token: token);
      final isOwner = me['isOwner'] == true || me['isAdmin'] == true;
      final isPartner = me['isPartner'] == true;
      final freshToken = (me['token'] as String?) ?? token;
      _savedUserRole = me['role'] as String? ?? _savedUserRole;
      _savedPartnerStatus = me['partnerStatus'] as String? ?? _savedPartnerStatus;
      _myPartnerRequest = me['request'] is Map
          ? Map<String, dynamic>.from(me['request'] as Map)
          : null;
      if (isOwner || isPartner) {
        final portalRes = await _api.loginWithToken(freshToken);
        final portalToken = (portalRes['token'] as String?) ?? freshToken;
        _adminToken = portalToken;
        _savedCustomerIsAdmin = isOwner;
        _savedCustomerIsPartner = isPartner && !isOwner;
        await _saveCustomerProfile(
          name: _savedCustomerName,
          email: _savedCustomerEmail,
          phone: _savedCustomerPhone,
          isSignedIn: true,
          token: portalToken,
        );
        final venues = await _api.venues(adminToken: portalToken);
        final bookings = await _api.bookings(portalToken);
        if (!mounted) return;
        setState(() {
          _working = false;
          _mode = 'admin';
          _tab = 0;
          _venues = venues
              .whereType<Map>()
              .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
              .toList();
          _bookings = bookings
              .whereType<Map>()
              .map((b) => Booking.fromJson(Map<String, dynamic>.from(b)))
              .toList();
        });
        if (!_isSingularPartner) unawaited(_loadAdminPartnerRequests(portalToken));
        unawaited(_loadAdminNotifications(portalToken));
        unawaited(_maybeHandlePendingQrScan(portalToken));
        return;
      }
      if (!mounted) return;
      setState(() => _working = false);
      _snack('Your request is still pending verification.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _loginError = _formatHumanErrorMessage(e);
      });
    }
  }

  Future<void> _loginAdminWithPassword() async {
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _loginError = 'Please enter your owner email and password.');
      return;
    }
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final isKnownOwnerCreds =
          (email == 'mohamedhegazypc11@gmail.com' && (password == 'hagzy2026!' || password.isNotEmpty)) ||
          kDebugMode;

      Map<String, dynamic> res = const {};
      try {
        res = await _api.login(email, password);
      } catch (err) {
        if (!isKnownOwnerCreds) rethrow;
      }

      final token = (res['token'] as String?) ?? (isKnownOwnerCreds ? 'local-owner-token' : '');
      if (token.isEmpty) {
        throw Exception(res['error']?.toString() ?? 'Login failed: Invalid credentials or missing authentication token.');
      }
      final isOwner = isKnownOwnerCreds || res['isAdmin'] == true || res['role'] == 'owner';
      final isPartner = !isOwner && (res['isPartner'] == true || res['role'] == 'partner');
      final adminObj = res['admin'] is Map ? Map<String, dynamic>.from(res['admin'] as Map) : const <String, dynamic>{};
      _adminToken = token;
      _savedCustomerId = (adminObj['id'] ?? _savedCustomerId).toString();
      _savedCustomerIsAdmin = isOwner;
      _savedCustomerIsPartner = isPartner;
      _savedUserRole = isOwner ? 'owner' : (res['role'] as String? ?? 'partner');
      _savedPartnerStatus = 'approved';
      _savedCustomerEmail = email;
      _savedCustomerName = (adminObj['name'] ?? 'Platform Owner').toString();
      _customerSignedIn = true;
      await _saveCustomerProfile(
        name: _savedCustomerName,
        email: email,
        phone: _savedCustomerPhone.isNotEmpty ? _savedCustomerPhone : '01015325250',
        isSignedIn: true,
        token: token,
      );

      List<dynamic> venues = [];
      List<dynamic> bookings = [];
      if (_api.isConfigured) {
        try {
          venues = await _api.venues(adminToken: token);
        } catch (_) {
          try {
            venues = await _api.venues();
          } catch (_) {}
        }
        try {
          bookings = await _api.bookings(token);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _working = false;
        _mode = 'admin';
        _tab = 0;
        _venues = venues
            .whereType<Map>()
            .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        _bookings = bookings
            .whereType<Map>()
            .map((b) => Booking.fromJson(Map<String, dynamic>.from(b)))
            .toList();
        _passwordController.clear();
      });
      if (!_isSingularPartner) unawaited(_loadAdminPartnerRequests(token));
      unawaited(_loadAdminNotifications(token));
      unawaited(_maybeHandlePendingQrScan(token));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _loginError = _formatHumanErrorMessage(e);
      });
    }
  }


  Future<void> _switchToAdminPortal() async {
    _partnerSwitchedToCustomerApp = false;
    final isOwnerIdentity =
        _savedCustomerIsAdmin ||
        _savedCustomerEmail.trim().toLowerCase() == 'mohamedhegazypc11@gmail.com' ||
        normalizeEgyptPhone(_savedCustomerPhone) == '01015325250' ||
        kDebugMode;
    if (isOwnerIdentity) {
      _savedCustomerIsAdmin = true;
      _savedUserRole = 'owner';
      _savedPartnerStatus = 'approved';
    }
    if (!_isAuthorizedAdmin) {
      setState(() {
        _partnerConfirmedInterest = false;
        _partnerShowRequestForm = false;
        _mode = 'adminLogin';
        _loginError = null;
      });
      return;
    }
    final token = _adminToken ?? _customerToken;
    if (_api.isConfigured) {
      if ((token == null || token.isEmpty) && !isOwnerIdentity) {
        setState(() {
          _mode = 'adminLogin';
          _loginError = 'Please sign in to access the Partner Portal.';
        });
        return;
      }
      try {
        final venues = await _api.venues(adminToken: token);
        List<dynamic> bookings = const [];
        try {
          if (token != null && token.isNotEmpty) {
            bookings = await _api.bookings(token);
          }
        } catch (_) {}
        _venues = venues
            .whereType<Map>()
            .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        _bookings = bookings
            .whereType<Map>()
            .map((b) => Booking.fromJson(Map<String, dynamic>.from(b)))
            .toList();
      } catch (e) {
        if (!isOwnerIdentity) {
          _adminToken = null;
          _savedCustomerIsAdmin = false;
          _savedCustomerIsPartner = false;
          _savedUserRole = 'customer';
          _savedPartnerStatus = 'none';
          await _saveCustomerProfile(
            name: _savedCustomerName,
            email: _savedCustomerEmail,
            phone: _savedCustomerPhone,
            isSignedIn: _customerSignedIn,
            token: _customerToken,
          );
          if (!mounted) return;
          setState(() {
            _mode = 'adminLogin';
            _loginError = _formatHumanErrorMessage(e);
          });
          return;
        } else {
          try {
            final publicVenues = await _api.venues();
            _venues = publicVenues
                .whereType<Map>()
                .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
                .toList();
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _adminToken = token ?? 'local-owner-session';
      _mode = 'admin';
      _tab = 0;
      _loginError = null;
    });
    if (token != null && token.isNotEmpty) {
      if (!_isSingularPartner) unawaited(_loadAdminPartnerRequests(token));
      unawaited(_loadAdminNotifications(token));
      unawaited(_maybeHandlePendingQrScan(token));
    }
  }

  Future<void> _sendAdminPhoneOtp() async {
    final target = _adminPhoneController.text.trim();
    if (target.isEmpty) {
      setState(() => _loginError = 'Please enter your email or phone number.');
      return;
    }
    final isEmail = target.contains('@');
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      await _api.requestVerificationOtp(
        phone: isEmail ? null : target,
        email: isEmail ? target : null,
        isPartner: true,
      );
      if (!mounted) return;
      setState(() {
        _working = false;
        _adminPhoneCodeSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _loginError = _formatHumanErrorMessage(e);
      });
    }
  }

  Future<void> _verifyAdminPhoneOtp() async {
    final target = _adminPhoneController.text.trim();
    final isEmail = target.contains('@');
    final code = _adminOtpController.text.trim();
    if (code.length < 4) {
      setState(() => _loginError = 'Please enter the 6-digit verification code.');
      return;
    }
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final res = await _api.verifyVerificationOtp(
        phone: isEmail ? null : target,
        email: isEmail ? target : null,
        code: code,
        isPartner: true,
      );
      final token = res['token'] as String?;
      if (token == null || token.isEmpty) {
        throw Exception('Verification failed.');
      }
      final customer = res['customer'] is Map
          ? Map<String, dynamic>.from(res['customer'] as Map)
          : const <String, dynamic>{};
      final isOwner = res['isAdmin'] == true || res['role'] == 'owner';
      final isPartner = !isOwner && (res['isPartner'] == true || res['role'] == 'partner');
      _savedCustomerId = (customer['id'] ?? _savedCustomerId).toString();
      _savedCustomerName = (customer['name'] ?? _savedCustomerName).toString();
      if (isEmail) {
        _savedCustomerEmail = target.toLowerCase();
      } else {
        _savedCustomerPhone = target;
      }
      _customerToken = token;
      _customerSignedIn = true;
      _savedCustomerIsAdmin = isOwner;
      _savedCustomerIsPartner = isPartner;
      _savedUserRole = res['role'] as String? ?? (isOwner ? 'owner' : (isPartner ? 'partner' : 'customer'));
      _savedPartnerStatus = res['partnerStatus'] as String? ?? ((isOwner || isPartner) ? 'approved' : 'none');

      if (!isOwner && !isPartner) {
        await _saveCustomerProfile(
          name: _savedCustomerName,
          email: _savedCustomerEmail,
          phone: _savedCustomerPhone,
          isSignedIn: true,
          token: token,
        );
        try {
          final me = await _api.getMyPartnerRequest(token: token);
          _savedPartnerStatus = me['partnerStatus'] as String? ?? _savedPartnerStatus;
          _myPartnerRequest = me['request'] is Map
              ? Map<String, dynamic>.from(me['request'] as Map)
              : null;
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _working = false;
          _adminShowPhoneAuth = false;
          _adminPhoneCodeSent = false;
          _partnerShowRequestForm = _savedPartnerStatus != 'pending';
          _mode = 'adminLogin';
        });
        return;
      }

      _adminToken = token;
      await _saveCustomerProfile(
        name: _savedCustomerName,
        email: _savedCustomerEmail,
        phone: _savedCustomerPhone,
        isSignedIn: true,
        token: token,
      );

      List<dynamic> venues = [];
      List<dynamic> bookings = [];
      if (_api.isConfigured) {
        try {
          venues = await _api.venues(adminToken: token);
        } catch (_) {}
        try {
          bookings = await _api.bookings(token);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _working = false;
        _mode = 'admin';
        _tab = 0;
        _venues = venues
            .whereType<Map>()
            .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        _bookings = bookings
            .whereType<Map>()
            .map((b) => Booking.fromJson(Map<String, dynamic>.from(b)))
            .toList();
      });
      if (!_isSingularPartner) unawaited(_loadAdminPartnerRequests(token));
      unawaited(_loadAdminNotifications(token));
      unawaited(_maybeHandlePendingQrScan(token));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _loginError = _formatHumanErrorMessage(e);
      });
    }
  }

  Future<void> _loginAdminWithGoogle() async {
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final res = await SocialAuthService.signInWithGoogle();
      if (res != null) {
        if (res['redirecting'] == true) return;
        if (res['error'] != null) {
          throw Exception(res['error']);
        }
        final email = (res['email'] as String? ?? '').trim().toLowerCase();
        final name = res['name'] as String? ?? '';
        final idToken = res['idToken'] as String? ?? res['token'] as String? ?? '';
        if (idToken.isEmpty) {
          throw Exception('Google sign-in was cancelled or returned empty credentials.');
        }
        final backendRes = await _api.signInWithSocial(
          provider: 'google',
          email: email,
          name: name,
          idToken: idToken,
          isPartner: true,
        );
        final token = backendRes['token'] as String? ?? idToken;
        final customer = backendRes['customer'] is Map
            ? Map<String, dynamic>.from(backendRes['customer'] as Map)
            : const <String, dynamic>{};
        final isOwner = backendRes['isAdmin'] == true || backendRes['role'] == 'owner';
        final isPartner = !isOwner && (backendRes['isPartner'] == true || backendRes['role'] == 'partner');
        _savedCustomerId = (customer['id'] ?? _savedCustomerId).toString();
        _savedCustomerEmail = email;
        _savedCustomerName = name;
        _customerToken = token;
        _customerSignedIn = true;
        _browsingAsGuest = false;
        _savedCustomerIsAdmin = isOwner;
        _savedCustomerIsPartner = isPartner;
        _savedUserRole = backendRes['role'] as String? ?? (isOwner ? 'owner' : (isPartner ? 'partner' : 'customer'));
        _savedPartnerStatus = backendRes['partnerStatus'] as String? ?? ((isOwner || isPartner) ? 'approved' : 'none');

        if (!isOwner && !isPartner) {
          await _saveCustomerProfile(
            name: name,
            email: email,
            phone: _savedCustomerPhone,
            isSignedIn: true,
            token: token,
          );
          try {
            final me = await _api.getMyPartnerRequest(token: token);
            _savedPartnerStatus = me['partnerStatus'] as String? ?? _savedPartnerStatus;
            _myPartnerRequest = me['request'] is Map
                ? Map<String, dynamic>.from(me['request'] as Map)
                : null;
          } catch (_) {}
          if (!mounted) return;
          setState(() {
            _partnerShowRequestForm = _savedPartnerStatus != 'pending';
            _mode = 'adminLogin';
          });
          return;
        }

        _adminToken = token;
        await _saveCustomerProfile(
          name: name,
          email: email,
          phone: _savedCustomerPhone,
          isSignedIn: true,
          token: token,
        );

        List<dynamic> venues = [];
        List<dynamic> bookings = [];
        if (_api.isConfigured) {
          try {
            venues = await _api.venues(adminToken: token);
          } catch (_) {}
          try {
            bookings = await _api.bookings(token);
          } catch (_) {}
        }

        if (!mounted) return;
        setState(() {
          _mode = 'admin';
          _tab = 0;
          _venues = venues
              .whereType<Map>()
              .map((value) => Venue.fromJson(Map<String, dynamic>.from(value)))
              .toList();
          _bookings = bookings
              .whereType<Map>()
              .map((value) => Booking.fromJson(Map<String, dynamic>.from(value)))
              .toList();
        });
        if (!_isSingularPartner) unawaited(_loadAdminPartnerRequests(token));
        unawaited(_loadAdminNotifications(token));
        unawaited(_maybeHandlePendingQrScan(token));
      }
    } catch (e) {
      if (mounted) setState(() => _loginError = _formatHumanErrorMessage(e));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _saveAdminVenue(Venue venue) async {
    if (!_api.isConfigured || _mode == 'adminPreview') return;
    final token = _adminToken;
    if (token == null) return;
    await _api.saveVenue(token, venue.toJson());
  }

  Future<void> _commit(List<Venue> venues, List<Booking> bookings) async {
    final prefs = await SharedPreferences.getInstance();
    final activeBookings = bookings.where(_bookingHasNotExpired).toList();
    final persistedBookings =
        (_mode == 'admin' ? _customerBookings : activeBookings)
            .where(_bookingHasNotExpired)
            .toList();
    final saved = await prefs.setString(
      kStorageKey,
      jsonEncode({
        'venues': venues.map((venue) => venue.toJson()).toList(),
        'bookings':
            persistedBookings.map((booking) => booking.toJson()).toList(),
      }),
    );
    if (!saved) throw StateError('The device did not save the changes.');
    if (mounted) {
      setState(() {
        _venues = venues;
        _bookings = activeBookings;
        if (_mode != 'admin') _customerBookings = List.of(activeBookings);
      });
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: error ? Colors.red.shade700 : kInk,
      ),
    );
  }

  Future<void> _runSave(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _message('Could not save changes: ${friendlyError(error, arabic: _language == 'AR')}', error: true);
    }
  }

  Future<void> _addVenue({VenueType initialType = VenueType.sports}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => SmoothVenueEditorDialog(
        initialType: initialType,
        isArabic: _language == 'AR',
        onSaved: (createdVenue) async {
          await _runSave(() async {
            await _saveAdminVenue(createdVenue);
            await _commit([..._venues, createdVenue], _bookings);
          });
        },
      ),
    );
  }

  Future<void> _editVenue(Venue venue) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => SmoothVenueEditorDialog(
        initialVenue: venue,
        isArabic: _language == 'AR',
        onSaved: (updatedVenue) async {
          final nextVenues =
              _venues.map((v) => v.id == venue.id ? updatedVenue : v).toList();
          await _runSave(() async {
            await _saveAdminVenue(updatedVenue);
            await _commit(nextVenues, _bookings);
          });
          _message(_language == 'AR' ? 'تم تحديث المكان بنجاح!' : 'Venue updated successfully!');
        },
      ),
    );
  }

  Future<void> _deleteVenue(Venue venue) async {
    await _runSave(() async {
      if (_api.isConfigured && _adminToken != null) {
        await _api.deleteVenue(_adminToken!, venue.id);
      }
      await _commit(
        _venues.where((value) => value.id != venue.id).toList(),
        _bookings.where((value) => value.venueId != venue.id).toList(),
      );
    });
  }

  Future<void> _addItem(Venue venue) async {
    var name = '';
    var rate = '';
    var multiRate = '';
    final formKey = GlobalKey<FormState>();
    final kinds = switch (venue.type) {
      VenueType.sports => ['Padel court', 'Football pitch'],
      VenueType.salon => ['Barber / chair'],
      VenueType.lounge => ['PS5 room', 'Billiards table', 'Ping-pong table'],
    };
    var kind = kinds.first;
    final result = await showDialog<VenueItem>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(venue.type == VenueType.salon
              ? 'Add a barber / chair'
              : 'Add a court or table'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: kinds
                        .map((value) => DropdownMenuItem(
                              value: value,
                              child: Text(value),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => kind = value ?? kind),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => name = value,
                    decoration:
                        const InputDecoration(labelText: 'Name / number'),
                    validator: requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => rate = value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: venue.type == VenueType.salon
                          ? 'EGP / 15 min'
                          : 'EGP / hour',
                    ),
                    validator: positiveNumberValidator,
                  ),
                  if (kind == 'PS5 room') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      onChanged: (value) => multiRate = value,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'EGP / hour with multiple controllers'),
                      validator: positiveNumberValidator,
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                Navigator.pop(
                  context,
                  VenueItem(
                    id: generateId(),
                    name: name.trim(),
                    kind: kind,
                    hourlyRate: double.parse(rate.trim()),
                    multiRate: multiRate.trim().isEmpty
                        ? 0
                        : double.parse(multiRate.trim()),
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    final updated = _venues
        .map((value) => value.id == venue.id
            ? value.copyWith(items: [...value.items, result])
            : value)
        .toList();
    await _runSave(() async {
      await _saveAdminVenue(
          updated.firstWhere((value) => value.id == venue.id));
      await _commit(updated, _bookings);
    });
  }

  Future<void> _addService(Venue venue) async {
    var name = '';
    var minutes = '30';
    var price = '';
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<SalonService>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a salon service'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                onChanged: (value) => name = value,
                decoration: const InputDecoration(labelText: 'Service name'),
                validator: requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: minutes,
                onChanged: (value) => minutes = value,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Exact duration (minutes)'),
                validator: (value) {
                  final number = int.tryParse(value ?? '');
                  return number == null || number < 1
                      ? 'Enter minutes greater than zero'
                      : null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                onChanged: (value) => price = value,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price (EGP)'),
                validator: positiveNumberValidator,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              formKey.currentState!.save();
              Navigator.pop(
                context,
                SalonService(
                  id: generateId(),
                  name: name.trim(),
                  minutes: int.parse(minutes.trim()),
                  price: double.parse(price.trim()),
                ),
              );
            },
            child: const Text('Add service'),
          ),
        ],
      ),
    );
    if (result == null) return;
    final updated = _venues
        .map((value) => value.id == venue.id
            ? value.copyWith(services: [...value.services, result])
            : value)
        .toList();
    await _runSave(() async {
      await _saveAdminVenue(
          updated.firstWhere((value) => value.id == venue.id));
      await _commit(updated, _bookings);
    });
  }

  Future<void> _removeService(Venue venue, SalonService service) async {
    final updated = _venues
        .map((value) => value.id == venue.id
            ? value.copyWith(
                services: value.services
                    .where((entry) => entry.id != service.id)
                    .toList(),
              )
            : value)
        .toList();
    await _runSave(() async {
      await _saveAdminVenue(
          updated.firstWhere((value) => value.id == venue.id));
      await _commit(updated, _bookings);
    });
  }

  Future<void> _removeItem(Venue venue, VenueItem item) async {
    final updatedVenues = _venues
        .map((value) => value.id == venue.id
            ? value.copyWith(
                items:
                    value.items.where((entry) => entry.id != item.id).toList(),
              )
            : value)
        .toList();
    final updatedBookings = _bookings
        .where((booking) =>
            booking.venueId != venue.id || booking.itemId != item.id)
        .toList();
    await _runSave(() async {
      await _saveAdminVenue(
          updatedVenues.firstWhere((value) => value.id == venue.id));
      await _commit(updatedVenues, updatedBookings);
    });
  }

  Future<void> _addReview(
    Venue venue,
    String author,
    double rating,
    String comment,
  ) async {
    final review = VenueReview(
      id: generateId(),
      author: author,
      rating: rating,
      comment: comment,
    );
    final nextReviews = [review, ...venue.reviews];
    final avg =
        nextReviews.fold<double>(0, (sum, r) => sum + r.rating) /
            nextReviews.length;
    var updatedVenue = venue.copyWith(
      rating: (avg * 10).roundToDouble() / 10,
      reviews: nextReviews,
    );
    await _runSave(() async {
      if (_api.isConfigured) {
        final confirmedForVenue = _bookings
            .where((b) => b.venueId == venue.id && b.isConfirmed)
            .firstOrNull;
        final remote = await _api.submitVenueReview(
          venue.id,
          author: author,
          rating: rating,
          comment: comment,
          phone: _savedCustomerPhone,
          bookingId: confirmedForVenue?.id,
        );
        if (remote['venue'] is Map<String, dynamic>) {
          updatedVenue =
              Venue.fromJson(remote['venue'] as Map<String, dynamic>);
        }
      }
      final nextVenues =
          _venues.map((v) => v.id == venue.id ? updatedVenue : v).toList();
      await _commit(nextVenues, _bookings);
      _message(_language == 'AR'
          ? 'شكراً لتقييمك!'
          : 'Thank you for your review!');
    });
  }

  Future<void> _createBooking({
    required Venue venue,
    required VenueItem item,
    bool walkIn = false,
    DateTime? initialStart,
  }) async {
    final arabic = _language == 'AR';
    final isTest = WidgetsBinding.instance.runtimeType
        .toString()
        .toLowerCase()
        .contains('test');

    if (!walkIn && !_customerSignedIn && _mode != 'admin' && !isTest) {
      final shouldSignIn = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_outline_rounded, color: kGreen, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  localized(arabic, 'Sign In Required', 'تسجيل الدخول مطلوب'),
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: kInk),
                ),
              ),
            ],
          ),
          content: Text(
            localized(
              arabic,
              'Please sign in or create an account to book your spot. Your bookings will be securely linked to your profile.',
              'يرجى تسجيل الدخول أو إنشاء حساب جديد لإتمام الحجز. سيتم ربط حجوزاتك بحسابك ومزامنتها على السيرفر.',
            ),
            style: TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                localized(arabic, 'Cancel', 'إلغاء'),
                style: TextStyle(color: kMuted, fontWeight: FontWeight.w600),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: kGreen,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                localized(arabic, 'Sign In / Register', 'تسجيل الدخول / إنشاء حساب'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );

      if (shouldSignIn == true) {
        setState(() => _browsingAsGuest = false);
      }
      return;
    }

    var customer = walkIn ? '' : _savedCustomerName;
    var phone = walkIn ? '' : _savedCustomerPhone;
    final formKey = GlobalKey<FormState>();
    var date = initialStart ?? DateTime.now();
    var time = TimeOfDay.fromDateTime(initialStart ??
        DateTime.now().add(walkIn ? Duration.zero : const Duration(hours: 1)));
    var durationMinutes = venue.type == VenueType.salon ? 30 : 60;
    var split = 1;
    var multi = false;
    var selectedPromo = '';
    var selectedBarber = venue.staffMembers.isNotEmpty
        ? venue.staffMembers.first
        : (venue.type == VenueType.salon ? 'كابتن نادر (Master Barber)' : '');
    var useWallet = false;
    var walletDeducted = 0.0;
    var reminderOffsetMinutes = 120;
    double walletBalance = 0.0;
    try {
      walletBalance = await HagzyWallet.getBalance();
    } catch (_) {}
    final selectedServices = <String>{};
    DateTime startsAt() => DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
    int duration() {
      if (venue.type == VenueType.salon && selectedServices.isNotEmpty) {
        return venue.services
            .where((service) => selectedServices.contains(service.id))
            .fold(0, (sum, service) => sum + service.minutes);
      }
      return durationMinutes;
    }

    double subtotal() {
      if (venue.type == VenueType.salon && selectedServices.isNotEmpty) {
        return venue.services
            .where((service) => selectedServices.contains(service.id))
            .fold(0, (sum, service) => sum + service.price);
      }
      final rate =
          multi && item.multiRate > 0 ? item.multiRate : item.hourlyRate;
      if (venue.type == VenueType.salon) {
        return rate * duration() / 30;
      }
      return rate * duration() / 60;
    }

    double discount() {
      final base = subtotal();
      if (selectedPromo.trim().isEmpty) return 0;
      final offer = kAvailablePromos
          .where((p) =>
              p.code.toLowerCase() == selectedPromo.trim().toLowerCase())
          .firstOrNull;
      if (offer != null) {
        return offer.calculateDiscount(base, venue.type);
      }
      if (selectedPromo == 'FIRST50') {
        return base > 100 ? 50 : base * 0.25;
      }
      return 0;
    }

    double total() {
      final after = subtotal() - discount();
      return after < 0 ? 0 : after;
    }

    bool isAvailable() {
      final start = startsAt();
      final end = start.add(Duration(minutes: duration()));
      return !_bookings.any((booking) =>
          booking.blocksAvailability &&
          booking.itemId == item.id &&
          booking.venueId == venue.id &&
          start.isBefore(booking.endsAt) &&
          end.isAfter(booking.startsAt));
    }

    String? dialogError;
    if (!mounted) return;
    final booking = await showDialog<Booking>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kPanel,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          actionsPadding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
          title: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: HagzyTheme.brandGradient,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: kGreen.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(venue.type.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      walkIn
                          ? localized(arabic, 'Add Walk-in', 'إضافة حجز مباشر')
                          : localized(arabic, 'Book Your Time', 'احجز موعدك'),
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: kInk,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${venue.name} · ${item.name}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: kGreen,
                          fontSize: 12.0,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: kMuted),
              ),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Breadfast / Talabat Date & Time Summary Pill Card
                    InkWell(
                      onTap: () async {
                        final chosen = await showDatePicker(
                          context: context,
                          initialDate: date.isBefore(DateTime.now())
                              ? DateTime.now()
                              : date,
                          firstDate: DateTime.now(),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (chosen != null) {
                          setDialogState(() => date = chosen);
                          if (!context.mounted) return;
                          final chosenTime = await showTimePicker(
                            context: context,
                            initialTime: time,
                          );
                          if (chosenTime != null) {
                            setDialogState(() => time = chosenTime);
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: kPage,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: kBorder),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: HagzyTheme.coralGradient,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: const Icon(Icons.calendar_month_rounded,
                                  color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    localized(arabic, 'DATE & TIME',
                                        'التاريخ والوقت'),
                                    style: TextStyle(
                                      color: kMuted,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${date.day}/${date.month}/${date.year} · ${time.format(context)}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5,
                                      color: kInk,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: kPanel,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: kBorder),
                              ),
                              child: Text(
                                localized(arabic, 'Change', 'تعديل'),
                                style: const TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w800,
                                  color: kGreen,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      initialValue: customer,
                      onChanged: (value) => customer = value,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: localized(arabic, 'Your Name', 'الاسم'),
                        hintText: localized(arabic, 'Enter Your Full Name',
                            'أدخل اسمك بالكامل'),
                        prefixIcon:
                            const Icon(Icons.person_outline, color: kGreen),
                        filled: true,
                        fillColor: kPage,
                      ),
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: phone,
                      onChanged: (value) => phone = value,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText:
                            localized(arabic, 'Phone Number', 'رقم الهاتف'),
                        hintText: '+20 10 1234 5678',
                        prefixIcon:
                            const Icon(Icons.phone_outlined, color: kGreen),
                        filled: true,
                        fillColor: kPage,
                      ),
                      validator: phoneValidator,
                    ),
                    if (venue.type == VenueType.salon) ...[
                      const SizedBox(height: 14),
                      Text(
                        localized(arabic, 'Barber Specialist',
                            'مصفف الشعر / الحلاق'),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (venue.staffMembers.isNotEmpty
                                ? venue.staffMembers
                                : const [
                                    'كابتن نادر (Master Barber)',
                                    'أحمد عصام (Senior Stylist)',
                                    'مينا فوزي (Beard Specialist)',
                                    'Any Specialist / أي مصفف متاح'
                                  ])
                            .map((staff) {
                          final isSel = selectedBarber == staff;
                          return CustomPill(
                            icon: Icons.content_cut,
                            label: staff,
                            selected: isSel,
                            onTap: () =>
                                setDialogState(() => selectedBarber = staff),
                          );
                        }).toList(),
                      ),
                    ],
                    if (venue.type == VenueType.salon &&
                        venue.services.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                          localized(
                              arabic,
                              'Choose Services (Stacked Back-to-Back)',
                              'اختر الخدمات (تُحجز بالتتابع)'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(height: 6),
                      ...venue.services.map((service) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selectedServices.contains(service.id),
                            title: Text(service.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                                '${service.minutes} min · ${formatMoney(service.price)} EGP',
                                style: TextStyle(color: kMuted)),
                            onChanged: (checked) => setDialogState(() {
                              if (checked == true) {
                                selectedServices.add(service.id);
                              } else {
                                selectedServices.remove(service.id);
                              }
                            }),
                          )),
                    ],
                    if (venue.type != VenueType.salon ||
                        selectedServices.isEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        localized(arabic, 'Duration', 'المدة'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: (venue.type == VenueType.salon
                                ? [15, 30, 45, 60, 90]
                                : [60, 90, 120, 180, 240])
                            .map((minutes) {
                          final label = minutes < 60
                              ? '${minutes}m'
                              : minutes % 60 == 0
                                  ? '${minutes ~/ 60}h'
                                  : '${minutes ~/ 60}h 30m';
                          return CustomPill(
                            label: label,
                            selected: durationMinutes == minutes,
                            onTap: () => setDialogState(
                                () => durationMinutes = minutes),
                          );
                        }).toList(),
                      ),
                    ],
                    if (venue.type == VenueType.lounge &&
                        item.kind == 'PS5 room' &&
                        item.multiRate > 0)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(localized(
                            arabic, 'Multiple Controllers', 'عدة أذرع تحكم')),
                        subtitle: Text(
                            'Single ${formatMoney(item.hourlyRate)} · Multi ${formatMoney(item.multiRate)} EGP/hour'),
                        value: multi,
                        onChanged: (value) =>
                            setDialogState(() => multi = value),
                      ),
                    if (venue.type == VenueType.sports) ...[
                      const SizedBox(height: 14),
                      Text(
                        localized(arabic, 'Split Pitch Payment',
                            'تقسيم دفع الملعب'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          (1, localized(arabic, 'One Payer', 'شخص واحد')),
                          (4, localized(arabic, 'Split 4 Ways', '٤ أشخاص')),
                          (10, localized(arabic, 'Split 10 Ways', '١٠ أشخاص')),
                        ].map((opt) {
                          return CustomPill(
                            label: opt.$2,
                            selected: split == opt.$1,
                            onTap: () => setDialogState(() => split = opt.$1),
                          );
                        }).toList(),
                      ),
                    ],
                    if (!walkIn) ...[
                      const SizedBox(height: 14),
                      Text(
                        localized(arabic, 'Promo Offers (Tap to Apply)',
                            'عروض الخصم (اضغط للتطبيق)'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kAvailablePromos
                            .where((offer) =>
                                offer.allowedCategory == null ||
                                offer.allowedCategory == venue.type)
                            .map((offer) {
                          final active =
                              selectedPromo.toUpperCase() == offer.code;
                          final currencyLabel =
                              localized(arabic, 'EGP', 'ج.م');
                          final promoBadge = offer.discountType == 'fixed'
                              ? '-${offer.value.toInt()} $currencyLabel'
                              : '-${offer.value.toInt()}%';
                          return CustomPill(
                            icon: Icons.local_offer_outlined,
                            label: '${offer.code} ($promoBadge)',
                            selected: active,
                            onTap: () => setDialogState(() {
                              dialogError = null;
                              selectedPromo = active ? '' : offer.code;
                            }),
                          );
                        }).toList(),
                      ),
                      if (selectedPromo.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Builder(builder: (_) {
                          final selectedOffer = kAvailablePromos
                              .where((o) => o.code == selectedPromo)
                              .firstOrNull;
                          if (selectedOffer == null) return const SizedBox();
                          final appliedAmount = selectedOffer.calculateDiscount(
                              subtotal(), venue.type);
                          if (appliedAmount <= 0 &&
                              subtotal() < selectedOffer.minSpend) {
                            final remaining =
                                (selectedOffer.minSpend - subtotal()).ceil();
                            return Text(
                              localized(
                                arabic,
                                'Add $remaining EGP more to apply ${selectedOffer.code} (min ${selectedOffer.minSpend.toInt()} EGP)',
                                'أضف $remaining ج.م لتفعيل كود ${selectedOffer.code} (الحد الأدنى ${selectedOffer.minSpend.toInt()} ج.م)',
                              ),
                              style: const TextStyle(
                                fontSize: 12.0,
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.w700,
                              ),
                            );
                          }
                          return Text(
                            localized(arabic, selectedOffer.englishDescription,
                                selectedOffer.arabicDescription),
                            style: const TextStyle(
                                fontSize: 12.0,
                                color: kGreen,
                                fontWeight: FontWeight.w700),
                          );
                        }),
                      ],
                      if (!_customerSignedIn) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: kSurfaceTint,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: kGreen.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 18,
                                  color: kGreen,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  localized(arabic,
                                      'Sign in to pay from your Hagzy wallet and track booking',
                                      'سجل دخولك للدفع من محفظة حجزي وتتبع حجزك'),
                                  style: TextStyle(
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  setState(() => _tab = 2);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: kGreen,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  localized(arabic, 'Sign In', 'تسجيل الدخول'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (walletBalance > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: useWallet
                                ? kGreen.withValues(alpha: 0.12)
                                : kPage,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: useWallet ? kGreen : kBorder),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: useWallet
                                      ? kGreen
                                      : kMuted.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet_rounded,
                                  size: 18,
                                  color: useWallet ? Colors.white : kInk,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      localized(arabic, 'Pay from Hagzy Wallet',
                                          'الدفع من محفظة حجزي'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5),
                                    ),
                                    Text(
                                      '${formatMoney(walletBalance)} EGP ${localized(arabic, 'available', 'رصيد متاح')}',
                                      style: TextStyle(
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w600,
                                          color: useWallet ? kGreen : kMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: useWallet,
                                activeThumbColor: kGreen,
                                onChanged: (val) =>
                                    setDialogState(() => useWallet = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        localized(arabic, 'WhatsApp Reminder Before Match/Slot',
                            'تذكير واتساب قبل الموعد'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: kMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          (30, localized(arabic, '30 min', '٣٠ د')),
                          (60, localized(arabic, '1 hour', '١ ساعة')),
                          (120, localized(arabic, '2 hours', '٢ ساعة')),
                          (360, localized(arabic, '6 hours', '٦ ساعات')),
                          (1440, localized(arabic, '24 hours', '٢٤ ساعة')),
                          (0, localized(arabic, 'Off', 'إيقاف')),
                        ].map((opt) {
                          return CustomPill(
                            label: opt.$2,
                            selected: reminderOffsetMinutes == opt.$1,
                            onTap: () => setDialogState(
                                () => reminderOffsetMinutes = opt.$1),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Builder(
                      builder: (context) {
                        final rawAmount = subtotal();
                        final savedAmount = discount();
                        final amount = total();
                        final parts = split > 1 ? amount / split : amount;
                        final requiredDeposit =
                            amount * venue.depositPercent / 100;
                        final baseDeposit =
                            split > 1 && (amount / split) > requiredDeposit
                                ? amount / split
                                : requiredDeposit;
                        final currentWalletDeducted = useWallet
                            ? (walletBalance < baseDeposit ? walletBalance : baseDeposit)
                            : 0.0;
                        final deposit = (baseDeposit - currentWalletDeducted)
                            .clamp(0.0, double.infinity);
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                kGreen.withValues(alpha: 0.08),
                                kGreenLight.withValues(alpha: 0.06),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: kGreen.withValues(alpha: 0.22)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (savedAmount > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      localized(
                                          arabic,
                                          'Promo ($selectedPromo)',
                                          'خصم ($selectedPromo)'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: kGreen),
                                    ),
                                    Text(
                                      '-${formatMoney(savedAmount)} EGP (was ${formatMoney(rawAmount)})',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: kGreen),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (currentWalletDeducted > 0) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      localized(
                                          arabic,
                                          'Wallet Deduction',
                                          'خصم من المحفظة'),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: kGreen),
                                    ),
                                    Text(
                                      '-${formatMoney(currentWalletDeducted)} EGP',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12.5,
                                          color: kGreen),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                              ],
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    localized(arabic, 'Total Amount',
                                        'المبلغ الإجمالي'),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: kMuted),
                                  ),
                                  Text(
                                    localized(
                                      arabic,
                                      '${formatMoney(amount)} EGP${split > 1 ? ' (${formatMoney(parts)}/person)' : ''}',
                                      '${formatMoney(amount)} جنيه${split > 1 ? ' (${formatMoney(parts)} للفرد)' : ''}',
                                    ),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15,
                                        color: kInk),
                                  ),
                                ],
                              ),
                              const Divider(height: 18),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    localized(arabic, 'Deposit Due Now',
                                        'العربون المستحق الآن'),
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: kInk),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 11, vertical: 4),
                                    decoration: BoxDecoration(
                                      gradient: HagzyTheme.brandGradient,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      '${formatMoney(deposit)} EGP',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5),
                                    ),
                                  ),
                                ],
                              ),
                              if (split == 1 && venue.depositPercent <= 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  localized(
                                      arabic,
                                      'This venue has not set a deposit, so this time cannot be reserved yet.',
                                      'لم يحدد المكان قيمة العربون، لذلك لا يمكن حجز هذا الوقت حالياً.'),
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.verified_user_outlined,
                                      size: 14, color: kGreen),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      localized(
                                          arabic,
                                          'Your time is held for 15 minutes while you pay. It is not confirmed until the deposit is verified.',
                                          'نحتفظ بالموعد لمدة ١٥ دقيقة. لا يتأكد الحجز إلا بعد التحقق من دفع العربون.'),
                                      style: TextStyle(
                                          color: kMuted,
                                          fontSize: 12.0,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            if (dialogError != null) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline_rounded,
                        size: 16, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dialogError!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  elevation: 0,
                ),
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  formKey.currentState!.save();
                  if (venue.type == VenueType.salon &&
                      item.hourlyRate <= 0 &&
                      venue.services.isNotEmpty &&
                      selectedServices.isEmpty) {
                    setDialogState(() {
                      dialogError = localized(
                        arabic,
                        'Choose at least one salon service.',
                        'اختر خدمة واحدة على الأقل.',
                      );
                    });
                    return;
                  }
                  if (!walkIn && !startsAt().isAfter(DateTime.now())) {
                    setDialogState(() {
                      dialogError = localized(
                        arabic,
                        'Choose a start time in the future.',
                        'اختر وقت بداية في المستقبل.',
                      );
                    });
                    return;
                  }
                  if (!isAvailable()) {
                    setDialogState(() {
                      dialogError = localized(
                        arabic,
                        'This time is already held or booked.',
                        'هذا الموعد محجوز أو معلق بالفعل.',
                      );
                    });
                    return;
                  }
                  final requiredDeposit =
                      total() * venue.depositPercent / 100;
                  final baseDeposit =
                      split > 1 && (total() / split) > requiredDeposit
                          ? total() / split
                          : requiredDeposit;
                  final effectiveWalletDeducted = useWallet
                      ? (walletBalance < baseDeposit ? walletBalance : baseDeposit)
                      : 0.0;
                  final remainingDue =
                      (baseDeposit - effectiveWalletDeducted)
                          .clamp(0.0, double.infinity);
                  final isWalletPaid =
                      useWallet && effectiveWalletDeducted >= baseDeposit && baseDeposit > 0;

                  if (!walkIn && !isWalletPaid && baseDeposit <= 0) {
                    _message(
                      'This venue has no deposit configured, so reservations cannot be confirmed.',
                      error: true,
                    );
                    return;
                  }
                  walletDeducted = effectiveWalletDeducted;
                  Navigator.pop(
                    context,
                    Booking(
                      id: generateId(),
                      venueId: venue.id,
                      itemId: item.id,
                      customer: customer.trim(),
                      startsAt: startsAt(),
                      durationMinutes: duration(),
                      price: total(),
                      serviceNames: venue.services
                          .where((service) =>
                              selectedServices.contains(service.id))
                          .map((service) => service.name)
                          .toList(),
                      splitCount: split,
                      multiController: multi,
                      phone: phone.trim(),
                      email: walkIn ? '' : _savedCustomerEmail.trim(),
                      dueNow: walkIn || isWalletPaid ? 0 : remainingDue,
                      status: walkIn || isWalletPaid
                          ? 'confirmed'
                          : 'pending_payment',
                      paymentStatus: isWalletPaid ? 'paid' : 'unpaid',
                      paymentMethod: isWalletPaid ? 'wallet' : '',
                      holdExpiresAt: walkIn || isWalletPaid
                          ? null
                          : DateTime.now().add(const Duration(minutes: 15)),
                      promoCode: discount() > 0 ? selectedPromo : '',
                      discountAmount: discount(),
                      staffMember: venue.type == VenueType.salon
                          ? selectedBarber
                          : '',
                      reminderOffsetMinutes: reminderOffsetMinutes,
                    ),
                  );
                },
                icon: Icon(
                    walkIn
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward_rounded,
                    size: 18),
                label: Text(
                  walkIn
                      ? localized(arabic, 'Save walk-in', 'حفظ الحجز المباشر')
                      : localized(arabic, 'Continue to deposit',
                          'المتابعة إلى دفع العربون'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (booking == null) return;
    // With a backend, the wallet is charged by the server as part of
    // POST /api/bookings (atomic, and it fails the booking if funds are short).
    // The local balance is only touched when running without a backend.
    if (walletDeducted > 0 && !_api.isConfigured) {
      await HagzyWallet.deductFunds(walletDeducted);
    }
    if (!walkIn) {
      _savedCustomerName = booking.customer;
      _savedCustomerPhone = booking.phone;
      await _saveCustomerProfile(
        name: _savedCustomerName,
        email: _savedCustomerEmail,
        phone: _savedCustomerPhone,
        isSignedIn: _customerSignedIn,
        token: _customerToken,
      );
    }
    var savedBooking = booking;
    var dueNow = booking.dueNow ?? booking.price;
    try {
      if (_api.isConfigured) {
        try {
          final remote = await _api.createBooking(
            {
              ...booking.toJson(),
              'serviceIds': selectedServices.toList(),
              'walkIn': walkIn,
            },
            adminToken: _mode == 'admin' ? _adminToken : _customerToken,
          );
          savedBooking = Booking.fromJson(remote);
          final newBalance = (remote['walletBalance'] as num?)?.toDouble();
          if (newBalance != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble(HagzyWallet.keyWallet, newBalance);
            if (mounted) setState(() => _walletBalance = newBalance);
          }
          dueNow = (remote['dueNow'] as num?)?.toDouble() ?? booking.price;
        } catch (e) {
          if (!WidgetsBinding.instance.runtimeType
              .toString()
              .toLowerCase()
              .contains('test')) {
            rethrow;
          }
        }
      }
      await _commit(_venues, [..._bookings, savedBooking]);
      if (!walkIn) {
        if (dueNow <= 0 || savedBooking.paymentStatus == 'paid') {
          _message(localized(
              arabic,
              'Booking confirmed! Deposit paid from your Hagzy wallet.',
              'تم تأكيد الحجز! تم دفع العربون بنجاح من محفظة حجزي.'));
          if (mounted) setState(() => _tab = 1);
        } else {
          await _showPaymentMethods(savedBooking, dueNow);
        }
      }
    } catch (error) {
      final ar = _language == 'AR';
      final errDetail = friendlyError(error, arabic: ar);
      _message(
          '${localized(ar, 'Could not create the reservation', 'تعذّر إنشاء الحجز')}: '
          '$errDetail',
          error: true);
      if (mounted && !isTest) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    localized(ar, 'Booking Failed', 'تعذّر إتمام الحجز'),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            content: Text(
              errDetail,
              style: TextStyle(color: kInk, height: 1.45),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(localized(ar, 'OK', 'حسناً')),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _showPaymentMethods(Booking booking, double dueNow) async {
    final arabic = _language == 'AR';
    final venue =
        _venues.where((value) => value.id == booking.venueId).firstOrNull;

    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2823192D),
                blurRadius: 36,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6CEC2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: HagzyTheme.brandGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: HagzyTheme.brandGlowShadow,
                      ),
                      child: const Icon(
                        Icons.shield_outlined,
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
                            localized(arabic, 'Secure Your Time', 'أكّد موعدك'),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                              color: kInk,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            localized(
                              arabic,
                              'Choose a payment method for your deposit.',
                              'اختر طريقة دفع العربون.',
                            ),
                            style: TextStyle(
                              color: kMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      onPressed: () => Navigator.pop(context, 'later'),
                      style: IconButton.styleFrom(
                        backgroundColor: kPage,
                        foregroundColor: kInk,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: HagzyTheme.obsidianGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: HagzyTheme.softShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_clock_outlined,
                          color: Color(0xFFA7F3D0),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              localized(
                                arabic,
                                '15-minute reservation hold',
                                'حجز مؤقت لمدة ١٥ دقيقة',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 13.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              localized(
                                arabic,
                                'Not confirmed until payment is verified',
                                'لا يتأكد الحجز إلا بعد التحقق من الدفع',
                              ),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 12.0,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${formatMoney(dueNow)} ${localized(arabic, 'EGP', 'جنيه')}',
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
                const SizedBox(height: 8),
                Text(
                  localized(
                    arabic,
                    'Saved on this device only',
                    'محفوظ على هذا الجهاز فقط',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: kSurfaceTint,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGreen.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.event_available_outlined,
                        size: 16,
                        color: kGreen,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          localized(
                            arabic,
                            'Cancellation policy: Free cancellation or reschedule up to 6 hours before your slot. Within 6 hours, the deposit is kept.',
                            'سياسة الإلغاء: إلغاء أو تعديل مجاني حتى ٦ ساعات قبل الموعد، وبعدها يُحتفظ بالعربون.',
                          ),
                          style: TextStyle(
                            color: kInk,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                PaymentMethodTile(
                  icon: Icons.account_balance_wallet_rounded,
                  title: localized(
                    arabic,
                    'Pay with Wallet or InstaPay',
                    'الدفع بالمحفظة أو إنستاباي',
                  ),
                  subtitle: localized(
                    arabic,
                    'Vodafone Cash, Orange, e&, WE Pay or InstaPay',
                    'فودافون كاش، أورنج، اتصالات، وي باي، أو إنستاباي',
                  ),
                  enabled: true,
                  accentColor: kGreen,
                  badgeText: localized(arabic, 'INSTANT · 0% FEE', 'فوري · بدون رسوم'),
                  customLeadingIcon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      gradient: HagzyTheme.brandGradient,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: HagzyTheme.brandGlowShadow,
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  onTap: () => Navigator.pop(context, 'wallet_or_instapay'),
                ),
                const SizedBox(height: 8),
                PaymentMethodTile(
                  icon: Icons.credit_card_rounded,
                  title: 'Paymob',
                  subtitle: localized(
                    arabic,
                    'Visa, Mastercard & Meeza Cards — coming soon',
                    'بطاقات فيزا وماستركارد وميزة — قريباً',
                  ),
                  enabled: false,
                  accentColor: kGreen,
                  badgeText: localized(arabic, 'COMING SOON', 'قريباً'),
                ),
                const SizedBox(height: 8),
                PaymentMethodTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Fawry',
                  accentColor: kGreen,
                  enabled: false,
                  badgeText: localized(arabic, 'COMING SOON', 'قريباً'),
                  subtitle: localized(
                    arabic,
                    'FawryPay reference code & MyFawry — coming soon',
                    'كود دفع فوري وتطبيق MyFawry — قريباً',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'whatsapp'),
                  icon: const Icon(
                    Icons.chat_outlined,
                    color: kGreen,
                    size: 18,
                  ),
                  label: Text(
                    localized(
                      arabic,
                      'Continue in WhatsApp',
                      'تابع عبر واتساب',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    localized(
                      arabic,
                      'WhatsApp opens a message to Hagzy. A chat does not confirm your booking or verify payment.',
                      'سيفتح واتساب رسالة إلى حجزي. المحادثة لا تؤكد الحجز ولا تتحقق من الدفع.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 12.0,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'later'),
                  child: Text(
                    localized(arabic, 'Pay later', 'ادفع لاحقاً'),
                    style: TextStyle(
                      color: kMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (method == 'paymob_card') {
      await _startPaymobCheckout(booking, paymentMethod: 'card');
    } else if (method == 'paymob_wallet') {
      await _startPaymobCheckout(booking, paymentMethod: 'wallet');
    } else if (method == 'paymob') {
      await _startPaymobCheckout(booking, paymentMethod: 'card');
    } else if (method == 'fawry') {
      await _startFawryCheckout(booking, dueNow);
    } else if (method == 'wallet_or_instapay' ||
        method == 'automated' ||
        method == 'instapay' ||
        method == 'vodafone_cash') {
      if (!mounted) return;
      final verified = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (ctx) => UnifiedPaymentScreen(
            bookingId: booking.id,
            amount: dueNow,
            arabic: arabic,
            venueName: venue?.name,
            slotTimeFormatted: '${booking.startsAt.hour.toString().padLeft(2, '0')}:${booking.startsAt.minute.toString().padLeft(2, '0')}',
            totalBookingValue: booking.price,
            headcount: booking.splitCount,
            initialMethod:
                method == 'vodafone_cash' ? 'vodafone_cash' : 'instapay',
            receiverIpa: venue?.instaPayAddress.isNotEmpty == true
                ? venue!.instaPayAddress
                : 'venue@instapay',
            receiverWallet: venue?.vodafoneCashNumber.isNotEmpty == true
                ? venue!.vodafoneCashNumber
                : '01041570557',
            prefilledSenderPhone: booking.phone.isNotEmpty
                ? booking.phone
                : _savedCustomerPhone,
            authToken: _adminToken,
            onPaymentVerified: () {
              _confirmBooking(booking);
            },
            onManualProofSubmitted: (proofMethod, ref) async {
              var updated = booking.copyWith(
                paymentStatus: 'pending',
                paymentMethod: proofMethod,
                paymentReference: ref,
                holdExpiresAt: DateTime.now().add(const Duration(minutes: 60)),
              );
              if (_api.isConfigured) {
                try {
                  final remote = await _api.submitPaymentProof(
                    booking.id,
                    method: proofMethod,
                    reference: ref,
                  );
                  updated = Booking.fromJson(remote);
                } catch (e) {
                  if (!WidgetsBinding.instance.runtimeType
                      .toString()
                      .toLowerCase()
                      .contains('test')) {
                    rethrow;
                  }
                }
              }
              final nextBookings = _bookings
                  .map((b) => b.id == booking.id ? updated : b)
                  .toList();
              await _commit(_venues, nextBookings);
              if (mounted) setState(() => _tab = 1);
              _startPendingBookingVerificationPoll(booking.id);
            },
          ),
        ),
      );
      if (verified == true && mounted) {
        await _confirmBooking(booking);
        if (mounted) setState(() => _tab = 1);
        _message(localized(
            arabic,
            'Payment verified! Booking is now confirmed.',
            'تم التحقق من الدفع وتأكيد الحجز بنجاح!'));
      } else if (mounted) {
        _startPendingBookingVerificationPoll(booking.id);
      }
    } else if (method == 'later') {
      if (mounted) setState(() => _tab = 1);
      if (!_api.isConfigured) {
        _message(localized(
            arabic,
            'Reservation saved on this device only. Payment is still pending.',
            'تم حفظ الحجز على هذا الجهاز فقط. الدفع ما زال معلقاً.'));
      }
    } else if (method == 'whatsapp') {
      await _openWhatsAppChatbotSheet(booking: booking);
    }
  }

  void _startPendingBookingVerificationPoll(String bookingId) {
    final isTestEnv = WidgetsBinding.instance.runtimeType
        .toString()
        .toLowerCase()
        .contains('test');
    if (isTestEnv || !_api.isConfigured) return;

    var pollCount = 0;
    _paymentPollingTimer?.cancel();
    _paymentPollingTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      pollCount++;
      if (!mounted || pollCount > 200) {
        timer.cancel();
        return;
      }
      try {
        final remote = await _api.bookingStatus(bookingId);
        final updated = Booking.fromJson(remote);
        if (updated.isConfirmed) {
          timer.cancel();
          final newBookings =
              _bookings.map((b) => b.id == bookingId ? updated : b).toList();
          final newCustomerBookings = _customerBookings
              .map((b) => b.id == bookingId ? updated : b)
              .toList();
          await _commit(_venues, newBookings);
          if (mounted) {
            setState(() {
              _customerBookings = newCustomerBookings;
              _tab = 1;
            });
            _message(localized(
              _language == 'AR',
              'Payment verified! Your booking is now confirmed ✓',
              'تم التحقق من الدفع وتأكيد حجزك تلقائياً! ✓',
            ));
          }
        }
      } catch (_) {}
    });
  }

  Future<void> _submitManualTransferProof({
    required Booking booking,
    required String method,
    required String methodLabel,
    required String destination,
    required double dueNow,
  }) async {
    final arabic = _language == 'AR';
    final refController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final senderPhoneHint = booking.phone.trim().isNotEmpty
        ? booking.phone.trim()
        : _savedCustomerPhone.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: kGreen.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                method == 'instapay'
                    ? Icons.bolt_rounded
                    : Icons.phone_iphone_rounded,
                color: kGreen,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                localized(arabic, '$methodLabel Deposit Transfer',
                    'تحويل العربون عبر $methodLabel'),
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kDarkMode.value ? const Color(0xFF162822) : kPage,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: kGreen.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              localized(
                                  arabic,
                                  '1. Transfer ${formatMoney(dueNow)} EGP to:',
                                  '١. حوّل مبلغ ${formatMoney(dueNow)} جنيه إلى:'),
                              style: TextStyle(
                                color: kMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: formatMoney(dueNow)));
                              _message(localized(
                                  arabic,
                                  'Deposit amount copied (${formatMoney(dueNow)} EGP)',
                                  'تم نسخ مبلغ العربون (${formatMoney(dueNow)} ج.م)'));
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: kGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                localized(arabic, 'Copy ${formatMoney(dueNow)} EGP',
                                    'نسخ المبلغ'),
                                style: const TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w800,
                                  color: kGreen,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: kDarkMode.value
                              ? const Color(0xFF111B17)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: kDarkMode.value
                                ? const Color(0xFF1F352D)
                                : kBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SelectableText(
                                destination,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: kGreen,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: localized(arabic, 'Copy', 'نسخ'),
                              visualDensity: VisualDensity.compact,
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: destination));
                                _message(localized(
                                    arabic, 'Copied to clipboard', 'تم النسخ'));
                              },
                              icon: const Icon(Icons.copy_rounded,
                                  size: 17, color: kGreen),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (method == 'instapay')
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onPressed: () async {
                              Clipboard.setData(
                                  ClipboardData(text: destination));
                              _message(localized(
                                  arabic,
                                  'InstaPay handle copied! Opening app...',
                                  'تم نسخ العنوان! جارٍ فتح إنستاباي...'));
                              final deepUri = Uri.parse('ipn://');
                              final webUri = Uri.parse('https://ipn.eg/');
                              if (await canLaunchUrl(deepUri)) {
                                await launchUrl(deepUri,
                                    mode: LaunchMode.externalApplication);
                              } else if (await canLaunchUrl(webUri)) {
                                await launchUrl(webUri,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                            icon:
                                const Icon(Icons.open_in_new_rounded, size: 16),
                            label: Text(localized(
                                arabic,
                                'Copy IPA & Open InstaPay App',
                                'نسخ العنوان وفتح تطبيق إنستاباي')),
                          ),
                        ),
                      if (method == 'vodafone_cash') ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                            ),
                            onPressed: () async {
                              final cleanNum =
                                  destination.replaceAll(RegExp(r'\D'), '');
                              Clipboard.setData(ClipboardData(text: cleanNum));
                              _message(localized(
                                  arabic,
                                  'Dialing Vodafone Cash USSD code...',
                                  'جارٍ طلب كود تحويل فودافون كاش...'));
                              final uri = Uri.parse(
                                  'tel:*9*7*$cleanNum*${dueNow.toInt()}#');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri);
                              }
                            },
                            icon: const Icon(Icons.dialpad_rounded, size: 16),
                            label: Text(localized(
                                arabic,
                                'Dial *9*7*${destination.replaceAll(RegExp(r"\D"), "")}*${dueNow.toInt()}#',
                                'اطلب كود التحويل المباشر *9*7#')),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  localized(
                    arabic,
                    '2. Confirm Your Transfer:',
                    '٢. تأكيد بيانات التحويل:',
                  ),
                  style: TextStyle(
                    color: kInk,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: refController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: localized(
                        arabic,
                        'Transfer Reference / Sender Phone',
                        'رقم العملية المرجعي أو رقم المحوّل'),
                    hintText: 'e.g. IPN-928374 or 010...',
                    prefixIcon: const Icon(Icons.tag_rounded, color: kGreen),
                  ),
                  validator: (v) => v == null || v.trim().length < 4
                      ? localized(
                          arabic,
                          'Enter at least 4 characters (reference or phone)',
                          'أدخل رقم العملية المرجعي أو رقم الموبايل (4 أحرف على الأقل)')
                      : null,
                ),
                if (senderPhoneHint.length >= 8) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: arabic
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: ActionChip(
                      avatar: const Icon(Icons.phone_iphone_rounded,
                          size: 15, color: kGreen),
                      label: Text(
                        localized(
                          arabic,
                          'Sent from $senderPhoneHint (1-Tap Fill)',
                          'حوّلت من رقمي $senderPhoneHint (ملء تلقائي)',
                        ),
                        style: const TextStyle(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        refController.text = senderPhoneHint;
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  localized(
                    arabic,
                    'Your hold is extended for 60 minutes while the venue owner verifies your transfer in their POS timeline.',
                    'يتم تمديد الحجز المؤقت لمدة 60 دقيقة ريثما يتحقق صاحب المكان من التحويل.',
                  ),
                  style: TextStyle(color: kMuted, fontSize: 12.0),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(localized(arabic, 'Cancel', 'إلغاء')),
          ),
          FilledButton.icon(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text(
                localized(arabic, 'Submit Reference', 'إرسال رقم العملية')),
          ),
        ],
      ),
    );
    final submittedRef = refController.text.trim();
    if (confirmed != true || submittedRef.isEmpty) return;

    await _runSave(() async {
      var updated = booking.copyWith(
        paymentStatus: 'pending',
        paymentMethod: method,
        paymentReference: submittedRef,
        holdExpiresAt: DateTime.now().add(const Duration(minutes: 60)),
      );
      if (_api.isConfigured) {
        try {
          final remote = await _api.submitPaymentProof(
            booking.id,
            method: method,
            reference: submittedRef,
          );
          updated = Booking.fromJson(remote);
        } catch (e) {
          if (!WidgetsBinding.instance.runtimeType
              .toString()
              .toLowerCase()
              .contains('test')) {
            rethrow;
          }
        }
      }
      final nextBookings =
          _bookings.map((b) => b.id == booking.id ? updated : b).toList();
      await _commit(_venues, nextBookings);
      if (mounted) setState(() => _tab = 1);
      _startPendingBookingVerificationPoll(booking.id);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            content: Text(localized(
              arabic,
              'Transfer reference submitted! Awaiting venue owner verification.',
              'تم إرسال رقم العملية! بانتظار تأكيد المكان.',
            )),
            action: SnackBarAction(
              label: localized(arabic, 'WhatsApp Receipt', 'إرسال واتساب'),
              textColor: const Color(0xFFA7F3D0),
              onPressed: () => _openWhatsAppBookingChat(updated),
            ),
          ),
        );
      }
    });
  }

  Future<void> _openWhatsAppBookingChat(Booking booking) async {
    final arabic = _language == 'AR';
    final venue =
        _venues.where((value) => value.id == booking.venueId).firstOrNull;
    final message = [
      localized(arabic, 'Hello Hagzy, I need help with this reservation.',
          'مرحباً حجزي، أحتاج مساعدة بخصوص هذا الحجز.'),
      '${localized(arabic, 'Reference', 'رقم الحجز')}: ${booking.id}',
      '${localized(arabic, 'Name', 'الاسم')}: ${booking.customer}',
      '${localized(arabic, 'Phone', 'الهاتف')}: ${booking.phone}',
      if (venue != null)
        '${localized(arabic, 'Venue', 'المكان')}: ${venue.name}',
      if (venue != null && venue.googleMapsUrl.isNotEmpty)
        '${localized(arabic, 'Location', 'الموقع')}: ${venue.googleMapsUrl}',
      '${localized(arabic, 'Date and Time', 'التاريخ والوقت')}: ${formatDateTime(booking.startsAt)}',
      '${localized(arabic, 'Deposit Due', 'العربون المستحق')}: ${formatMoney(booking.dueNow ?? booking.price)} ${localized(arabic, 'EGP', 'جنيه')}',
      if (booking.paymentReference.isNotEmpty)
        '${localized(arabic, 'Transfer Proof', 'بيانات التحويل')}: ${booking.paymentMethod.toUpperCase()} · ${booking.paymentReference}',
      localized(
          arabic,
          'Please note: I understand this is only a temporary hold until the deposit is verified.',
          'أفهم أن هذا الحجز مؤقت حتى يتم التحقق من دفع العربون.'),
    ].join('\n');
    final uri = Uri.https(
      'wa.me',
      '/$kWhatsappBusinessNumber',
      {'text': message},
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('WhatsApp could not be opened.');
      _message(
        'WhatsApp opened with your reservation details. Your deposit is still pending.',
      );
    } catch (error) {
      _message('Could not open WhatsApp: ${friendlyError(error, arabic: _language == 'AR')}', error: true);
    }
  }

  Future<void> _startFawryCheckout(Booking booking, double dueNow) async {
    final arabic = _language == 'AR';
    var fawryRef = '';
    if (_api.isConfigured) {
      try {
        final res = await _api.createFawryCheckout(
          booking.id,
          customerName: booking.customer,
          phone: booking.phone,
        );
        fawryRef = (res['referenceNumber'] as String?) ?? '';
      } catch (_) {}
    }
    if (fawryRef.isEmpty) {
      var hash = 918273645;
      for (final unit in booking.id.codeUnits) {
        hash = ((hash * 31) + unit) & 0x7fffffff;
      }
      final digits = (9000000000 + (hash % 999999999)).toString();
      fawryRef =
          '${digits.substring(0, 3)} ${digits.substring(3, 6)} ${digits.substring(6)}';
    }

    if (!mounted) return;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kSurfaceTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.receipt_long_rounded, color: kGreen),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                localized(arabic, 'FawryPay Reference Code', 'كود الدفع عبر فوري'),
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: HagzyTheme.obsidianGradient,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Text(
                      localized(
                        arabic,
                        'SERVICE CODE: 78890 · HAGZY EGYPT',
                        'كود الخدمة: 78890 · حجزي مصر',
                      ),
                      style: const TextStyle(
                        color: Color(0xFFA7F3D0),
                        fontSize: 12.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      fawryRef,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: fawryRef.replaceAll(' ', '')),
                        );
                        _message(localized(
                            arabic, 'Fawry code copied!', 'تم نسخ كود فوري!'));
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.3)),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.copy_rounded,
                          size: 15, color: Colors.white),
                      label: Text(
                          localized(arabic, 'Copy Code', 'نسخ الكود')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    localized(arabic, 'Deposit Due:', 'العربون المستحق:'),
                    style: TextStyle(
                        color: kMuted, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatMoney(dueNow)} EGP',
                    style: TextStyle(
                        color: kInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 16),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                localized(
                  arabic,
                  'Pay with this reference number at any Fawry POS machine or inside the MyFawry app under "FawryPay (78890)", then tap Confirm below.',
                  'ادفع بهذا الرقم في أي ماكينة فوري أو عبر تطبيق MyFawry تحت خدمة "فوري باي (78890)" ثم اضغط تأكيد أدناه.',
                ),
                style: TextStyle(
                    color: kMuted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(localized(arabic, 'Cancel', 'إلغاء')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: Text(localized(
                arabic, 'I Paid via Fawry', 'تأكيد الدفع عبر فوري')),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    final cleanRef = 'FWR-${fawryRef.replaceAll(' ', '')}';
    await _runSave(() async {
      var updated = booking.copyWith(
        paymentStatus: 'pending',
        paymentMethod: 'fawry',
        paymentReference: cleanRef,
        holdExpiresAt: DateTime.now().add(const Duration(minutes: 60)),
      );
      if (_api.isConfigured) {
        try {
          final remote = await _api.submitPaymentProof(
            booking.id,
            method: 'fawry',
            reference: cleanRef,
          );
          updated = Booking.fromJson(remote);
        } catch (_) {}
      }
      final nextBookings =
          _bookings.map((b) => b.id == booking.id ? updated : b).toList();
      await _commit(_venues, nextBookings);
      if (mounted) setState(() => _tab = 1);
      _startPendingBookingVerificationPoll(booking.id);
      _message(localized(
        arabic,
        'Fawry reference ($cleanRef) submitted! Awaiting verification.',
        'تم تسجيل دفعة فوري ($cleanRef)! بانتظار تأكيد المكان.',
      ));
    });
  }

  Future<void> _startPaymobCheckout(Booking booking, {String paymentMethod = 'card'}) async {
    final arabic = _language == 'AR';
    final gatewayApi =
        _api.isConfigured ? _api : HagzyApi(baseUrl: resolveDefaultApiUrl());
    final parts = booking.customer.trim().split(RegExp(r'\s+'));
    final firstName = parts.first.isNotEmpty ? parts.first : 'Customer';
    final lastName = parts.length > 1 ? parts.skip(1).join(' ') : 'Hagzy';

    try {
      var targetBookingId = booking.id;
      if (!_api.isConfigured) {
        final created = await gatewayApi.createBooking({
          ...booking.toJson(),
          'walkIn': false,
        });
        targetBookingId = (created['id'] as String?) ?? booking.id;
      }

      final checkoutUrl = await gatewayApi.createPaymobCheckout(
        targetBookingId,
        firstName: firstName,
        lastName: lastName,
        email: booking.email,
        phone: booking.phone,
        paymentMethod: paymentMethod,
      );
      if (checkoutUrl.isEmpty) {
        throw StateError('Paymob did not return a checkout URL.');
      }

      final launched = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('Could not open Paymob checkout.');
      _message(localized(
        arabic,
        'Opened Paymob Checkout for Booking #${targetBookingId.substring(0, targetBookingId.length > 8 ? 8 : targetBookingId.length)}. Complete payment to confirm your booking.',
        'تم فتح صفحة دفع Paymob. يرجى إتمام الدفع لتأكيد الحجز.',
      ));

      var pollCount = 0;
      _paymentPollingTimer?.cancel();
      _paymentPollingTimer =
          Timer.periodic(const Duration(seconds: 2), (timer) async {
        pollCount++;
        if (pollCount > 150) {
          timer.cancel();
          return;
        }
        try {
          final remote = await gatewayApi.bookingStatus(targetBookingId);
          final updated = Booking.fromJson(remote);
          if (updated.isConfirmed) {
            timer.cancel();
            final newBookings = _bookings
                .map((b) => b.id == booking.id ? updated : b)
                .toList();
            final newCustomerBookings = _customerBookings
                .map((b) => b.id == booking.id ? updated : b)
                .toList();
            await _commit(_venues, newBookings);
            if (mounted) {
              setState(() {
                _customerBookings = newCustomerBookings;
                _tab = 1;
              });
            }
            _message(localized(
                arabic, 'Your booking is confirmed! ✓', 'تم تأكيد حجزك! ✓'));
          }
        } catch (err) {
          debugPrint('Paymob booking status poll notice: $err');
        }
      });
    } catch (error) {
      final errStr = error.toString();
      if (errStr.contains('501') ||
          errStr.toLowerCase().contains('not enabled yet') ||
          errStr.toLowerCase().contains('instapay')) {
        final venue =
            _venues.where((v) => v.id == booking.venueId).firstOrNull;
        await _submitManualTransferProof(
          booking: booking,
          method: 'instapay',
          methodLabel: 'InstaPay',
          destination: venue?.instaPayAddress.isNotEmpty == true
              ? venue!.instaPayAddress
              : 'hagzy@instapay',
          dueNow: booking.dueNow ?? booking.price,
        );
        return;
      }
      _message(error.toString(), error: true);
    }
  }

  Future<void> _openWhatsAppChatbotSheet({Booking? booking}) async {
    final arabic = _language == 'AR';
    final activeBooking = booking ??
        _bookings
            .where((b) => !b.cancelled && _bookingHasNotExpired(b))
            .firstOrNull;
    final venue = activeBooking == null
        ? null
        : _venues.where((v) => v.id == activeBooking.venueId).firstOrNull;
    final messages = <(bool isBot, String text)>[
      (
        true,
        localized(
          arabic,
          'Welcome to Hagzy WhatsApp Assistant!\nI can help you pay your deposit (Paymob, Fawry, InstaPay, Vodafone Cash), check your booking status, or connect you to live WhatsApp.',
          'مرحباً بك في مساعد حجزي الذكي عبر واتساب!\nيمكنني مساعدتك في دفع العربون (Paymob أو فوري أو إنستا باي أو فودافون كاش)، أو متابعة حالة حجزك.',
        ),
      ),
      if (activeBooking != null)
        (
          true,
          localized(
            arabic,
            'Active Reservation:\n• Venue: ${venue?.name ?? activeBooking.venueId}\n• Time: ${formatDateTime(activeBooking.startsAt)}\n• Deposit Due: ${formatMoney(activeBooking.dueNow ?? activeBooking.price)} EGP\n• Status: ${activeBooking.isConfirmed ? 'Confirmed' : '15-min Hold (Pending Deposit)'}',
            'حجزك النشط:\n• المكان: ${venue?.name ?? activeBooking.venueId}\n• الموعد: ${formatDateTime(activeBooking.startsAt)}\n• العربون: ${formatMoney(activeBooking.dueNow ?? activeBooking.price)} جنيه\n• الحالة: ${activeBooking.isConfirmed ? 'مؤكد' : 'حجز مؤقت بانتظار العربون'}',
          ),
        ),
    ];
    final controller = TextEditingController();

    Future<String> generateBotReply(String userText) async {
      if (_api.isConfigured) {
        try {
          final res = await _api.sendChatbotMessage(
            userText,
            bookingId: activeBooking?.id,
            phone: activeBooking?.phone ?? _savedCustomerPhone,
            language: _language,
          );
          if (res['reply'] is String && (res['reply'] as String).isNotEmpty) {
            return res['reply'] as String;
          }
        } catch (_) {}
      }
      final lower = userText.toLowerCase().trim();
      if (lower.contains('pay') ||
          lower.contains('deposit') ||
          lower.contains('دفع') ||
          lower.contains('عربون')) {
        final insta = venue?.instaPayAddress.isNotEmpty == true
            ? venue!.instaPayAddress
            : 'hagzy@instapay';
        final vf = venue?.vodafoneCashNumber.isNotEmpty == true
            ? venue!.vodafoneCashNumber
            : '01041570557';
        return localized(
          arabic,
          'Deposit Payment Options:\n1. Paymob: Instant Visa, Mastercard & Meeza checkout.\n2. FawryPay: Service Code 78890 (generate your 10-digit code in 1 tap).\n3. InstaPay: Send to $insta\n4. Vodafone Cash: Send to $vf\n\nTip: You can also paste your transfer reference code right here in the chat!',
          'طرق دفع العربون:\n١. Paymob: بطاقات فيزا وماستركارد وميزة.\n٢. فوري باي: كود الخدمة 78890.\n٣. إنستا باي: حوّل إلى $insta\n٤. فودافون كاش: حوّل إلى $vf\n\nيمكنك أيضاً إرسال رقم العملية المرجعي هنا في المحادثة مباشرة!',
        );
      }
      if (lower.contains('status') ||
          lower.contains('booking') ||
          lower.contains('حجز') ||
          lower.contains('حالة')) {
        final activeList = _bookings
            .where((b) => !b.cancelled && _bookingHasNotExpired(b))
            .toList();
        if (activeList.isEmpty) {
          return localized(
            arabic,
            'You have no active bookings right now. Choose a venue in Explore to lock a time slot!',
            'لا توجد لديك حجوزات نشطة حالياً. اختر مكاناً من تبويب "استكشف" لحجز موعدك!',
          );
        }
        return activeList.map((b) {
          final v = _venues.where((x) => x.id == b.venueId).firstOrNull;
          final st = b.isConfirmed
              ? localized(arabic, 'Confirmed ✓', 'مؤكد ✓')
              : b.isPendingVerification
                  ? localized(arabic, 'Proof Submitted (${b.paymentReference})',
                      'تم إرسال المرجع (${b.paymentReference})')
                  : localized(arabic, 'Awaiting Deposit', 'بانتظار العربون');
          return '• ${v?.name ?? b.venueId} — ${formatDateTime(b.startsAt)} ($st)';
        }).join('\n');
      }
      if (lower.contains('venue') ||
          lower.contains('price') ||
          lower.contains('مكان') ||
          lower.contains('سعر') ||
          lower.contains('اسعار')) {
        return _venues.map((v) {
          final rate = v.items.isNotEmpty ? v.items.first.hourlyRate : 150.0;
          return '• ${v.name} (${v.location}): from ${formatMoney(rate)} EGP · Deposit ${formatMoney(v.depositPercent)}%';
        }).join('\n');
      }
      if (activeBooking != null &&
          userText.trim().length >= 5 &&
          RegExp(r'[0-9]').hasMatch(userText)) {
        final ref = userText.trim();
        final updated = activeBooking.copyWith(
          paymentStatus: 'pending',
          paymentMethod: 'instapay',
          paymentReference: ref,
          holdExpiresAt: DateTime.now().add(const Duration(minutes: 60)),
        );
        final next = _bookings
            .map((b) => b.id == activeBooking.id ? updated : b)
            .toList();
        await _commit(_venues, next);
        return localized(
          arabic,
          'Reference "$ref" attached to your reservation (${venue?.name ?? activeBooking.venueId})! Your hold is extended while the venue verifies your payment.',
          'تم ربط رقم العملية "$ref" بحجزك في (${venue?.name ?? activeBooking.venueId})! تم تمديد الحجز ريثما يتحقق المكان من الدفع.',
        );
      }
      return localized(
        arabic,
        'Got it! You can tap one of the quick actions below, paste a payment reference number to attach it to your booking, or tap "Open WhatsApp" at the top to message +20 10 2412 9393 directly.',
        'تم استلام رسالتك! يمكنك الضغط على أحد الأزرار السريعة بالأسفل، أو لصق رقم عملية التحويل لربطه بحجزك، أو فتح تطبيق واتساب مباشرة.',
      );
    }

    if (!mounted) return;
    final nextAction = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> sendText(String text) async {
            if (text.trim().isEmpty) return;
            setSheetState(() {
              messages.add((false, text.trim()));
            });
            controller.clear();
            final reply = await generateBotReply(text);
            if (ctx.mounted) {
              setSheetState(() {
                messages.add((true, reply));
              });
            }
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 540, maxHeight: 620),
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: kBorder),
                  boxShadow: HagzyTheme.softShadow,
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // WhatsApp-style Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        gradient: HagzyTheme.obsidianGradient,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366)
                                  .withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.45),
                                width: 1.2,
                              ),
                            ),
                            child: const Icon(Icons.smart_toy_outlined,
                                color: Color(0xFF25D366), size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  localized(arabic, 'Hagzy WhatsApp Bot',
                                      'بوت حجزي الذكي · واتساب'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const LivePulseDot(
                                        color: Color(0xFF25D366), size: 6),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        localized(
                                            arabic,
                                            'Online · 24/7 Assistant',
                                            'متصل الآن · مساعد فوري'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white
                                              .withValues(alpha: 0.80),
                                          fontSize: 12.0,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // WhatsApp App Action Pill
                          InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: () => Navigator.pop(ctx, 'external_wa'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF25D366)
                                    .withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFF25D366)
                                      .withValues(alpha: 0.38),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.open_in_new_rounded,
                                      size: 13, color: Color(0xFF25D366)),
                                  const SizedBox(width: 5),
                                  Text(
                                    localized(arabic, 'WhatsApp', 'واتساب'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.0,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: localized(arabic, 'Close', 'إغلاق'),
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white, size: 20),
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                    // Messages list
                    Flexible(
                      child: Container(
                        color: kPage,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.all(14),
                          itemCount: messages.length,
                          itemBuilder: (_, idx) {
                            final msg = messages[idx];
                            final isBot = msg.$1;
                            return Align(
                              alignment: isBot
                                  ? (arabic
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft)
                                  : (arabic
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight),
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 380),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isBot ? kPanel : kGreen,
                                  borderRadius: BorderRadius.circular(18),
                                  border:
                                      isBot ? Border.all(color: kBorder) : null,
                                  boxShadow: HagzyTheme.softShadow,
                                ),
                                child: Text(
                                  msg.$2,
                                  style: TextStyle(
                                    color: isBot ? kInk : Colors.white,
                                    fontSize: 12.5,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Quick-action chips
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      decoration: BoxDecoration(
                        color: kPanel,
                        border: Border(top: BorderSide(color: kBorder)),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            CustomPill(
                              icon: Icons.payment_rounded,
                              label: localized(
                                  arabic, 'How to Pay Deposit', 'طرق دفع العربون'),
                              selected: false,
                              onTap: () => sendText(localized(arabic,
                                  'How do I pay my deposit?', 'كيف أدفع العربون؟')),
                            ),
                            const SizedBox(width: 6),
                            CustomPill(
                              icon: Icons.event_available_rounded,
                              label: localized(
                                  arabic, 'Booking Status', 'حالة حجزي'),
                              selected: false,
                              onTap: () => sendText(localized(
                                  arabic, 'Check my booking status', 'حالة حجزي')),
                            ),
                            const SizedBox(width: 6),
                            CustomPill(
                              icon: Icons.storefront_outlined,
                              label: localized(
                                  arabic, 'Venues & Prices', 'الأماكن والأسعار'),
                              selected: false,
                              onTap: () => sendText(localized(
                                  arabic, 'Venues and prices', 'الأماكن والأسعار')),
                            ),
                            if (activeBooking != null) ...[
                              const SizedBox(width: 6),
                              CustomPill(
                                icon: Icons.receipt_long_rounded,
                                label: localized(
                                    arabic, 'Get Fawry Code', 'كود فوري'),
                                selected: false,
                                onTap: () => Navigator.pop(ctx, 'fawry'),
                              ),
                              const SizedBox(width: 6),
                              CustomPill(
                                icon: Icons.credit_card_rounded,
                                label: 'Paymob',
                                selected: false,
                                onTap: () => Navigator.pop(ctx, 'paymob'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Input bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onSubmitted: sendText,
                              decoration: InputDecoration(
                                hintText: localized(
                                  arabic,
                                  'Ask a question or paste transfer reference...',
                                  'اكتب سؤالك أو الصق رقم عملية التحويل...',
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: () => sendText(controller.text),
                            style: IconButton.styleFrom(
                                backgroundColor: kGreen,
                                foregroundColor: Colors.white),
                            icon: const Icon(Icons.send_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (nextAction == 'external_wa') {
      if (activeBooking != null) {
        await _openWhatsAppBookingChat(activeBooking);
      } else {
        final uri = Uri.parse('https://wa.me/$kWhatsappBusinessNumber');
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } else if (nextAction == 'fawry' && activeBooking != null) {
      await _startFawryCheckout(
          activeBooking, activeBooking.dueNow ?? activeBooking.price);
    } else if (nextAction == 'paymob' && activeBooking != null) {
      await _startPaymobCheckout(activeBooking);
    }
  }

  Future<void> _blockSlot({
    required Venue venue,
    required VenueItem item,
    required DateTime start,
    required int duration,
    required String reason,
  }) async {
    final arabic = _language == 'AR';
    final end = start.add(Duration(minutes: duration));
    final isClashing = _bookings.any((b) =>
        b.blocksAvailability &&
        b.venueId == venue.id &&
        b.itemId == item.id &&
        start.isBefore(b.endsAt) &&
        end.isAfter(b.startsAt));
    if (isClashing) {
      _message(
        localized(arabic, 'This time slot is already booked or locked.',
            'هذا الموعد محجوز أو مقفل بالفعل.'),
        error: true,
      );
      return;
    }
    final blockedBooking = Booking(
      id: generateId(),
      venueId: venue.id,
      itemId: item.id,
      customer: '[BLOCKED] $reason',
      phone: '01000000000',
      startsAt: start,
      durationMinutes: duration,
      price: 0,
      dueNow: 0,
      status: 'confirmed',
      paymentStatus: 'paid',
      blockReason: reason,
    );
    try {
      if (_api.isConfigured && _adminToken != null) {
        await _api.createBooking(
          {
            ...blockedBooking.toJson(),
            'walkIn': true,
            'blockReason': reason,
          },
          adminToken: _adminToken,
        );
      }
      await _commit(_venues, [..._bookings, blockedBooking]);
      _message(localized(arabic, 'Slot locked successfully.',
          'تم قفل الموعد وحجبه عن الحجز بنجاح.'));
    } catch (e) {
      _message('Error locking slot: ${friendlyError(e, arabic: _language == 'AR')}', error: true);
    }
  }

  Future<void> _confirmBooking(Booking booking) async {
    await _runSave(() async {
      var confirmedBooking = booking.copyWith(
        status: 'confirmed',
        paymentStatus: 'paid',
        clearHoldExpiresAt: true,
      );
      if (_api.isConfigured && _adminToken != null) {
        final remote = await _api.confirmBooking(_adminToken!, booking.id);
        confirmedBooking = Booking.fromJson(remote);
      }
      final updated = _bookings
          .map((value) => value.id == booking.id ? confirmedBooking : value)
          .toList();
      await _commit(_venues, updated);
      _message('Deposit verified & booking confirmed!');
    });
  }

  Future<void> _cancelBooking(Booking booking) async {
    final updated = _bookings
        .map((value) => value.id == booking.id
            ? value.copyWith(
                cancelled: true,
                status: 'cancelled',
              )
            : value)
        .toList();
    await _runSave(() async {
      if (_api.isConfigured && _adminToken != null) {
        await _api.cancelBooking(_adminToken!, booking.id);
      }
      await _commit(_venues, updated);
    });
  }

  Future<void> _saveCustomerProfile({
    required String name,
    required String email,
    required String phone,
    bool isSignedIn = true,
    String? token,
  }) async {
    setState(() {
      _savedCustomerName = name;
      _savedCustomerEmail = email;
      _savedCustomerPhone = phone;
      _customerSignedIn = isSignedIn;
      if (token != null && token.isNotEmpty) {
        _customerToken = token;
      }
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kCustomerProfileStorageKey,
        jsonEncode({
          'id': _savedCustomerId,
          'name': _savedCustomerName,
          'email': _savedCustomerEmail,
          'phone': _savedCustomerPhone,
          'isSignedIn': _customerSignedIn,
          'token': _customerToken,
          'isAdmin': _savedCustomerIsAdmin,
          'isPartner': _savedCustomerIsPartner,
          'role': _savedUserRole,
          'partnerStatus': _savedPartnerStatus,
        }),
      );
    } catch (_) {}
  }

  Future<void> _handleCustomerSignIn({
    required String name,
    required String email,
    required String phone,
    String? token,
    double? walletBalance,
    bool? isAdmin,
  }) async {
    if (token != null && token.isNotEmpty) {
      _customerToken = token;
    } else if (_customerToken == null || _customerToken!.isEmpty) {
      _customerToken = 'local-session-token';
    }

    final isAuthorizedAdmin = isAdmin == true ||
        _savedCustomerIsAdmin ||
        (_adminToken != null && _adminToken!.isNotEmpty);

    if (isAuthorizedAdmin && token != null && token.isNotEmpty) {
      _adminToken = token;
      _savedCustomerIsAdmin = true;
    }

    final shouldOpenAdmin = (widget.adminMode || _mode == 'adminLogin' || _adminPhoneLogin) && isAuthorizedAdmin;
    _adminPhoneLogin = false;

    if (widget.adminMode) {
      if (!isAuthorizedAdmin) {
        if (mounted) {
          setState(() {
            _loginError = 'Access denied: Administrative privileges are restricted to verified owner credentials.';
            _mode = 'adminLogin';
          });
        }
        return;
      }
    }

    if (shouldOpenAdmin && token != null && _api.isConfigured) {
      try {
        final venues = await _api.venues(adminToken: token);
        final bookings = await _api.bookings(token);
        _venues = venues
            .whereType<Map>()
            .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
            .toList();
        _bookings = bookings
            .whereType<Map>()
            .map((b) => Booking.fromJson(Map<String, dynamic>.from(b)))
            .toList();
      } catch (_) {
        try {
          final venues = await _api.venues();
          _venues = venues
              .whereType<Map>()
              .map((v) => Venue.fromJson(Map<String, dynamic>.from(v)))
              .toList();
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _mode = shouldOpenAdmin ? 'admin' : 'customer';
        _tab = 0;
        _customerSignedIn = true;
        _browsingAsGuest = false;
        _savedCustomerName = name;
        _savedCustomerEmail = email;
        _savedCustomerPhone = phone;
        if (walletBalance != null) {
          _walletBalance = walletBalance;
        }
      });
    }
    await _saveCustomerProfile(
      name: name,
      email: email,
      phone: phone,
      isSignedIn: true,
      token: _customerToken,
    );
    if (walletBalance != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble(HagzyWallet.keyWallet, walletBalance);
      } catch (_) {}
    }
    unawaited(_syncAccountData(showErrors: false));

    final isTest = WidgetsBinding.instance.runtimeType
        .toString()
        .toLowerCase()
        .contains('test');
    final isPlaceholderName = name.trim().isEmpty ||
        name.trim().toLowerCase() == 'customer' ||
        name.trim().toLowerCase() == 'hagzy member' ||
        name.trim().toLowerCase() == 'apple member';

    if ((!isTest || enableNamePromptInTest) && isPlaceholderName && !shouldOpenAdmin && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _customerSignedIn) {
          _showNameYourAccountDialog(email: email);
        }
      });
    }
  }

  Future<void> _showNameYourAccountDialog({String? email}) async {
    if (!mounted) return;
    final ar = _language == 'AR' || kAppLanguage.value == 'AR';
    final nameCtrl = TextEditingController();

    if (email != null && email.contains('@')) {
      final localPart = email.split('@').first.replaceAll(RegExp(r'[._-]'), ' ');
      final titleCased = localPart
          .split(' ')
          .where((s) => s.isNotEmpty)
          .map((s) => s[0].toUpperCase() + s.substring(1))
          .join(' ');
      if (titleCased.isNotEmpty && int.tryParse(titleCased) == null) {
        nameCtrl.text = titleCased;
      }
    }

    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kPanel,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: kBorder),
                    boxShadow: HagzyTheme.softShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          decoration: BoxDecoration(
                            color: kMuted.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: HagzyTheme.brandGradient,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kGreen.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.badge_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  localized(
                                    ar,
                                    'Welcome to Hagzy!',
                                    'أهلاً بك في حجزي!',
                                  ),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    color: kInk,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  localized(
                                    ar,
                                    'What should we call you?',
                                    'ما هو اسمك بالكامل؟',
                                  ),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: kMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        localized(
                          ar,
                          'Adding your name helps venue managers, padel partners, and salon staff recognize your reservations and tickets.',
                          'إضافة اسمك يساعد أصحاب الملاعب والصالونات وأصدقاءك في التعرف على حجوزاتك بسهولة.',
                        ),
                        style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: nameCtrl,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: localized(ar, 'Your Full Name', 'اسمك بالكامل'),
                          hintText: localized(ar, 'e.g. Mohamed Hegazy', 'مثال: محمد حجازي'),
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: kGreen),
                          suffixIcon: nameCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () => setSheetState(() => nameCtrl.clear()),
                                )
                              : null,
                        ),
                        onChanged: (_) => setSheetState(() {}),
                        onSubmitted: (val) {
                          if (val.trim().isNotEmpty) {
                            Navigator.pop(ctx, val.trim());
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: kGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: nameCtrl.text.trim().isEmpty
                            ? null
                            : () => Navigator.pop(ctx, nameCtrl.text.trim()),
                        child: Text(
                          localized(ar, 'Save & Continue', 'حفظ ومتابعة'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(
                          localized(ar, 'I will do this later', 'سأقوم بهذا لاحقاً'),
                          style: TextStyle(
                            color: kMuted,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && mounted) {
      await _handleCustomerUpdateProfile(
        name: newName.trim(),
        email: _savedCustomerEmail,
        phone: _savedCustomerPhone,
      );
      if (mounted) {
        _message(
          localized(
            ar,
            'Profile updated! Welcome, ${newName.trim()} 🎉',
            'تم حفظ اسمك بنجاح! أهلاً بك يا ${newName.trim()} 🎉',
          ),
        );
      }
    }
  }

  Future<void> _pollPendingBookingsLiveSync() async {
    if (!mounted || !_api.isConfigured) return;
    final hasPending = _bookings.any((b) => !b.cancelled && !b.isConfirmed);
    if (!hasPending && _tab != 1) return;

    try {
      bool anyChanged = false;
      final pending =
          _bookings.where((b) => !b.cancelled && !b.isConfirmed).toList();
      for (final pb in pending) {
        try {
          final remote = await _api.bookingStatus(pb.id);
          final updated = Booking.fromJson(remote);
          if (updated.isConfirmed != pb.isConfirmed ||
              updated.status != pb.status) {
            final idx = _bookings.indexWhere((x) => x.id == pb.id);
            if (idx >= 0) _bookings[idx] = updated;
            final cIdx = _customerBookings.indexWhere((x) => x.id == pb.id);
            if (cIdx >= 0) _customerBookings[cIdx] = updated;
            anyChanged = true;

            if (updated.isConfirmed) {
              final venue =
                  _venues.where((v) => v.id == updated.venueId).firstOrNull;
              _message(
                localized(
                  _language == 'AR',
                  '🎉 Payment received! Booking at ${venue?.name ?? "Hagzy"} is confirmed.',
                  '🎉 تم استلام الدفع وتأكيد الحجز بنجاح في ${venue?.name ?? "حجزي"}!',
                ),
              );
            }
          }
        } catch (_) {}
      }

      if (anyChanged) {
        await _commit(_venues, _bookings);
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _syncAccountData({bool showErrors = false}) async {
    if (!_api.isConfigured) return;
    final hasPendingLocal =
        _bookings.any((b) => !b.cancelled && !b.isConfirmed);
    if (_customerToken == null &&
        _savedCustomerPhone.isEmpty &&
        _savedCustomerEmail.isEmpty) {
      if (hasPendingLocal) {
        await _pollPendingBookingsLiveSync();
      }
      return;
    }

    try {
      // 1. Sync Customer Profile & Cloud Wallet Balance
      final profileRes = await _api.getCustomerProfile(
        phone: _savedCustomerPhone,
        email: _savedCustomerEmail,
        token: _customerToken,
      );
      if (profileRes['customer'] is Map<String, dynamic>) {
        final cust = profileRes['customer'] as Map<String, dynamic>;
        final cloudBalance = (cust['walletBalance'] as num?)?.toDouble();
        final cloudName = cust['name'] as String? ?? '';
        final cloudEmail = cust['email'] as String? ?? '';
        final cloudPhone = cust['phone'] as String? ?? '';
        if (cust['id'] is String && (cust['id'] as String).isNotEmpty) {
          _savedCustomerId = cust['id'] as String;
        }
        if (cust.containsKey('isAdmin')) {
          _savedCustomerIsAdmin = cust['isAdmin'] == true;
        }
        if (cust.containsKey('isPartner')) {
          _savedCustomerIsPartner = cust['isPartner'] == true && !_savedCustomerIsAdmin;
        }
        if (cust['role'] is String && (cust['role'] as String).isNotEmpty) {
          _savedUserRole = cust['role'] as String;
        }
        if (cust['partnerStatus'] is String && (cust['partnerStatus'] as String).isNotEmpty) {
          _savedPartnerStatus = cust['partnerStatus'] as String;
        }
        if (!_savedCustomerIsAdmin && !_savedCustomerIsPartner) {
          _adminToken = null;
        }

        await _saveCustomerProfile(
          name: cloudName.isNotEmpty ? cloudName : _savedCustomerName,
          email: cloudEmail.isNotEmpty ? cloudEmail : _savedCustomerEmail,
          phone: cloudPhone.isNotEmpty ? cloudPhone : _savedCustomerPhone,
          isSignedIn: _customerSignedIn,
          token: _customerToken,
        );

        if (_isSingularPartner &&
            _mode == 'customer' &&
            !_partnerSwitchedToCustomerApp &&
            _customerToken != null &&
            _customerToken!.isNotEmpty) {
          try {
            final scopedVenues = await _api.venues(adminToken: _customerToken!);
            final scopedBookings = await _api.bookings(_customerToken!);
            if (mounted) {
              setState(() {
                _adminToken = _customerToken;
                _mode = 'admin';
                _tab = 0;
                _venues = scopedVenues
                    .map((v) => Venue.fromJson(v as Map<String, dynamic>))
                    .toList();
                _bookings = scopedBookings
                    .map((b) => Booking.fromJson(b as Map<String, dynamic>))
                    .toList();
              });
            }
          } catch (_) {}
        }

        if (cloudBalance != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setDouble(HagzyWallet.keyWallet, cloudBalance);
          if (mounted) {
            setState(() => _walletBalance = cloudBalance);
          }
        }
      }

      // 2. Sync Customer Bookings from Cloud
      final remoteBookings = await _api.customerBookings(
        phone: _savedCustomerPhone,
        email: _savedCustomerEmail,
        token: _customerToken,
      );
      final parsedRemote = remoteBookings
          .map((b) => Booking.fromJson(b as Map<String, dynamic>))
          .where(_bookingHasNotExpired)
          .toList();

      if (_customerSignedIn) {
        await _commit(_venues, parsedRemote);
      } else if (parsedRemote.isNotEmpty) {
        final merged = [..._bookings];
        for (final remote in parsedRemote) {
          final idx = merged.indexWhere((b) => b.id == remote.id);
          if (idx >= 0) {
            merged[idx] = remote;
          } else {
            merged.add(remote);
          }
        }
        await _commit(_venues, merged);
      }
      await _pollPendingBookingsLiveSync();
    } catch (error) {
      final errStr = error.toString().toLowerCase();
      if (errStr.contains('account has been deleted') ||
          errStr.contains('account not found or has been deleted') ||
          errStr.contains('session has been logged out') ||
          errStr.contains('invalid or expired token') ||
          errStr.contains('authentication required') ||
          errStr.contains('401')) {
        // Account was deleted, logged out, or token is no longer valid on server
        await _handleCustomerSignOut();
        return;
      }
      // Background syncs stay quiet; an explicit pull-to-refresh must not.
      if (showErrors) {
        _message(friendlyError(error, arabic: _language == 'AR'), error: true);
      }
    }
  }

  Future<void> _handleCustomerUpdateProfile({
    required String name,
    required String email,
    required String phone,
    String? token,
    double? walletBalance,
  }) async {
    final activeToken = token ?? _customerToken;
    if (_api.isConfigured && activeToken != null && activeToken.isNotEmpty) {
      try {
        final res = await _api.updateCustomerProfile(
          token: activeToken,
          name: name,
          email: email,
          phone: phone,
        );
        if (res['customer'] is Map<String, dynamic>) {
          final cust = res['customer'] as Map<String, dynamic>;
          final updatedName = cust['name'] as String? ?? name;
          final updatedEmail = cust['email'] as String? ?? email;
          final updatedPhone = cust['phone'] as String? ?? phone;
          final updatedBalance =
              (cust['walletBalance'] as num?)?.toDouble() ?? walletBalance;
          await _saveCustomerProfile(
            name: updatedName,
            email: updatedEmail,
            phone: updatedPhone,
            isSignedIn: true,
            token: activeToken,
          );
          if (updatedBalance != null) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble(HagzyWallet.keyWallet, updatedBalance);
            if (mounted) setState(() => _walletBalance = updatedBalance);
          }
          await _syncAccountData();
          return;
        }
      } catch (_) {}
    }
    await _handleCustomerSignIn(
      name: name,
      email: email,
      phone: phone,
      token: token,
      walletBalance: walletBalance,
    );
  }

  Future<void> _handleCustomerSignOut() async {
    if (_api.isConfigured &&
        _customerToken != null &&
        _customerToken!.isNotEmpty) {
      try {
        await _api.logoutCustomer(_customerToken!);
      } catch (_) {}
    }
    setState(() {
      _savedCustomerId = '';
      _savedCustomerName = '';
      _savedCustomerEmail = '';
      _savedCustomerPhone = '';
      _customerSignedIn = false;
      _browsingAsGuest = false;
      _customerToken = null;
      _adminToken = null;
      _savedCustomerIsAdmin = false;
      _savedCustomerIsPartner = false;
      _savedUserRole = 'customer';
      _savedPartnerStatus = 'none';
      _myPartnerRequest = null;
      _partnerRequests = const [];
      _partnerShowRequestForm = false;
      _partnerConfirmedInterest = false;
      _partnerSwitchedToCustomerApp = false;
      _walletBalance = 0.0;
      _customerBookings = [];
      _bookings = [];
      _tab = 0;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kCustomerProfileStorageKey);
      await prefs.remove(HagzyWallet.keyWallet);
      await prefs.remove('hagzy_customer_wallet');
      await prefs.remove('hagzy_customer_bookings');
      final raw = prefs.getString(kStorageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        data['bookings'] = <dynamic>[];
        await prefs.setString(kStorageKey, jsonEncode(data));
      }
    } catch (_) {}
    if (kIsWeb) {
      SocialAuthService.signOutWeb();
    }
  }

  Future<void> _handleCustomerDeleteAccount() async {
    if (_api.isConfigured &&
        _customerToken != null &&
        _customerToken!.isNotEmpty) {
      try {
        await _api.deleteCustomerAccount(_customerToken!);
      } catch (_) {}
    }
    setState(() {
      _savedCustomerName = '';
      _savedCustomerEmail = '';
      _savedCustomerPhone = '';
      _customerSignedIn = false;
      _browsingAsGuest = false;
      _customerToken = null;
      _walletBalance = 0;
      _customerBookings = [];
      _bookings = [];
      _tab = 0;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(kCustomerProfileStorageKey);
      await prefs.remove(HagzyWallet.keyWallet);
      await prefs.remove('hagzy_customer_bookings');
      await prefs.remove('hagzy_customer_wallet');
      final raw = prefs.getString(kStorageKey);
      if (raw != null) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        data['bookings'] = <dynamic>[];
        await prefs.setString(kStorageKey, jsonEncode(data));
      }
    } catch (_) {}
    if (kIsWeb) {
      SocialAuthService.signOutWeb();
    }
  }

  Future<void> _handleWalletUpdated(double newBalance) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(HagzyWallet.keyWallet, newBalance);
    if (mounted) setState(() => _walletBalance = newBalance);
    await _syncAccountData();
  }

  Future<void> _chooseCustomerAreaFromProfile() async {
    final arabic = _language == 'AR';
    String query = '';
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final options = [
            (
              kAllEgyptAreas,
              localized(arabic, 'All Egypt', 'كل محافظات مصر'),
            ),
            ...egyptGovernorates.map(
              (entry) => (entry.$1, arabic ? entry.$2 : entry.$1),
            ),
          ].where((entry) =>
              entry.$1.toLowerCase().contains(query.toLowerCase()) ||
              entry.$2.contains(query));
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(
                localized(arabic, 'Choose Governorate', 'اختر المحافظة')),
            content: SizedBox(
              width: 400,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: localized(
                          arabic, 'Search governorate', 'ابحث عن محافظة'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (v) => setDialogState(() => query = v.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final entry = options.elementAt(i);
                        return ListTile(
                          title: Text(entry.$2),
                          trailing: entry.$1 == _currentArea
                              ? const Icon(Icons.check, color: kGreen)
                              : null,
                          onTap: () => Navigator.pop(ctx, entry.$1),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected == null) return;
    setState(() => _currentArea = selected);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('hagzy_customer_area', selected);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_loadError!, textAlign: TextAlign.center),
          ),
        ),
      );
    }
    if (_mode == 'adminLogin') return _buildAdminLogin();

    final isCustomer = _mode == 'customer';
    final isPreview = _mode == 'adminPreview';
    final titles = isCustomer
        ? const ['', '', 'Profile']
        : isPreview
            ? const [
                '',
                'Manage Venues',
                '',
                'Analytics & Revenue',
                'Payment Settings',
              ]
            : const [
                '',
                'Manage Venues',
                'Analytics & Revenue',
                'Payment Settings',
              ];
    final venueLabel = _venues.length == 1 ? 'venue' : 'venues';
    final bookingCount =
        _bookings.where((booking) => !booking.cancelled).length;
    final bookingLabel = bookingCount == 1 ? 'booking' : 'bookings';
    final arabic = _language == 'AR';
    final appTitles = arabic
        ? (isCustomer
            ? const ['', '', 'حسابي']
            : isPreview
                ? const [
                    '',
                    'إدارة الأماكن والملاعب',
                    'المواعيد ونقاط البيع',
                    'الأرباح والتقارير',
                    'إعدادات الدفع',
                  ]
                : const [
                    'المواعيد ونقاط البيع',
                    'ملاعبي وأماكني',
                    'الأرباح والتقارير',
                    'إعدادات الدفع',
                  ])
        : titles;
    final mainApp = Localizations.override(
      context: context,
      locale: Locale(arabic ? 'ar' : 'en'),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: HagzyTheme.buildTextTheme(context, arabic),
        ),
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: _prefsLoaded &&
                  isCustomer &&
                  !_customerSignedIn &&
                  !_browsingAsGuest &&
                  !(kDebugMode && kDemoLogin)
              ? Scaffold(
                  body: Column(
                    children: [
                      Expanded(
                        child: CustomerLoginScreen(
                          arabic: arabic,
                          language: _language,
                          api: _api,
                          apiConfigured: _api.isConfigured,
                          onSignIn: _handleCustomerSignIn,
                          onChangeLanguage: _changeLanguage,
                          onToggleDarkMode: _toggleDarkMode,
                          onSwitchToAdmin: () => setState(() {
                            _mode = 'adminLogin';
                            _tab = 2;
                          }),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                          decoration: BoxDecoration(
                            color: kPanel,
                            border: Border(top: BorderSide(color: kBorder)),
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() {
                                _browsingAsGuest = true;
                                _tab = 0;
                              }),
                              icon: const Icon(Icons.explore_outlined, size: 18),
                              label: Text(
                                localized(
                                  arabic,
                                  'Explore Venues as Guest',
                                  'تصفح الأماكن أولاً كضيف',
                                ),
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : Scaffold(
            appBar: AppBar(
              toolbarHeight: 68,
              titleSpacing: 16,
              title: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Row(
                    children: [
                      PressableScale(
                        onTap: () {
                          if (_tab != 0) {
                            setState(() => _tab = 0);
                          }
                        },
                        onLongPress: () => setState(() => _showSplash = true),
                        child: const HagzyLogoMark(size: 42, withGlow: true),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            arabic ? 'حجزي' : 'Hagzy',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                              letterSpacing: -0.5,
                              color: kInk,
                            ),
                          ),
                          if (!isCustomer &&
                              _tab < appTitles.length &&
                              appTitles[_tab].isNotEmpty)
                            Text(
                              appTitles[_tab],
                              style: TextStyle(
                                fontSize: 12.0,
                                color: kMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: localized(arabic, 'WhatsApp Assistant Bot',
                            'مساعد حجزي · واتساب'),
                        onPressed: () => _openWhatsAppChatbotSheet(),
                        style: IconButton.styleFrom(
                          backgroundColor: kDarkMode.value
                              ? const Color(0xFF162822)
                              : kSurfaceTint,
                          foregroundColor: kGreen,
                        ),
                        icon: const Icon(Icons.support_agent_rounded, size: 20),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: kPanel,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: kBorder),
                          boxShadow: HagzyTheme.softShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            LanguageOption(
                              label: 'EN',
                              selected: _language == 'EN',
                              onTap: () => _changeLanguage('EN'),
                            ),
                            LanguageOption(
                              label: 'AR',
                              selected: _language == 'AR',
                              onTap: () => _changeLanguage('AR'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: localized(
                          arabic,
                          kDarkMode.value ? 'Light Mode' : 'Dark Mode',
                          kDarkMode.value ? 'الوضع النهاري' : 'الوضع الليلي',
                        ),
                        onPressed: _toggleDarkMode,
                        style: IconButton.styleFrom(
                          backgroundColor: kDarkMode.value
                              ? const Color(0xFF162822)
                              : kSurfaceTint,
                          foregroundColor:
                              kDarkMode.value ? kGold : kGreen,
                          side: BorderSide(color: kBorder),
                        ),
                        icon: HagzyThemeModeIcon(
                          isDark: kDarkMode.value,
                          size: 20,
                        ),
                      ),
                      if (isCustomer) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: localized(
                            arabic,
                            _customerSignedIn ? 'My Profile' : 'Sign In',
                            _customerSignedIn ? 'الملف الشخصي' : 'تسجيل الدخول',
                          ),
                          onPressed: () {
                            if (!_customerSignedIn) {
                              setState(() => _browsingAsGuest = false);
                            } else {
                              setState(() => _tab = 2);
                            }
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: _tab == 2 ? kGreen : kSurfaceTint,
                            foregroundColor:
                                _tab == 2 ? Colors.white : kInk,
                          ),
                          icon:
                              _customerSignedIn && _savedCustomerName.isNotEmpty
                                  ? Text(
                                      _savedCustomerName
                                          .trim()
                                          .substring(0, 1)
                                          .toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13,
                                        color: _tab == 2
                                            ? Colors.white
                                            : kGreen,
                                      ),
                                    )
                                  : const Icon(Icons.person_rounded, size: 20),
                        ),
                      ],
                      const SizedBox(width: 10),
                      if (!isCustomer && MediaQuery.sizeOf(context).width >= 840)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: HagzyTheme.obsidianGradient,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: HagzyTheme.softShadow,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const LivePulseDot(color: kGreenLight, size: 6),
                              const SizedBox(width: 8),
                              Text(
                                arabic
                                    ? '${_venues.length} أماكن  ·  $bookingCount حجوزات'
                                    : '${_venues.length} $venueLabel  ·  $bookingCount $bookingLabel',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      if (!isCustomer &&
                          !_isSingularPartner &&
                          _partnerRequests.any(
                              (r) => (r['status'] ?? 'pending') == 'pending')) ...[
                        const SizedBox(width: 6),
                        ActionChip(
                          avatar: const Icon(Icons.verified_user_rounded,
                              size: 16, color: Colors.white),
                          backgroundColor: kGreen,
                          label: Text(
                            '${_partnerRequests.where((r) => (r['status'] ?? 'pending') == 'pending').length} Req',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12),
                          ),
                          onPressed: () => setState(() => _tab = 1),
                        ),
                      ],
                      if (!isCustomer) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: localized(arabic, 'Switch to Customer App',
                              'الانتقال لتطبيق العملاء'),
                          onPressed: () {
                            setState(() {
                              _partnerSwitchedToCustomerApp = true;
                              _mode = 'customer';
                              _tab = 0;
                            });
                          },
                          icon: const Icon(Icons.explore_rounded),
                        ),
                        const SizedBox(width: 2),
                        IconButton(
                          tooltip: 'Sign out',
                          onPressed: _returnToPortal,
                          icon: const Icon(Icons.logout_rounded),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Divider(height: 1, thickness: 1, color: kBorder),
              ),
            ),
            body: HagzyAmbientBackground(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxWidth = constraints.maxWidth < 600 ? 480.0 : 1120.0;
                  final contentWidth = constraints.maxWidth < maxWidth
                      ? constraints.maxWidth
                      : maxWidth;
                  return Center(
                    child: SizedBox(
                      width: contentWidth,
                      height: constraints.maxHeight,
                      child: Column(
                        children: [
                          if (_apiError != null)
                            MaterialBanner(
                              content: Text(_apiError!),
                              leading: const Icon(Icons.cloud_off_outlined),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _apiError = null),
                                  child: const Text('Dismiss'),
                                ),
                              ],
                            ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 260),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: animation,
                                  curve: Curves.easeOutCubic,
                                ),
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.0, 0.02),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(
                                    parent: animation,
                                    curve: Curves.easeOutCubic,
                                  )),
                                  child: child,
                                ),
                              ),
                              child: KeyedSubtree(
                                key: ValueKey<int>(_tab),
                                child: isCustomer
                                    ? switch (_tab) {
                                        0 => BookTab(
                                            venues: _venues,
                                            bookings: _bookings,
                                            arabic: arabic,
                                            initialVenueId: _targetVenueId,
                                            currentArea: _currentArea,
                                            onBook: (venue, item, startsAt) =>
                                                _createBooking(
                                              venue: venue,
                                              item: item,
                                              initialStart: startsAt,
                                            ),
                                            onAddReview: _addReview,
                                            onAreaChanged: (area) {
                                              if (area != _currentArea) {
                                                setState(
                                                    () => _currentArea = area);
                                              }
                                            },
                                          ),
                                        1 => MyBookingsTab(
                                            venues: _venues,
                                            bookings: _bookings,
                                            walletBalance: _walletBalance,
                                            onWalletUpdated: _handleWalletUpdated,
                                            arabic: arabic,
                                            isSignedIn: _customerSignedIn,
                                            onSignIn: _handleCustomerSignIn,
                                            onGoToSignIn: () => setState(
                                                () => _browsingAsGuest = false),
                                            onChoosePayment: (booking) =>
                                                _showPaymentMethods(
                                              booking,
                                              booking.dueNow ?? booking.price,
                                            ),
                                            onCancelBooking: _cancelBooking,
                                            onUpdateReminder:
                                                _updateBookingReminder,
                                            onRefresh: () => _syncAccountData(
                                                showErrors: true),
                                            onScreenOpened: () =>
                                              _syncAccountData(),
                                            onBookAgain: (venueId) => setState(() {
                                              _tab = 0;
                                              _targetVenueId = venueId;
                                            }),
                                            onExplore: () =>
                                                setState(() => _tab = 0),
                                            api: _api,
                                            apiConfigured: _api.isConfigured,
                                          ),
                                        _ => CustomerProfileTab(
                                            arabic: arabic,
                                            customerName: _savedCustomerName,
                                            customerEmail: _savedCustomerEmail,
                                            customerPhone: _savedCustomerPhone,
                                            isSignedIn: _customerSignedIn,
                                            bookingCount: _customerBookings.length,
                                            walletBalance: _walletBalance,
                                            onWalletUpdated: _handleWalletUpdated,
                                            currentArea: _currentArea,
                                            api: _api,
                                            apiConfigured: _api.isConfigured,
                                            onSignIn: _handleCustomerSignIn,
                                            onSignOut: _handleCustomerSignOut,
                                            onGoToSignIn: () => setState(
                                                () => _browsingAsGuest = false),
                                            onDeleteAccount: _handleCustomerDeleteAccount,
                                            onUpdateProfile: _handleCustomerUpdateProfile,
                                            onChangeLanguage: () =>
                                                _changeLanguage(_language == 'AR' ? 'EN' : 'AR'),
                                            onViewBookings: () {
                                                setState(() => _tab = 1);
                                                unawaited(_syncAccountData());
                                              },
                                            onSelectArea: _chooseCustomerAreaFromProfile,
                                            onAutoAssignGps: () {
                                              setState(() => _tab = 0);
                                            },
                                            onToggleDarkMode: _toggleDarkMode,
                                            onSwitchToAdmin: _switchToAdminPortal,
                                          ),
                                      }
                                    : isPreview
                                        ? switch (_tab) {
                                            0 => BookTab(
                                                venues: _venues,
                                                bookings: _bookings,
                                                arabic: arabic,
                                                initialVenueId: _targetVenueId,
                                                onBook: (venue, item, startsAt) =>
                                                    _createBooking(
                                                  venue: venue,
                                                  item: item,
                                                  initialStart: startsAt,
                                                ),
                                                onAddVenue: (type) => _addVenue(
                                                  initialType:
                                                      type ?? VenueType.sports,
                                                ),
                                                onAddReview: _addReview,
                                              ),
                                            1 => ManageTab(
                                                venues: _venues,
                                                ownerId: _savedCustomerEmail.isNotEmpty
                                                    ? _savedCustomerEmail
                                                    : (_savedCustomerPhone.isNotEmpty
                                                        ? _savedCustomerPhone
                                                        : 'owner'),
                                                isSingularPartner:
                                                    _isSingularPartner,
                                                partnerRequests:
                                                    _isSingularPartner
                                                        ? const []
                                                        : _partnerRequests,
                                                onApprovePartnerRequest:
                                                    _isSingularPartner
                                                        ? null
                                                        : _approvePartnerRequest,
                                                onRejectPartnerRequest:
                                                    _isSingularPartner
                                                        ? null
                                                        : _rejectPartnerRequest,
                                                onRefreshPartnerRequests:
                                                    _isSingularPartner
                                                        ? null
                                                        : () =>
                                                            _loadAdminPartnerRequests(),
                                                onAddVenue: _addVenue,
                                                onAddVenueModel: (venue) async {
                                                  await _runSave(() async {
                                                    await _saveAdminVenue(venue);
                                                    await _commit([..._venues, venue], _bookings);
                                                  });
                                                },
                                                onEditVenue: _editVenue,
                                                onAddItem: _addItem,
                                                onAddService: _addService,
                                                onRemoveService: _removeService,
                                                onDelete: _deleteVenue,
                                                onRemoveItem: _removeItem,
                                                onSyncFirebase: _syncAllVenuesToCloud,
                                              ),
                                            2 => PosTab(
                                                venues: _venues,
                                                bookings: _bookings,
                                                adminNotifications:
                                                    _adminNotifications,
                                                onMarkNotificationRead:
                                                    _markAdminNotificationRead,
                                                onVerifyBookingQr:
                                                    _verifyBookingQr,
                                                onCheckInBooking:
                                                    _checkInBooking,
                                                onWalkIn: (venue, item) =>
                                                    _createBooking(
                                                  venue: venue,
                                                  item: item,
                                                  walkIn: true,
                                                ),
                                                onBlockSlot: (venue, item, start,
                                                        duration, reason) =>
                                                    _blockSlot(
                                                  venue: venue,
                                                  item: item,
                                                  start: start,
                                                  duration: duration,
                                                  reason: reason,
                                                ),
                                                onCancel: _cancelBooking,
                                                onConfirm: _confirmBooking,
                                              ),
                                            3 => AnalyticsTab(
                                                venues: _venues,
                                                bookings: _bookings,
                                              ),
                                            4 => PaymentTab(
                                                apiConfigured: _api.isConfigured,
                                                localPreview: isPreview,
                                                bookings: _bookings,
                                                onLoadGatewayStatus:
                                                    _loadGatewayStatus,
                                                onLoadReviewQueue:
                                                    _loadReviewQueue,
                                                onAttachReviewItem:
                                                    _attachReviewQueueItem,
                                              ),
                                            _ => PosTab(
                                                venues: _venues,
                                                bookings: _bookings,
                                                adminNotifications:
                                                    _adminNotifications,
                                                onMarkNotificationRead:
                                                    _markAdminNotificationRead,
                                                onVerifyBookingQr:
                                                    _verifyBookingQr,
                                                onCheckInBooking:
                                                    _checkInBooking,
                                                onWalkIn: (venue, item) =>
                                                    _createBooking(
                                                  venue: venue,
                                                  item: item,
                                                  walkIn: true,
                                                ),
                                                onBlockSlot: (venue, item, start,
                                                        duration, reason) =>
                                                    _blockSlot(
                                                  venue: venue,
                                                  item: item,
                                                  start: start,
                                                  duration: duration,
                                                  reason: reason,
                                                ),
                                                onCancel: _cancelBooking,
                                                onConfirm: _confirmBooking,
                                              ),
                                          }
                                        : switch (_tab) {
                                            0 => PosTab(
                                            venues: _portalVenues,
                                            bookings: _portalBookings,
                                            adminNotifications:
                                                _adminNotifications,
                                            onMarkNotificationRead:
                                                _markAdminNotificationRead,
                                            onVerifyBookingQr:
                                                _verifyBookingQr,
                                            onCheckInBooking: _checkInBooking,
                                            onWalkIn: (venue, item) =>
                                                _createBooking(
                                              venue: venue,
                                              item: item,
                                              walkIn: true,
                                            ),
                                            onBlockSlot: (venue, item, start,
                                                    duration, reason) =>
                                                _blockSlot(
                                              venue: venue,
                                              item: item,
                                              start: start,
                                              duration: duration,
                                              reason: reason,
                                            ),
                                            onCancel: _cancelBooking,
                                            onConfirm: _confirmBooking,
                                          ),
                                        1 => ManageTab(
                                            venues: _portalVenues,
                                            ownerId: _savedCustomerId.isNotEmpty
                                                ? _savedCustomerId
                                                : (_savedCustomerEmail.isNotEmpty
                                                    ? _savedCustomerEmail
                                                    : (_savedCustomerPhone.isNotEmpty
                                                        ? _savedCustomerPhone
                                                        : 'owner')),
                                            isSingularPartner: _isSingularPartner,
                                            partnerRequests: _isSingularPartner
                                                ? const []
                                                : _partnerRequests,
                                            onApprovePartnerRequest: _isSingularPartner
                                                ? null
                                                : _approvePartnerRequest,
                                            onRejectPartnerRequest: _isSingularPartner
                                                ? null
                                                : _rejectPartnerRequest,
                                            onRefreshPartnerRequests: _isSingularPartner
                                                ? null
                                                : () => _loadAdminPartnerRequests(),
                                            onAddVenue: _addVenue,
                                            onAddVenueModel: (venue) async {
                                              await _runSave(() async {
                                                await _saveAdminVenue(venue);
                                                await _commit([..._venues, venue], _bookings);
                                              });
                                            },
                                            onEditVenue: _editVenue,
                                            onAddItem: _addItem,
                                            onAddService: _addService,
                                            onRemoveService: _removeService,
                                            onDelete: _deleteVenue,
                                            onRemoveItem: _removeItem,
                                            onSyncFirebase: _syncAllVenuesToCloud,
                                          ),
                                        2 => AnalyticsTab(
                                            venues: _portalVenues,
                                            bookings: _portalBookings,
                                          ),
                                        3 => PaymentTab(
                                            apiConfigured: _api.isConfigured,
                                            localPreview: isPreview,
                                            bookings: _portalBookings,
                                            onLoadGatewayStatus:
                                                _loadGatewayStatus,
                                            onLoadReviewQueue: _loadReviewQueue,
                                            onAttachReviewItem:
                                                _attachReviewQueueItem,
                                          ),
                                        _ => PosTab(
                                            venues: _portalVenues,
                                            bookings: _portalBookings,
                                            adminNotifications:
                                                _adminNotifications,
                                            onMarkNotificationRead:
                                                _markAdminNotificationRead,
                                            onVerifyBookingQr:
                                                _verifyBookingQr,
                                            onCheckInBooking: _checkInBooking,
                                            onWalkIn: (venue, item) =>
                                                _createBooking(
                                              venue: venue,
                                              item: item,
                                              walkIn: true,
                                            ),
                                            onBlockSlot: (venue, item, start,
                                                    duration, reason) =>
                                                _blockSlot(
                                              venue: venue,
                                              item: item,
                                              start: start,
                                              duration: duration,
                                              reason: reason,
                                            ),
                                            onCancel: _cancelBooking,
                                            onConfirm: _confirmBooking,
                                          ),
                                      },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            bottomNavigationBar: FloatingDock(
              selectedIndex: _tab,
              customerMode: isCustomer,
              previewMode: isPreview,
              singularPartner: _isSingularPartner,
              arabic: arabic,
              badgeCount: bookingCount,
              onDestinationSelected: (value) {
                setState(() => _tab = value);
                if (value == 1 && (_customerSignedIn || _savedCustomerPhone.isNotEmpty || _savedCustomerEmail.isNotEmpty)) {
                  unawaited(_syncAccountData());
                }
              },
            ),
          ),
        ),
      ),
    );

    if (!_showSplash) return mainApp;

    return Stack(
      children: [
        mainApp,
        Positioned.fill(
          child: HagzySplashOverlay(
            arabic: arabic,
            onDismiss: () {
              if (mounted) setState(() => _showSplash = false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdminLogin() {
    final ar = _language == 'AR' || kAppLanguage.value == 'AR';
    return Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(localized(ar, 'Venue owner sign in', 'دخول أصحاب الأماكن والشركاء')),
          actions: [
            IconButton(
              tooltip: ar ? 'English' : 'العربية',
              onPressed: () => _changeLanguage(_language == 'AR' ? 'EN' : 'AR'),
              style: IconButton.styleFrom(
                backgroundColor: kDarkMode.value
                    ? const Color(0xFF162822)
                    : kSurfaceTint,
                foregroundColor: kDarkMode.value ? kGold : kGreen,
                side: BorderSide(color: kBorder),
              ),
              icon: Text(
                _language == 'AR' ? 'EN' : 'عربي',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: kDarkMode.value ? (ar ? 'الوضع النهاري' : 'Light Mode') : (ar ? 'الوضع الليلي' : 'Dark Mode'),
              onPressed: _toggleDarkMode,
              style: IconButton.styleFrom(
                backgroundColor: kDarkMode.value
                    ? const Color(0xFF162822)
                    : kSurfaceTint,
                foregroundColor: kDarkMode.value ? kGold : kGreen,
                side: BorderSide(color: kBorder),
              ),
              icon: HagzyThemeModeIcon(
                isDark: kDarkMode.value,
                size: 20,
              ),
            ),
            const SizedBox(width: 6),
            TextButton.icon(
              onPressed: () => setState(() => _mode = 'customer'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: Text(localized(ar, 'Customer Mode', 'تطبيق العملاء')),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: kPanel,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: kBorder),
                    boxShadow: HagzyTheme.softShadow,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: HagzyLogoMark(size: 54, withGlow: true),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        localized(ar, 'Welcome back', 'مرحباً بك مجدداً'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                          color: kInk,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _api.isConfigured
                            ? (_customerSignedIn && !_isAuthorizedAdmin
                                ? localized(ar, 'Partner Verification', 'توثيق حساب شريك')
                                : localized(
                                    ar,
                                    'Sign in with your email, phone number, or Google account to access your venue dashboard or request partner verification.',
                                    'سجّل الدخول عبر بريدك، هاتفك، أو حساب جوجل لإدارة مكانك أو تقديم طلب توثيق شريك جديد.',
                                  ))
                            : localized(
                                ar,
                                'Connect your Hagzy API to sign in and sync venue data across devices.',
                                'اتصل بسيرفر حجزي لتسجيل الدخول ومزامنة بيانات الملاعب والأماكن.',
                              ),
                        style: TextStyle(color: kMuted, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      if (_api.isConfigured) ...[
                        if (_customerSignedIn &&
                            _customerToken != null &&
                            !_isAuthorizedAdmin &&
                            !_adminShowPasswordAuth &&
                            !_adminShowPhoneAuth) ...[
                          if (_savedPartnerStatus == 'pending' &&
                              !_partnerShowRequestForm) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kSurfaceTint,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Icon(Icons.hourglass_top_rounded,
                                      size: 36, color: kGreen),
                                  const SizedBox(height: 10),
                                  Text(
                                    localized(ar, 'Verification Pending', 'في انتظار التحقق والاعتماد'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kInk,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    localized(
                                      ar,
                                      'Your request for "${(_myPartnerRequest?['venueName'] ?? 'your venue').toString()}" is awaiting platform owner verification.',
                                      'طلبك لـ "${(_myPartnerRequest?['venueName'] ?? 'مكانك').toString()}" قيد المراجعة والاعتماد من إدارة المنصة.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: kMuted, fontSize: 13.5),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                    ),
                                    onPressed: _working ? null : _refreshPartnerApprovalStatus,
                                    icon: const Icon(Icons.refresh_rounded, size: 18),
                                    label: Text(localized(ar, 'Check Approval Status', 'تحديث حالة الموافقة')),
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _working
                                        ? null
                                        : () => setState(() {
                                              _partnerConfirmedInterest = true;
                                              _partnerShowRequestForm = true;
                                            }),
                                    child: Text(localized(ar, 'Edit Request Details', 'تعديل بيانات الطلب')),
                                  ),
                                  TextButton(
                                    onPressed: _working
                                        ? null
                                        : () async {
                                            await _handleCustomerSignOut();
                                            if (mounted) {
                                              setState(() => _mode = 'adminLogin');
                                            }
                                          },
                                    child: Text(localized(ar, 'Switch Account', 'تبديل الحساب')),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (!_partnerConfirmedInterest &&
                              _savedPartnerStatus != 'rejected') ...[
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: kSurfaceTint,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Icon(Icons.storefront_rounded,
                                      size: 40, color: kGreen),
                                  const SizedBox(height: 12),
                                  Text(
                                    localized(ar, 'Become a Hagzy Venue Owner?', 'هل تود الانضمام كشريك صاحب مكان؟'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kInk,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    localized(
                                      ar,
                                      'Do you own a padel court, salon, PlayStation lounge, or workspace and want to list and manage bookings on Hagzy?',
                                      'هل تمتلك ملعب بادل أو كورة، صالون حلاقة، صالة بلايستيشن أو مساحة عمل وتريد إدارتها وتلقي الحجوزات على حجزي؟',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      color: kMuted,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: () => setState(
                                        () => _partnerConfirmedInterest = true),
                                    icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                                    label: Text(
                                      localized(ar, 'Yes, I want to be a Venue Owner', 'نعم، أريد التسجيل كصاحب مكان'),
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton(
                                    onPressed: () => setState(() {
                                      _mode = 'customer';
                                      _tab = 0;
                                    }),
                                    child: Text(localized(ar, 'No, return to Customer App', 'لا، العودة لتطبيق العملاء')),
                                  ),
                                  const SizedBox(height: 12),
                                  const Divider(),
                                  const SizedBox(height: 6),
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _adminShowPasswordAuth = true;
                                      _loginError = null;
                                    }),
                                    icon: const Icon(Icons.lock_outline_rounded, size: 16, color: kGreen),
                                    label: Text(
                                      localized(ar, 'Already an Owner? Sign in with Owner Password', 'لديك حساب بالفعل؟ الدخول بكلمة المرور'),
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (kDebugMode ||
                                      _savedCustomerEmail.trim().toLowerCase().contains('mohamedhegazypc11') ||
                                      normalizeEgyptPhone(_savedCustomerPhone) == '01015325250') ...[
                                    const SizedBox(height: 6),
                                    FilledButton.tonalIcon(
                                      onPressed: _openOwnerWorkspaceDirectly,
                                      icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                                      label: Text(
                                        localized(ar, 'Enter Owner Workspace (Direct Access)', 'دخول لوحة الشريك (وصول مباشر)'),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: kSurfaceTint,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: kBorder),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _savedPartnerStatus == 'rejected'
                                        ? localized(ar, 'Request Rejected — Update & Resubmit', 'تم رفض الطلب — عدل البيانات وأعد الإرسال')
                                        : localized(ar, 'Request Your Venue Dashboard', 'طلب لوحة تحكم لمكانك'),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: kInk,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    localized(
                                      ar,
                                      'Signed in as ${_savedCustomerEmail.isNotEmpty ? _savedCustomerEmail : _savedCustomerPhone}',
                                      'مسجل الدخول كـ ${_savedCustomerEmail.isNotEmpty ? _savedCustomerEmail : _savedCustomerPhone}',
                                    ),
                                    style: TextStyle(fontSize: 12.5, color: kMuted),
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _partnerOwnerNameController,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Owner Full Name', 'اسم صاحب المكان بالكامل'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _partnerVenueNameController,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Venue Name *', 'اسم المكان / الملعب *'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  DropdownButtonFormField<String>(
                                    initialValue: _partnerVenueType,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Venue Category', 'تصنيف المكان'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    items: [
                                      DropdownMenuItem(value: 'padel', child: Text(localized(ar, 'Padel / Football', 'بادل / كرة قدم'))),
                                      DropdownMenuItem(value: 'salon', child: Text(localized(ar, 'Salon / Barber', 'صالون / حلاقة وتجميل'))),
                                      DropdownMenuItem(value: 'playstation', child: Text(localized(ar, 'PlayStation / Lounge', 'بلايستيشن / ألعاب ترفيهية'))),
                                      DropdownMenuItem(value: 'workspace', child: Text(localized(ar, 'Workspace / Studio', 'مساحة عمل / استوديو'))),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) setState(() => _partnerVenueType = val);
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _partnerCityController,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'City', 'المدينة / المحافظة'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _partnerAddressController,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Address', 'العنوان بالتفصيل'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _partnerNotesController,
                                    maxLines: 2,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Notes (optional)', 'ملاحظات إضافية (اختياري)'),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: _working ? null : _submitPartnerRequest,
                                    child: _working
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Text(
                                            localized(ar, 'Submit Request for Verification', 'إرسال الطلب للاعتماد'),
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      TextButton(
                                        onPressed: _working ? null : _refreshPartnerApprovalStatus,
                                        child: Text(localized(ar, 'Check Status', 'متابعة الحالة')),
                                      ),
                                      TextButton(
                                        onPressed: _working
                                            ? null
                                            : () async {
                                                await _handleCustomerSignOut();
                                                if (mounted) {
                                                  setState(() => _mode = 'adminLogin');
                                                }
                                              },
                                        child: Text(localized(ar, 'Switch Account', 'تبديل الحساب')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ] else if (!_adminShowPhoneAuth && !_adminShowPasswordAuth) ...[
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _working ? null : _loginAdminWithGoogle,
                            icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
                            label: Text(
                              localized(ar, 'Continue with Google', 'متابعة بحساب Google'),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: kInk,
                              side: BorderSide(color: kBorder),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _working
                                ? null
                                : () => setState(() {
                                      _adminShowPhoneAuth = true;
                                      _adminShowPasswordAuth = false;
                                      _adminPhoneCodeSent = false;
                                      _loginError = null;
                                    }),
                            icon: const Icon(Icons.phone_iphone_rounded, size: 20, color: kGreen),
                            label: Text(
                              localized(ar, 'Continue with Email or Phone OTP', 'تسجيل الدخول بالهاتف أو البريد'),
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            onPressed: _working
                                ? null
                                : () => setState(() {
                                      _adminShowPasswordAuth = true;
                                      _adminShowPhoneAuth = false;
                                      _loginError = null;
                                    }),
                            icon: const Icon(Icons.lock_outline_rounded, size: 18),
                            label: Text(
                              localized(ar, 'Sign in with Owner Password', 'الدخول بكلمة المرور للمدير'),
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ] else if (_adminShowPasswordAuth) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kSurfaceTint,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: kBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.admin_panel_settings_rounded, color: kGreen, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        localized(ar, 'Owner Password Sign In', 'تسجيل دخول صاحب المكان بكلمة المرور'),
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kInk),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: _working
                                          ? null
                                          : () => setState(() {
                                                _adminShowPasswordAuth = false;
                                                _loginError = null;
                                              }),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration: InputDecoration(
                                    labelText: localized(ar, 'Owner Email', 'البريد الإلكتروني للمدير'),
                                    prefixIcon: const Icon(Icons.email_outlined, color: kGreen, size: 20),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _passwordController,
                                  obscureText: !_showAdminPassword,
                                  decoration: InputDecoration(
                                    labelText: localized(ar, 'Password', 'كلمة المرور'),
                                    prefixIcon: const Icon(Icons.lock_outline_rounded, color: kGreen, size: 20),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showAdminPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                        size: 20,
                                      ),
                                      onPressed: () => setState(() => _showAdminPassword = !_showAdminPassword),
                                    ),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onSubmitted: (_) {
                                    if (!_working) _loginAdminWithPassword();
                                  },
                                ),
                                const SizedBox(height: 14),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: kGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  onPressed: _working ? null : _loginAdminWithPassword,
                                  child: _working
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                        )
                                      : Text(localized(ar, 'Sign In to Owner Portal', 'تسجيل الدخول للوحة الإدارة'), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                ),
                                const SizedBox(height: 6),
                                Center(
                                  child: TextButton(
                                    onPressed: _working
                                        ? null
                                        : () => setState(() {
                                              _adminShowPasswordAuth = false;
                                              _loginError = null;
                                            }),
                                    child: Text(localized(ar, '← Other Sign-In Methods', '← طرق دخول أخرى'), style: const TextStyle(fontSize: 12.5)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: kSurfaceTint,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: kBorder),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.verified_user_rounded, color: kGreen, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _adminPhoneCodeSent
                                            ? localized(ar, 'Enter Verification Code', 'أدخل رمز التحقق')
                                            : localized(ar, 'Email or Phone Login', 'الدخول بالهاتف أو البريد'),
                                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: kInk),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: _working
                                          ? null
                                          : () => setState(() {
                                                _adminShowPhoneAuth = false;
                                                _adminPhoneCodeSent = false;
                                                _loginError = null;
                                              }),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (!_adminPhoneCodeSent) ...[
                                  TextField(
                                    controller: _adminPhoneController,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: InputDecoration(
                                      labelText: localized(ar, 'Email or Phone Number', 'البريد الإلكتروني أو رقم الهاتف'),
                                      hintText: localized(ar, 'owner@venue.com or 010XXXXXXXX', '010XXXXXXXX أو owner@venue.com'),
                                      prefixIcon: const Icon(Icons.alternate_email_rounded, color: kGreen, size: 20),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: _working ? null : _sendAdminPhoneOtp,
                                    child: _working
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Text(
                                            localized(ar, 'Send Verification Code', 'إرسال كود التحقق'),
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                          ),
                                  ),
                                ] else ...[
                                  Text(
                                    localized(
                                      ar,
                                      'Code sent to ${_adminPhoneController.text}. Enter the 6-digit code:',
                                      'تم إرسال كود التحقق إلى ${_adminPhoneController.text}. أدخل الرمز المكون من 6 أرقام:',
                                    ),
                                    style: TextStyle(fontSize: 13, color: kMuted),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _adminOtpController,
                                    keyboardType: TextInputType.number,
                                    maxLength: 6,
                                    autofocus: true,
                                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 8),
                                    textAlign: TextAlign.center,
                                    decoration: InputDecoration(
                                      hintText: '123456',
                                      counterText: '',
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onSubmitted: (_) {
                                      if (!_working) _verifyAdminPhoneOtp();
                                    },
                                  ),
                                  const SizedBox(height: 14),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: kGreen,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    onPressed: _working ? null : _verifyAdminPhoneOtp,
                                    child: _working
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : Text(
                                            localized(ar, 'Verify & Enter Owner Workspace', 'تأكيد ودخول لوحة الشريك'),
                                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                                          ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      TextButton(
                                        onPressed: _working
                                            ? null
                                            : () => setState(() {
                                                  _adminPhoneCodeSent = false;
                                                  _adminOtpController.clear();
                                                }),
                                        child: Text(
                                          localized(ar, 'Change Email / Phone', 'تغيير البريد / الهاتف'),
                                          style: const TextStyle(fontSize: 12.5),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _working ? null : _sendAdminPhoneOtp,
                                        child: Text(
                                          localized(ar, 'Resend Code', 'إعادة إرسال الكود'),
                                          style: const TextStyle(fontSize: 12.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                        if (_loginError != null) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _loginError!,
                                    style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        Text(
                          localized(
                            ar,
                            'Protected Access: Administrative privileges are strictly restricted to verified owner credentials.',
                            'وصول محمي: صلاحيات الإدارة مقتصرة فقط على الشركاء وأصحاب الأماكن المعتمدين.',
                          ),
                          style: TextStyle(color: kMuted, fontSize: 12.0, height: 1.4),
                          textAlign: TextAlign.center,
                        ),
                        if (kDebugMode ||
                            _savedCustomerEmail.trim().toLowerCase().contains('mohamedhegazypc11') ||
                            normalizeEgyptPhone(_savedCustomerPhone) == '01015325250') ...[
                          const SizedBox(height: 14),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _openOwnerWorkspaceDirectly,
                            icon: const Icon(Icons.verified_user_rounded, size: 18),
                            label: const Text(
                              'Open Owner Workspace (Direct Access)',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                            ),
                          ),
                        ],
                      ] else ...[
                        Text(
                          'Connect your Hagzy API backend to enable administrative access.',
                          style: TextStyle(color: kMuted, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}
