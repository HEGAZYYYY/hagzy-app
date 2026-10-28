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
import 'screens/book_tab.dart';
import 'screens/login_screen.dart';
import 'screens/my_bookings_tab.dart';
import 'screens/profile_tab.dart';
import 'theme/hagzy_theme.dart';
import 'widgets/common_widgets.dart';
import 'services/social_auth_service.dart';

export 'models/models.dart';
export 'screens/login_screen.dart';

void main() {
  runApp(const HagzyApp());
}

/// The app language, lifted above MaterialApp so that dialogs, bottom sheets
/// and snackbars (which live in the Navigator overlay, above the home screen)
/// get the right locale and text direction, not the device's.
final ValueNotifier<String> kAppLanguage = ValueNotifier<String>('EN');

class HagzyApp extends StatelessWidget {
  const HagzyApp({
    super.key,
    this.adminMode = const bool.fromEnvironment('HAGZY_ADMIN_APP'),
  });

  final bool adminMode;

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
            home: HagzyHome(adminMode: adminMode),
          ),
        ),
      );
}

class HagzyHome extends StatefulWidget {
  const HagzyHome({super.key, this.adminMode = false});

  final bool adminMode;

  @override
  State<HagzyHome> createState() => _HagzyHomeState();
}

class _HagzyHomeState extends State<HagzyHome> {
  final HagzyApi _api = HagzyApi();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  Timer? _expiredBookingTimer;
  Timer? _paymentPollingTimer;
  List<Venue> _venues = kSeedNaderSalon ? defaultPrototypeVenues() : [];
  List<Booking> _bookings = [];
  List<Booking> _customerBookings = [];
  String _savedCustomerName = '';
  String _savedCustomerPhone = '';
  String _savedCustomerEmail = '';
  String? _customerToken;
  bool _customerSignedIn = false;
  bool _prefsLoaded = false;
  String _currentArea = 'Cairo';
  double _walletBalance = HagzyWallet.defaultWelcomeBalance;
  bool _working = false;
  bool _showAdminPassword = false;
  String? _loadError;
  String? _apiError;
  String? _loginError;
  String? _adminToken;
  String _mode = 'landing';
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
    _mode = widget.adminMode ? 'adminLogin' : 'customer';
    _load();

    // Check for real OAuth 2.0 callback credentials in URL query parameters or Firebase redirect result
    if (kIsWeb) {
      try {
        final params = Uri.base.queryParameters;
        String? token = params['auth_token'];
        String? name = params['auth_name'];
        String? email = params['auth_email'];
        if (token == null || token.isEmpty) {
          final redirectUser = SocialAuthService.getRedirectUser();
          if (redirectUser != null) {
            token = redirectUser['token'] as String?;
            name = redirectUser['name'] as String?;
            email = redirectUser['email'] as String?;
          }
        }
        if (token != null && token.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleCustomerSignIn(
              name: name ?? (email?.split('@')[0] ?? 'Hagzy Member'),
              email: email ?? '',
              phone: '',
              token: token,
            );
          });
        }
      } catch (_) {}

      // Listen for Firebase account deletion/sign-out in real time
      SocialAuthService.registerSignOutListener(() {
        if (mounted && _customerSignedIn) {
          _handleCustomerSignOut();
        }
      });

      // Listen for real-time Cloud Firestore venue updates
      SocialAuthService.registerVenuesListener((fbVenuesJson) {
        if (!mounted || fbVenuesJson.isEmpty) return;
        try {
          final incoming = fbVenuesJson
              .map((m) => Venue.fromJson(m))
              .toList();
          if (incoming.isNotEmpty) {
            final merged = List<Venue>.of(_venues);
            for (final fv in incoming) {
              final idx = merged.indexWhere((v) => v.id == fv.id);
              if (idx >= 0) {
                merged[idx] = fv;
              } else {
                merged.add(fv);
              }
            }
            setState(() {
              _venues = merged;
            });
          }
        } catch (_) {}
      });
    }
  }

  Future<List<Venue>> _loadSeedVenues(List<Venue> venues) async {
    if (!kSeedNaderSalon) return venues;
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
      return upsertNaderSalon(venues);
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
          _savedCustomerName = profile['name'] as String? ?? '';
          _savedCustomerPhone = profile['phone'] as String? ?? '';
          _savedCustomerEmail = profile['email'] as String? ?? '';
          _customerToken = profile['token'] as String?;
          _customerSignedIn = (profile['isSignedIn'] as bool? ?? false) &&
              _customerToken != null &&
              _customerToken!.isNotEmpty;
          if (kIsWeb) {
            try {
              final tokenParam = Uri.base.queryParameters['token'];
              if (tokenParam != null && tokenParam.isNotEmpty) {
                _customerToken = tokenParam;
                _customerSignedIn = true;
              }
            } catch (_) {}
          }
        } catch (_) {}
      }
      _currentArea = prefs.getString('hagzy_customer_area') ?? 'Cairo';
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
      if (!widget.adminMode && _api.isConfigured) {
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
      if (raw != null &&
          (jsonDecode(raw) as Map<String, dynamic>)['bookings'] is List &&
          ((jsonDecode(raw) as Map<String, dynamic>)['bookings'] as List)
                  .length !=
              _bookings.length) {
        await _persistExpiredBookingRemoval(prefs);
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
    _api.close();
    _emailController.dispose();
    _passwordController.dispose();
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

  Future<void> _syncAllVenuesToFirebase() async {
    final arabic = _language == 'AR';
    try {
      if (kIsWeb) {
        for (final v in _venues) {
          SocialAuthService.saveVenueToFirestore(v.toJson());
        }
      }
      if (_api.isConfigured && _adminToken != null) {
        await _api.syncVenuesToCloud(_adminToken!);
      }
      _message(localized(
        arabic,
        'Synced ${_venues.length} venues to Cloud Firebase!',
        'تمت مزامنة ${_venues.length} أماكن مع سحابة Firebase بنجاح!',
      ));
    } catch (e) {
      _message(
        localized(
          arabic,
          'Synced locally & queued for Cloud Firebase.',
          'تم الحفظ والمزامنة مع Firebase.',
        ),
      );
    }
  }

  Future<void> _loginAdmin() async {
    setState(() {
      _working = true;
      _loginError = null;
    });
    try {
      final auth = await _api.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      final token = auth['token'] as String;
      final venues = await _api.venues(adminToken: token);
      final bookings = await _api.bookings(token);
      if (!mounted) return;
      setState(() {
        _adminToken = token;
        _venues = upsertNaderSalon(
          venues
              .map((value) => Venue.fromJson(value as Map<String, dynamic>))
              .toList(),
        );
        _bookings = bookings
            .map((value) => Booking.fromJson(value as Map<String, dynamic>))
            .toList();
        _mode = 'admin';
        _tab = 0;
        _passwordController.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _loginError = friendlyError(error, arabic: false));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _enterAdminPreview() {
    setState(() {
      _mode = 'adminPreview';
      _tab = 0;
      _apiError = null;
      _bookings = List.of(_customerBookings);
    });
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

  Future<void> _saveAdminVenue(Venue venue) async {
    if (kIsWeb) {
      SocialAuthService.saveVenueToFirestore(venue.toJson());
    }
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
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
    var name = '';
    var location = '';
    var ownerPhone = '';
    var depositPercent = '25';
    final formKey = GlobalKey<FormState>();
    VenueType type = initialType;
    final result = await showDialog<Venue>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add a venue'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<VenueType>(
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Venue type'),
                    items: VenueType.values
                        .map((type) => DropdownMenuItem(
                              value: type,
                              child: Text(type.label,
                                  overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => type = value ?? type),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => name = value,
                    decoration: const InputDecoration(labelText: 'Venue name'),
                    validator: requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => location = value,
                    decoration:
                        const InputDecoration(labelText: 'Area / address'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    onChanged: (value) => ownerPhone = value,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Owner phone'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: depositPercent,
                    onChanged: (value) => depositPercent = value,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Deposit policy (%)',
                        helperText:
                            'Estimate only; Hagzy does not collect it.'),
                    validator: (value) {
                      final percent = double.tryParse(value ?? '');
                      return percent == null ||
                              !percent.isFinite ||
                              percent < 0 ||
                              percent > 100
                          ? 'Enter a percentage from 0 to 100'
                          : null;
                    },
                  ),
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
                  Venue(
                    id: generateId(),
                    name: name.trim(),
                    location: location.trim(),
                    type: type,
                    ownerPhone: ownerPhone.trim(),
                    depositPercent: double.parse(depositPercent.trim()),
                  ),
                );
              },
              child: const Text('Add venue'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _runSave(() async {
      await _saveAdminVenue(result);
      await _commit([..._venues, result], _bookings);
    });
  }

  Future<void> _editVenue(Venue venue) async {
    var type = venue.type;
    var name = venue.name;
    var location = venue.location;
    var ownerPhone = venue.ownerPhone;
    var depositPercent = venue.depositPercent.toStringAsFixed(0);
    var instaPay = venue.instaPayAddress;
    var vodafoneCash = venue.vodafoneCashNumber;
    var description = venue.description;
    var imageUrl = venue.imageUrl ?? '';
    var amenitiesText = venue.amenities.join(', ');
    var googleMapsUrl = venue.googleMapsUrl;
    var openHour = venue.openHour;
    var closeHour = venue.closeHour;
    final formKey = GlobalKey<FormState>();

    final updated = await showDialog<Venue>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Renovate / Edit ${venue.name}'),
          content: SizedBox(
            width: 460,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<VenueType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Venue category'),
                      items: VenueType.values
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(t.label, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setDialogState(() => type = v ?? type),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: name,
                      onChanged: (v) => name = v,
                      decoration:
                          const InputDecoration(labelText: 'Venue name'),
                      validator: requiredValidator,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: location,
                      onChanged: (v) => location = v,
                      decoration:
                          const InputDecoration(labelText: 'Area / address'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: description,
                      onChanged: (v) => description = v,
                      maxLines: 2,
                      decoration: const InputDecoration(
                          labelText: 'Description / renovation notes'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: imageUrl,
                      onChanged: (v) => imageUrl = v,
                      decoration: const InputDecoration(
                        labelText: 'Cover Image URL (optional)',
                        hintText: 'https://images.unsplash.com/...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: amenitiesText,
                      onChanged: (v) => amenitiesText = v,
                      decoration: const InputDecoration(
                        labelText: 'Amenities (comma-separated)',
                        hintText: 'Parking, Wi-Fi, AC, VIP Lounge, Showers',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: ownerPhone,
                      onChanged: (v) => ownerPhone = v,
                      keyboardType: TextInputType.phone,
                      decoration:
                          const InputDecoration(labelText: 'Owner phone'),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: depositPercent,
                      onChanged: (v) => depositPercent = v,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Deposit policy (%)'),
                      validator: (v) {
                        final p = double.tryParse(v ?? '');
                        return p == null || p < 0 || p > 100
                            ? 'Enter 0 to 100'
                            : null;
                      },
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: instaPay,
                      onChanged: (v) => instaPay = v,
                      decoration: const InputDecoration(
                        labelText: 'InstaPay Address (IPA)',
                        hintText: 'venue@instapay',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: vodafoneCash,
                      onChanged: (v) => vodafoneCash = v,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Vodafone Cash Wallet Number',
                        hintText: '010...',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      initialValue: googleMapsUrl,
                      onChanged: (v) => googleMapsUrl = v,
                      decoration: const InputDecoration(
                        labelText: 'Google Maps Link (optional)',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: openHour.clamp(6, 20),
                            decoration: const InputDecoration(
                                labelText: 'Opening Hour'),
                            items: List.generate(15, (i) => i + 6)
                                .map((h) => DropdownMenuItem(
                                      value: h,
                                      child: Text('$h:00'),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => openHour = v ?? 10),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: closeHour.clamp(12, 23),
                            decoration: const InputDecoration(
                                labelText: 'Closing Hour'),
                            items: List.generate(12, (i) => i + 12)
                                .map((h) => DropdownMenuItem(
                                      value: h,
                                      child: Text('$h:00'),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setDialogState(() => closeHour = v ?? 22),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                final parsedAmenities = amenitiesText
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
                Navigator.pop(
                  ctx,
                  venue.copyWith(
                    type: type,
                    name: name.trim(),
                    location: location.trim(),
                    description: description.trim(),
                    imageUrl: imageUrl.trim(),
                    amenities: parsedAmenities,
                    ownerPhone: ownerPhone.trim(),
                    depositPercent: double.parse(depositPercent.trim()),
                    instaPayAddress: instaPay.trim(),
                    vodafoneCashNumber: vodafoneCash.trim(),
                    googleMapsUrl: googleMapsUrl.trim(),
                    openHour: openHour,
                    closeHour: closeHour > openHour ? closeHour : openHour + 1,
                  ),
                );
              },
              child: const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
    if (updated == null) return;
    final nextVenues =
        _venues.map((v) => v.id == venue.id ? updated : v).toList();
    await _runSave(() async {
      await _saveAdminVenue(updated);
      await _commit(nextVenues, _bookings);
    });
  }

  Future<void> _deleteVenue(Venue venue) async {
    await _runSave(() async {
      if (kIsWeb) {
        SocialAuthService.deleteVenueFromFirestore(venue.id);
      }
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
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5, color: kInk),
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
            style: const TextStyle(fontSize: 14, color: kMuted, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                localized(arabic, 'Cancel', 'إلغاء'),
                style: const TextStyle(color: kMuted, fontWeight: FontWeight.w600),
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
        setState(() => _tab = 2);
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
        return rate * duration() / 15;
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
      if (selectedPromo == 'HAGZY20') {
        final d = base * 0.20;
        return d > 100 ? 100 : d;
      }
      if (selectedPromo == 'FIRST50' || selectedPromo == 'HAGZY50') {
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

    if (!mounted) return;
    final booking = await showDialog<Booking>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: kPanel,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 22),
          title: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: HagzyTheme.brandGradient,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: kGreen.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(venue.type.icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      walkIn
                          ? localized(arabic, 'Add Walk-in', 'إضافة حجز مباشر')
                          : localized(arabic, 'Book Your Time', 'احجز موعدك'),
                      style: const TextStyle(
                        fontSize: 21,
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
                        style: const TextStyle(
                          color: kGreen,
                          fontSize: 11,
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
                icon: const Icon(Icons.close_rounded, color: kMuted),
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
                                    style: const TextStyle(
                                      color: kMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${date.day}/${date.month}/${date.year} · ${time.format(context)}',
                                    style: const TextStyle(
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
                                  fontSize: 11,
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
                                style: const TextStyle(color: kMuted)),
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
                        style: const TextStyle(
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
                        style: const TextStyle(
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
                        style: const TextStyle(
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
                          final promoBadge = offer.discountType == 'fixed'
                              ? '-${offer.value.toInt()} EGP'
                              : '-${offer.value.toInt()}%';
                          return CustomPill(
                            icon: Icons.local_offer_outlined,
                            label: '${offer.code} ($promoBadge)',
                            selected: active,
                            onTap: () => setDialogState(() {
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
                          return Text(
                            localized(arabic, selectedOffer.englishDescription,
                                selectedOffer.arabicDescription),
                            style: const TextStyle(
                                fontSize: 11.5,
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
                                  style: const TextStyle(
                                    fontSize: 11.5,
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
                                          fontSize: 11,
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
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: kMuted),
                                  ),
                                  Text(
                                    localized(
                                      arabic,
                                      '${formatMoney(amount)} EGP${split > 1 ? ' (${formatMoney(parts)}/person)' : ''}',
                                      '${formatMoney(amount)} جنيه${split > 1 ? ' (${formatMoney(parts)} للفرد)' : ''}',
                                    ),
                                    style: const TextStyle(
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
                                    style: const TextStyle(
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
                                      style: const TextStyle(
                                          color: kMuted,
                                          fontSize: 11,
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
            SizedBox(
              width: double.infinity,
              height: 52,
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
                      venue.services.isNotEmpty &&
                      selectedServices.isEmpty) {
                    _message('Choose at least one salon service.');
                    return;
                  }
                  if (!walkIn && !startsAt().isAfter(DateTime.now())) {
                    _message('Choose a start time in the future.');
                    return;
                  }
                  if (!isAvailable()) {
                    _message('This time is already held or booked.',
                        error: true);
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
                      promoCode: selectedPromo,
                      discountAmount: discount(),
                      staffMember: venue.type == VenueType.salon
                          ? selectedBarber
                          : '',
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
      _message(
          '${localized(ar, 'Could not create the reservation', 'تعذّر إنشاء الحجز')}: '
          '${friendlyError(error, arabic: ar)}',
          error: true);
    }
  }

  Future<void> _showPaymentMethods(Booking booking, double dueNow) async {
    final arabic = _language == 'AR';
    final venue =
        _venues.where((value) => value.id == booking.venueId).firstOrNull;
    final hasInstaPay = venue != null && venue.instaPayAddress.isNotEmpty;
    final hasVodafoneCash =
        venue != null && venue.vodafoneCashNumber.isNotEmpty;

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
                            style: const TextStyle(
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
                            style: const TextStyle(
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
                                fontSize: 11.5,
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
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 11,
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
                          style: const TextStyle(
                            color: kInk,
                            fontSize: 11.5,
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
                  icon: Icons.account_balance_rounded,
                  title: 'InstaPay',
                  subtitle: hasInstaPay
                      ? localized(
                          arabic,
                          'Send to ${venue.instaPayAddress} & submit reference',
                          'حوّل إلى ${venue.instaPayAddress} وأدخل رقم المرجع',
                        )
                      : localized(
                          arabic,
                          'Transfer & submit reference for venue verification',
                          'حوّل وأدخل رقم المرجع للتحقق',
                        ),
                  enabled: true,
                  accentColor: kGreen,
                  badgeText: localized(arabic, 'INSTANT', 'فوري'),
                  onTap: () => Navigator.pop(context, 'instapay'),
                ),
                const SizedBox(height: 8),
                PaymentMethodTile(
                  icon: Icons.phone_android_rounded,
                  title: 'Vodafone Cash',
                  subtitle: hasVodafoneCash
                      ? localized(
                          arabic,
                          'Wallet ${venue.vodafoneCashNumber} · Submit reference',
                          'محفظة ${venue.vodafoneCashNumber} · أدخل رقم العملية',
                        )
                      : localized(
                          arabic,
                          'Mobile wallet transfer & reference verification',
                          'تحويل محفظة إلكترونية وتأكيد الرقم',
                        ),
                  enabled: true,
                  accentColor: kGreen,
                  badgeText: localized(arabic, 'WALLET', 'محفظة'),
                  onTap: () => Navigator.pop(context, 'vodafone_cash'),
                ),
                const SizedBox(height: 8),
                PaymentMethodTile(
                  icon: Icons.credit_card_rounded,
                  title: 'Paymob',
                  subtitle: localized(
                    arabic,
                    'Visa, Mastercard, Meeza & Mobile Wallets',
                    'فيزا، ماستركارد، ميزة والمحافظ الإلكترونية',
                  ),
                  enabled: true,
                  accentColor: kGreen,
                  badgeText: localized(arabic, 'CARD / WALLET', 'بطاقة / محفظة'),
                  onTap: () => Navigator.pop(context, 'paymob'),
                ),
                const SizedBox(height: 8),
                PaymentMethodTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Fawry',
                  accentColor: kGreen,
                  enabled: true,
                  badgeText: localized(arabic, 'FAWRYPAY', 'كود فوري'),
                  subtitle: localized(
                    arabic,
                    'Generate a FawryPay reference code or pay via MyFawry',
                    'اصدر كود دفع فوري أو ادفع عبر تطبيق MyFawry',
                  ),
                  onTap: () => Navigator.pop(context, 'fawry'),
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
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'later'),
                  child: Text(
                    localized(arabic, 'Pay later', 'ادفع لاحقاً'),
                    style: const TextStyle(
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
    } else if (method == 'instapay') {
      await _submitManualTransferProof(
        booking: booking,
        method: 'instapay',
        methodLabel: 'InstaPay',
        destination: venue?.instaPayAddress.isNotEmpty == true
            ? venue!.instaPayAddress
            : 'hagzy@instapay',
        dueNow: dueNow,
      );
    } else if (method == 'vodafone_cash') {
      await _submitManualTransferProof(
        booking: booking,
        method: 'vodafone_cash',
        methodLabel: 'Vodafone Cash',
        destination: venue?.vodafoneCashNumber.isNotEmpty == true
            ? venue!.vodafoneCashNumber
            : (venue?.ownerPhone.isNotEmpty == true
                ? venue!.ownerPhone
                : '01024129393'),
        dueNow: dueNow,
      );
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

  Future<void> _submitManualTransferProof({
    required Booking booking,
    required String method,
    required String methodLabel,
    required String destination,
    required double dueNow,
  }) async {
    final arabic = _language == 'AR';
    var reference = '';
    final formKey = GlobalKey<FormState>();

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
                    color: kDarkMode.value ? const Color(0xFF19243D) : kPage,
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
                              style: const TextStyle(
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
                                  fontSize: 11,
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
                              ? const Color(0xFF131C31)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: kDarkMode.value
                                ? const Color(0xFF283552)
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
                              final uri = Uri.parse('https://ipn.eg/');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri,
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
                      if (method == 'vodafone_cash')
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
                                'Dial *9*7* USSD Code',
                                'اطلب كود التحويل المباشر')),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  autofocus: true,
                  onChanged: (v) => reference = v,
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
                const SizedBox(height: 8),
                Text(
                  localized(
                    arabic,
                    'Your hold is extended for 60 minutes while the venue owner verifies your transfer in their POS timeline.',
                    'يتم تمديد الحجز المؤقت لمدة 60 دقيقة ريثما يتحقق صاحب المكان من التحويل.',
                  ),
                  style: const TextStyle(color: kMuted, fontSize: 11.5),
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
    if (confirmed != true || reference.trim().isEmpty) return;

    await _runSave(() async {
      var updated = booking.copyWith(
        paymentStatus: 'pending',
        paymentMethod: method,
        paymentReference: reference.trim(),
        holdExpiresAt: DateTime.now().add(const Duration(minutes: 60)),
      );
      if (_api.isConfigured) {
        try {
          final remote = await _api.submitPaymentProof(
            booking.id,
            method: method,
            reference: reference.trim(),
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
      _message(localized(
        arabic,
        'Transfer reference submitted! Awaiting venue owner verification.',
        'تم إرسال رقم العملية! بانتظار تأكيد المكان.',
      ));
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
                        fontSize: 11,
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
                    style: const TextStyle(
                        color: kMuted, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatMoney(dueNow)} EGP',
                    style: const TextStyle(
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
                style: const TextStyle(
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
          'Welcome to Hagzy WhatsApp Assistant! 👋\nI can help you pay your deposit (Paymob, Fawry, InstaPay, Vodafone Cash), check your booking status, or connect you to live WhatsApp.',
          'مرحباً بك في مساعد حجزي الذكي عبر واتساب! 👋\nيمكنني مساعدتك في دفع العربون (Paymob أو فوري أو إنستا باي أو فودافون كاش)، أو متابعة حالة حجزك.',
        ),
      ),
      if (activeBooking != null)
        (
          true,
          localized(
            arabic,
            '📌 Active Reservation:\n• Venue: ${venue?.name ?? activeBooking.venueId}\n• Time: ${formatDateTime(activeBooking.startsAt)}\n• Deposit Due: ${formatMoney(activeBooking.dueNow ?? activeBooking.price)} EGP\n• Status: ${activeBooking.isConfirmed ? 'Confirmed ✓' : '15-min Hold (Pending Deposit)'}',
            '📌 حجزك النشط:\n• المكان: ${venue?.name ?? activeBooking.venueId}\n• الموعد: ${formatDateTime(activeBooking.startsAt)}\n• العربون: ${formatMoney(activeBooking.dueNow ?? activeBooking.price)} جنيه\n• الحالة: ${activeBooking.isConfirmed ? 'مؤكد ✓' : 'حجز مؤقت بانتظار العربون'}',
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
            : '01024129393';
        return localized(
          arabic,
          '💳 Deposit Payment Options:\n1. Paymob: Instant Visa, Mastercard & Meeza checkout.\n2. FawryPay: Service Code 78890 (generate your 10-digit code in 1 tap).\n3. InstaPay: Send to $insta\n4. Vodafone Cash: Send to $vf\n\nTip: You can also paste your transfer reference code right here in the chat!',
          '💳 طرق دفع العربون:\n١. Paymob: بطاقات فيزا وماستركارد وميزة.\n٢. فوري باي: كود الخدمة 78890.\n٣. إنستا باي: حوّل إلى $insta\n٤. فودافون كاش: حوّل إلى $vf\n\nيمكنك أيضاً إرسال رقم العملية المرجعي هنا في المحادثة مباشرة!',
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
          '✅ Reference "$ref" attached to your reservation (${venue?.name ?? activeBooking.venueId})! Your hold is extended while the venue verifies your payment.',
          '✅ تم ربط رقم العملية "$ref" بحجزك في (${venue?.name ?? activeBooking.venueId})! تم تمديد الحجز ريثما يتحقق المكان من الدفع.',
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
                                          fontSize: 11,
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
                                      fontSize: 11.5,
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
                      decoration: const BoxDecoration(
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
          'name': _savedCustomerName,
          'email': _savedCustomerEmail,
          'phone': _savedCustomerPhone,
          'isSignedIn': _customerSignedIn,
          'token': _customerToken,
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
  }) async {
    if (token != null && token.isNotEmpty) {
      _customerToken = token;
    } else if (_customerToken == null || _customerToken!.isEmpty) {
      _customerToken = 'local-session-token';
    }
    _tab = 0;
    await _saveCustomerProfile(
      name: name,
      email: email,
      phone: phone,
      isSignedIn: true,
      token: _customerToken,
    );
    if (walletBalance != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(HagzyWallet.keyWallet, walletBalance);
      if (mounted) setState(() => _walletBalance = walletBalance);
    }
    await _syncAccountData(showErrors: false);
  }

  Future<void> _syncAccountData({bool showErrors = false}) async {
    if (!_api.isConfigured) return;
    if (_customerToken == null &&
        _savedCustomerPhone.isEmpty &&
        _savedCustomerEmail.isEmpty) {
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

        await _saveCustomerProfile(
          name: cloudName.isNotEmpty ? cloudName : _savedCustomerName,
          email: cloudEmail.isNotEmpty ? cloudEmail : _savedCustomerEmail,
          phone: cloudPhone.isNotEmpty ? cloudPhone : _savedCustomerPhone,
          isSignedIn: _customerSignedIn,
          token: _customerToken,
        );

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
    } catch (error) {
      final errStr = error.toString().toLowerCase();
      if (errStr.contains('401') ||
          errStr.contains('404') ||
          errStr.contains('deleted') ||
          errStr.contains('user not found') ||
          errStr.contains('logged out') ||
          errStr.contains('invalid or expired')) {
        // Account was deleted in Firebase / revoked on server
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
      _savedCustomerName = '';
      _savedCustomerEmail = '';
      _savedCustomerPhone = '';
      _customerSignedIn = false;
      _customerToken = null;
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

  void _openVenueControlDashboardModal() {
    final arabic = _language == 'AR';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final isDark = kDarkMode.value;
          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0B1120) : kPage,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(
                  color: isDark ? const Color(0xFF283552) : kBorder),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kMuted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          gradient: HagzyTheme.brandGradient,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.dashboard_customize_rounded,
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
                              localized(
                                arabic,
                                'Firebase Venue Control Dashboard',
                                'لوحة التحكم في الأماكن (Firebase)',
                              ),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: isDark
                                    ? const Color(0xFFF8FAFC)
                                    : kInk,
                              ),
                            ),
                            Text(
                              localized(
                                arabic,
                                'Add, remove, or renovate venues online in real time',
                                'إضافة أو حذف أو تجديد الأماكن والملاعب فوراً على السحابة',
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark
                                    ? const Color(0xFF94A3B8)
                                    : kMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ManageTab(
                    venues: _venues,
                    onAddVenue: () async {
                      await _addVenue();
                      setModalState(() {});
                    },
                    onEditVenue: (v) async {
                      await _editVenue(v);
                      setModalState(() {});
                    },
                    onAddItem: (v) async {
                      await _addItem(v);
                      setModalState(() {});
                    },
                    onAddService: (v) async {
                      await _addService(v);
                      setModalState(() {});
                    },
                    onRemoveService: (v, s) async {
                      await _removeService(v, s);
                      setModalState(() {});
                    },
                    onDelete: (v) async {
                      await _deleteVenue(v);
                      setModalState(() {});
                    },
                    onRemoveItem: (v, item) async {
                      await _removeItem(v, item);
                      setModalState(() {});
                    },
                    onSyncFirebase: _syncAllVenuesToFirebase,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
          child: _prefsLoaded && isCustomer && !_customerSignedIn
              ? CustomerLoginScreen(
                  arabic: arabic,
                  language: _language,
                  api: _api,
                  apiConfigured: _api.isConfigured,
                  onSignIn: _handleCustomerSignIn,
                  onChangeLanguage: _changeLanguage,
                  onSwitchToAdmin: () => setState(() {
                    _mode = _api.isConfigured ? 'adminLogin' : 'adminPreview';
                    _tab = 2;
                  }),
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
                            style: const TextStyle(
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
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: kMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: localized(
                          arabic,
                          kDarkMode.value ? 'Light Mode' : 'Dark Mode',
                          kDarkMode.value ? 'الوضع النهاري' : 'الوضع الليلي',
                        ),
                        onPressed: _toggleDarkMode,
                        style: IconButton.styleFrom(
                          backgroundColor: kDarkMode.value
                              ? const Color(0xFF19243D)
                              : kSurfaceTint,
                          foregroundColor:
                              kDarkMode.value ? kGold : kGreen,
                        ),
                        icon: Icon(
                          kDarkMode.value
                              ? Icons.light_mode_rounded
                              : Icons.dark_mode_rounded,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: localized(arabic, 'WhatsApp Assistant Bot',
                            'مساعد حجزي · واتساب'),
                        onPressed: () => _openWhatsAppChatbotSheet(),
                        style: IconButton.styleFrom(
                          backgroundColor: kDarkMode.value
                              ? const Color(0xFF19243D)
                              : kSurfaceTint,
                          foregroundColor: kGreen,
                        ),
                        icon: const Icon(Icons.support_agent_rounded, size: 20),
                      ),
                      const SizedBox(width: 8),
                      if (MediaQuery.sizeOf(context).width >= 360)
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
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: localized(
                          arabic,
                          _customerSignedIn ? 'My Profile' : 'Sign In',
                          _customerSignedIn ? 'الملف الشخصي' : 'تسجيل الدخول',
                        ),
                        onPressed: () =>
                            setState(() => _tab = isCustomer ? 2 : 4),
                        style: IconButton.styleFrom(
                          backgroundColor: _tab == (isCustomer ? 2 : 4)
                              ? kGreen
                              : kSurfaceTint,
                          foregroundColor: _tab == (isCustomer ? 2 : 4)
                              ? Colors.white
                              : kInk,
                        ),
                        icon: _customerSignedIn && _savedCustomerName.isNotEmpty
                            ? Text(
                                _savedCustomerName
                                    .trim()
                                    .substring(0, 1)
                                    .toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 13,
                                  color: _tab == (isCustomer ? 2 : 4)
                                      ? Colors.white
                                      : kGreen,
                                ),
                              )
                            : const Icon(Icons.person_rounded, size: 20),
                      ),
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
                      if (!isCustomer) ...[
                        const SizedBox(width: 6),
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
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
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
                                            onBook: (venue, item, startsAt) =>
                                                _createBooking(
                                              venue: venue,
                                              item: item,
                                              initialStart: startsAt,
                                            ),
                                            onAddReview: _addReview,
                                          ),
                                        1 => MyBookingsTab(
                                            venues: _venues,
                                            bookings: _bookings,
                                            walletBalance: _walletBalance,
                                            arabic: arabic,
                                            isSignedIn: _customerSignedIn,
                                            onSignIn: _handleCustomerSignIn,
                                            onGoToSignIn: () => setState(() => _tab = 2),
                                            onChoosePayment: (booking) =>
                                                _showPaymentMethods(
                                              booking,
                                              booking.dueNow ?? booking.price,
                                            ),
                                            onCancelBooking: _cancelBooking,
                                            onRefresh: () => _syncAccountData(
                                                showErrors: true),
                                            onScreenOpened: () =>
                                              _syncAccountData(),
                                            onBookAgain: (venueId) => setState(() {
                                              _tab = 0;
                                              _targetVenueId = venueId;
                                            }),
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
                                            currentArea: _currentArea,
                                            api: _api,
                                            apiConfigured: _api.isConfigured,
                                            onSignIn: _handleCustomerSignIn,
                                            onSignOut: _handleCustomerSignOut,
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
                                            onSwitchToAdmin: () => setState(() { _mode = _api.isConfigured ? 'adminLogin' : 'adminPreview'; _tab = 2; }),
                                            onToggleDarkMode: _toggleDarkMode,
                                            onOpenVenueDashboard: _openVenueControlDashboardModal,
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
                                                onAddVenue: _addVenue,
                                                onEditVenue: _editVenue,
                                                onAddItem: _addItem,
                                                onAddService: _addService,
                                                onRemoveService: _removeService,
                                                onDelete: _deleteVenue,
                                                onRemoveItem: _removeItem,
                                                onSyncFirebase: _syncAllVenuesToFirebase,
                                              ),
                                            2 => PosTab(
                                                venues: _venues,
                                                bookings: _bookings,
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
                                              ),
                                            _ => PosTab(
                                                venues: _venues,
                                                bookings: _bookings,
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
                                            venues: _venues,
                                            bookings: _bookings,
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
                                            venues: _venues,
                                            onAddVenue: _addVenue,
                                            onEditVenue: _editVenue,
                                            onAddItem: _addItem,
                                            onAddService: _addService,
                                            onRemoveService: _removeService,
                                            onDelete: _deleteVenue,
                                            onRemoveItem: _removeItem,
                                            onSyncFirebase: _syncAllVenuesToFirebase,
                                          ),
                                        2 => AnalyticsTab(
                                            venues: _venues,
                                            bookings: _bookings,
                                          ),
                                        3 => PaymentTab(
                                            apiConfigured: _api.isConfigured,
                                            localPreview: isPreview,
                                          ),
                                        _ => PosTab(
                                            venues: _venues,
                                            bookings: _bookings,
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

  Widget _buildAdminLogin() => Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Venue owner sign in'),
          actions: [
            TextButton.icon(
              onPressed: () => setState(() => _mode = 'customer'),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Customer Mode'),
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
                        alignment: Alignment.centerLeft,
                        child: HagzyLogoMark(size: 54, withGlow: true),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Welcome back',
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
                            ? 'Sign in with the admin account created for your Hagzy server.'
                            : 'Connect your Hagzy API to sign in and sync venue data across devices.',
                        style: const TextStyle(color: kMuted, height: 1.4),
                      ),
                      const SizedBox(height: 22),
                      if (_api.isConfigured) ...[
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                              labelText: 'Admin email',
                              prefixIcon: Icon(Icons.email_outlined)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: !_showAdminPassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _working ? null : _loginAdmin(),
                          decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.key_outlined),
                              suffixIcon: IconButton(
                                tooltip: _showAdminPassword
                                    ? 'Hide password'
                                    : 'Show password',
                                icon: Icon(_showAdminPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined),
                                onPressed: () => setState(() =>
                                    _showAdminPassword = !_showAdminPassword),
                              )),
                        ),
                        if (_loginError != null) ...[
                          const SizedBox(height: 12),
                          // redAccent was 3.2:1 on white; this is 6.5:1.
                          Text(_loginError!,
                              style: const TextStyle(color: Color(0xFFB91C1C))),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _working ? null : _loginAdmin,
                          child: _working
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Sign in securely'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _enterAdminPreview,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Open local preview'),
                        ),
                      ] else ...[
                        FilledButton.icon(
                          onPressed: _enterAdminPreview,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Open local preview'),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Local preview data stays on this device and is not shared with customers on other phones.',
                          style: TextStyle(color: kMuted, fontSize: 12),
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
