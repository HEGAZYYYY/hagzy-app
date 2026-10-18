import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'hagzy_api.dart';

void main() {
  runApp(const HagzyApp());
}

const _ink = Color(0xFF0F172A);
const _green = Color(0xFF059669);
const _page = Color(0xFFF8FAFC);
const _panel = Color(0xFFFFFFFF);
const _muted = Color(0xFF64748B);
const _border = Color(0xFFE2E8F0);
const _dark = Color(0xFF0F172A);
const _whatsappBusinessNumber = '201024129393';
const _storageKey = 'hagzy_app_data_v1';
const _favoriteStorageKey = 'hagzy_favorite_venues_v1';
const _seedNaderSalon =
    bool.fromEnvironment('HAGZY_SEED_NADER_SALON', defaultValue: false);
const _languageStorageKey = 'hagzy_language';
const _allEgyptAreas = 'Choose your area';

const _egyptGovernorates = <(String, String)>[
  ('Cairo', 'القاهرة'),
  ('Giza', 'الجيزة'),
  ('Alexandria', 'الإسكندرية'),
  ('Dakahlia', 'الدقهلية'),
  ('Red Sea', 'البحر الأحمر'),
  ('Beheira', 'البحيرة'),
  ('Fayoum', 'الفيوم'),
  ('Gharbia', 'الغربية'),
  ('Ismailia', 'الإسماعيلية'),
  ('Menoufia', 'المنوفية'),
  ('Minya', 'المنيا'),
  ('Qalyubia', 'القليوبية'),
  ('New Valley', 'الوادي الجديد'),
  ('Suez', 'السويس'),
  ('Aswan', 'أسوان'),
  ('Assiut', 'أسيوط'),
  ('Beni Suef', 'بني سويف'),
  ('Port Said', 'بورسعيد'),
  ('Damietta', 'دمياط'),
  ('Sharkia', 'الشرقية'),
  ('South Sinai', 'جنوب سيناء'),
  ('Kafr El Sheikh', 'كفر الشيخ'),
  ('Matrouh', 'مطروح'),
  ('Luxor', 'الأقصر'),
  ('Qena', 'قنا'),
  ('North Sinai', 'شمال سيناء'),
  ('Sohag', 'سوهاج'),
];

String _localized(bool arabic, String english, String arabicText) =>
    arabic ? arabicText : english;

String _governorateName(String english, bool arabic) {
  final governorate =
      _egyptGovernorates.where((entry) => entry.$1 == english).firstOrNull;
  if (governorate == null) {
    return english == _allEgyptAreas
        ? _localized(arabic, 'Choose your area', 'كل محافظات مصر')
        : english;
  }
  return arabic ? governorate.$2 : governorate.$1;
}

Venue _naderSalonSample() => Venue(
      id: 'nader-el-khawaga-kafr-el-sheikh',
      name: 'Nader El Khawaga',
      location: 'Kafr El Sheikh',
      type: VenueType.salon,
      depositPercent: 30,
      items: [
        VenueItem(
          id: 'nader-el-khawaga-chair-1',
          name: 'Barber Chair 1',
          kind: 'Barber / chair',
          hourlyRate: 150,
        ),
      ],
      services: [
        SalonService(
          id: 'nader-haircut',
          name: 'Haircut',
          minutes: 30,
          price: 150,
        ),
        SalonService(
          id: 'nader-beard-trim',
          name: 'Beard trim',
          minutes: 20,
          price: 100,
        ),
        SalonService(
          id: 'nader-haircut-beard',
          name: 'Haircut + beard',
          minutes: 45,
          price: 220,
        ),
        SalonService(
          id: 'nader-kids-haircut',
          name: 'Kids haircut',
          minutes: 25,
          price: 100,
        ),
      ],
    );

List<Venue> _upsertNaderSalon(List<Venue> venues) {
  if (!_seedNaderSalon) return venues;
  final sample = _naderSalonSample();
  final matches = venues
      .where((venue) =>
          venue.id == sample.id ||
          (venue.name.trim().toLowerCase() == sample.name.toLowerCase() &&
              venue.location.trim().toLowerCase() ==
                  sample.location.toLowerCase()))
      .toList();
  if (matches.isEmpty) return [...venues, sample];

  final primary = matches.first;
  final items = <VenueItem>[];
  final services = <SalonService>[];
  for (final value in [...matches, sample]) {
    for (final item in value.items) {
      if (!items.any((saved) =>
          saved.id == item.id ||
          saved.name.trim().toLowerCase() == item.name.trim().toLowerCase())) {
        items.add(item);
      }
    }
    for (final service in value.services) {
      if (!services.any((saved) =>
          saved.id == service.id ||
          saved.name.trim().toLowerCase() ==
              service.name.trim().toLowerCase())) {
        services.add(service);
      }
    }
  }
  final merged = Venue(
    id: primary.id,
    name: sample.name,
    location: sample.location,
    type: VenueType.salon,
    ownerPhone: primary.ownerPhone,
    depositPercent: sample.depositPercent,
    items: items,
    services: services,
  );
  final firstMatch = venues.indexWhere((venue) => matches.contains(venue));
  return [
    ...venues.take(firstMatch),
    merged,
    ...venues.skip(firstMatch).where((venue) => !matches.contains(venue)),
  ];
}

enum VenueType { sports, salon, lounge }

extension VenueTypeLabel on VenueType {
  String get label => switch (this) {
        VenueType.sports => 'Padel / Football Club',
        VenueType.salon => 'Hair Salon / Barbershop',
        VenueType.lounge => 'PS5 / Billiards / Ping Pong Lounge',
      };

  IconData get icon => switch (this) {
        VenueType.sports => Icons.sports_tennis,
        VenueType.salon => Icons.content_cut,
        VenueType.lounge => Icons.sports_esports,
      };
}

class VenueItem {
  VenueItem({
    required this.id,
    required this.name,
    required this.kind,
    required this.hourlyRate,
    this.multiRate = 0,
  });

  final String id;
  final String name;
  final String kind;
  final double hourlyRate;
  final double multiRate;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'hourlyRate': hourlyRate,
        'multiRate': multiRate,
      };

  factory VenueItem.fromJson(Map<String, dynamic> json) => VenueItem(
        id: json['id'] as String,
        name:
            (json['name'] as String).trim().toLowerCase() == 'nader el khawaga'
                ? 'Nader El Khawaga'
                : json['name'] as String,
        kind: json['kind'] as String,
        hourlyRate: (json['hourlyRate'] as num).toDouble(),
        multiRate: (json['multiRate'] as num?)?.toDouble() ?? 0,
      );
}

class SalonService {
  SalonService({
    required this.id,
    required this.name,
    required this.minutes,
    required this.price,
  });

  final String id;
  final String name;
  final int minutes;
  final double price;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'minutes': minutes, 'price': price};

  factory SalonService.fromJson(Map<String, dynamic> json) => SalonService(
        id: json['id'] as String,
        name: json['name'] as String,
        minutes: json['minutes'] as int,
        price: (json['price'] as num).toDouble(),
      );
}

class Venue {
  Venue({
    required this.id,
    required this.name,
    required this.location,
    required this.type,
    this.ownerPhone = '',
    this.depositPercent = 25,
    this.imageUrl,
    List<VenueItem>? items,
    List<SalonService>? services,
  })  : items = items ?? [],
        services = services ?? [];

  final String id;
  final String name;
  final String location;
  final VenueType type;
  final String ownerPhone;
  final double depositPercent;
  final String? imageUrl;
  final List<VenueItem> items;
  final List<SalonService> services;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'type': type.name,
        'ownerPhone': ownerPhone,
        'depositPercent': depositPercent,
        if (imageUrl != null && imageUrl!.isNotEmpty) 'imageUrl': imageUrl,
        'items': items.map((item) => item.toJson()).toList(),
        'services': services.map((service) => service.toJson()).toList(),
      };

  factory Venue.fromJson(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        name: json['name'] as String,
        location: json['location'] as String? ?? '',
        type: VenueType.values.byName(json['type'] as String),
        ownerPhone: json['ownerPhone'] as String? ?? '',
        depositPercent: (json['depositPercent'] as num?)?.toDouble() ?? 25,
        imageUrl: json['imageUrl'] as String?,
        items: (json['items'] as List<dynamic>? ?? [])
            .map((item) => VenueItem.fromJson(item as Map<String, dynamic>))
            .toList(),
        services: (json['services'] as List<dynamic>? ?? [])
            .map((item) => SalonService.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
}

class Booking {
  Booking({
    required this.id,
    required this.venueId,
    required this.itemId,
    required this.customer,
    required this.startsAt,
    required this.durationMinutes,
    required this.price,
    this.serviceNames = const [],
    this.splitCount = 1,
    this.multiController = false,
    this.cancelled = false,
    this.phone = '',
    this.email = '',
    this.dueNow,
    this.status = 'pending_payment',
    this.paymentStatus = 'unpaid',
    this.holdExpiresAt,
  });

  final String id;
  final String venueId;
  final String itemId;
  final String customer;
  final DateTime startsAt;
  final int durationMinutes;
  final double price;
  final List<String> serviceNames;
  final int splitCount;
  final bool multiController;
  final bool cancelled;
  final String phone;
  final String email;
  final double? dueNow;
  final String status;
  final String paymentStatus;
  final DateTime? holdExpiresAt;
  DateTime get endsAt => startsAt.add(Duration(minutes: durationMinutes));
  bool get isPendingPayment =>
      status == 'pending_payment' &&
      paymentStatus != 'paid' &&
      (holdExpiresAt == null || holdExpiresAt!.isAfter(DateTime.now()));
  bool get isConfirmed =>
      status == 'confirmed' &&
      !cancelled &&
      (paymentStatus == 'paid' || dueNow == 0);
  bool get blocksAvailability =>
      !cancelled &&
      (isConfirmed ||
          (status == 'pending_payment' &&
              (holdExpiresAt == null ||
                  holdExpiresAt!.isAfter(DateTime.now()))));

  Map<String, dynamic> toJson() => {
        'id': id,
        'venueId': venueId,
        'itemId': itemId,
        'customer': customer,
        'startsAt': startsAt.toIso8601String(),
        'durationMinutes': durationMinutes,
        'price': price,
        'serviceNames': serviceNames,
        'splitCount': splitCount,
        'multiController': multiController,
        'cancelled': cancelled,
        'phone': phone,
        'email': email,
        'dueNow': dueNow,
        'status': status,
        'paymentStatus': paymentStatus,
        'holdExpiresAt': holdExpiresAt?.toIso8601String(),
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        venueId: json['venueId'] as String,
        itemId: json['itemId'] as String,
        customer: json['customer'] as String,
        startsAt: DateTime.parse(json['startsAt'] as String),
        durationMinutes: json['durationMinutes'] as int,
        price: (json['price'] as num).toDouble(),
        serviceNames:
            (json['serviceNames'] as List<dynamic>? ?? []).cast<String>(),
        splitCount: json['splitCount'] as int? ?? 1,
        multiController: json['multiController'] as bool? ?? false,
        cancelled: json['cancelled'] as bool? ?? false,
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        dueNow: (json['dueNow'] as num?)?.toDouble(),
        status: json['status'] as String? ??
            ((json['cancelled'] as bool? ?? false)
                ? 'cancelled'
                : 'pending_payment'),
        paymentStatus: json['paymentStatus'] as String? ?? 'unpaid',
        holdExpiresAt: DateTime.tryParse(
              json['holdExpiresAt'] as String? ?? '',
            ) ??
            ((json['status'] as String? ?? 'pending_payment') ==
                    'pending_payment'
                ? DateTime.now()
                : null),
      );
}

class HagzyApp extends StatelessWidget {
  const HagzyApp({
    super.key,
    this.adminMode = const bool.fromEnvironment('HAGZY_ADMIN_APP'),
  });

  final bool adminMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Hagzy',
        debugShowCheckedModeBanner: false,
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData.light(useMaterial3: true).copyWith(
          colorScheme: ColorScheme.fromSeed(
            seedColor: _green,
            brightness: Brightness.light,
            primary: _green,
            surface: _panel,
          ),
          scaffoldBackgroundColor: _page,
          textTheme: GoogleFonts.plusJakartaSansTextTheme(
            ThemeData.light().textTheme,
          )
              .apply(
                bodyColor: _ink,
                displayColor: _ink,
              )
              .copyWith(
                headlineLarge: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: _ink),
                headlineMedium: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: _ink),
                titleLarge: const TextStyle(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: _ink),
                bodyMedium: const TextStyle(color: _muted, height: 1.4),
                labelLarge:
                    const TextStyle(fontWeight: FontWeight.w600, color: _ink),
              ),
          appBarTheme: const AppBarTheme(
            backgroundColor: _panel,
            foregroundColor: _ink,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          cardTheme: CardThemeData(
            color: _panel,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _border, width: 1),
            ),
          ),
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: _dark,
            indicatorColor: _green,
            labelTextStyle:
                WidgetStateProperty.resolveWith((states) => TextStyle(
                      fontSize: 12,
                      fontWeight: states.contains(WidgetState.selected)
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: Colors.white,
                    )),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: _green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: const TextStyle(color: _muted),
            hintStyle: const TextStyle(color: Color(0xFF64748B)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _green, width: 1.5),
            ),
            filled: true,
            fillColor: _panel,
          ),
        ),
        home: HagzyHome(adminMode: adminMode),
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
  List<Venue> _venues = _seedNaderSalon ? [_naderSalonSample()] : [];
  List<Booking> _bookings = [];
  List<Booking> _customerBookings = [];
  bool _loaded = false;
  bool _working = false;
  String? _loadError;
  String? _apiError;
  String? _loginError;
  String? _adminToken;
  String _mode = 'landing';
  int _tab = 0;
  String _language = 'EN';
  bool _showSplash = !WidgetsBinding.instance.runtimeType
      .toString()
      .toLowerCase()
      .contains('test');

  static TextTheme? _cachedJakartaTextTheme;
  static TextTheme? _cachedCairoTextTheme;

  static TextTheme _buildTextTheme(BuildContext context, bool arabic) {
    final base = Theme.of(context).textTheme;
    if (arabic) {
      return _cachedCairoTextTheme ??= GoogleFonts.cairoTextTheme(base);
    } else {
      return _cachedJakartaTextTheme ??=
          GoogleFonts.plusJakartaSansTextTheme(base);
    }
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.adminMode ? 'adminLogin' : 'customer';
    _load();
  }

  Future<List<Venue>> _loadSeedVenues(List<Venue> venues) async {
    if (!_seedNaderSalon) return venues;
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
      return _upsertNaderSalon(venues);
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _language = prefs.getString(_languageStorageKey) == 'AR' ? 'AR' : 'EN';
      final raw = prefs.getString(_storageKey);
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
        _storageKey,
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
      if (mounted) setState(() => _loaded = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _loaded = true;
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
      _storageKey,
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
        _storageKey,
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
      _message('Could not remove expired bookings: $error', error: true);
    }
  }

  Future<void> _changeLanguage(String language) async {
    if (language == _language) return;
    setState(() => _language = language);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString(_languageStorageKey, language);
      if (!saved) throw StateError('Could not save the language setting.');
    } catch (error) {
      _message('Could not save language preference: $error', error: true);
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
        _venues = _upsertNaderSalon(
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
      if (mounted) setState(() => _loginError = error.toString());
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
    if (!_api.isConfigured) return;
    final token = _adminToken;
    if (token == null) {
      throw StateError('Sign in as an admin to manage venues.');
    }
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
      _storageKey,
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
        backgroundColor: error ? Colors.red.shade700 : _ink,
      ),
    );
  }

  Future<void> _runSave(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      _message('Could not save changes: $error', error: true);
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
                    validator: _required,
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
                    id: _id(),
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
                    validator: _required,
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
                    validator: _positiveNumber,
                  ),
                  if (kind == 'PS5 room') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      onChanged: (value) => multiRate = value,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'EGP / hour with multiple controllers'),
                      validator: _positiveNumber,
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
                    id: _id(),
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
            ? Venue(
                id: value.id,
                name: value.name,
                location: value.location,
                type: value.type,
                ownerPhone: value.ownerPhone,
                depositPercent: value.depositPercent,
                items: [...value.items, result],
                services: value.services,
              )
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
                validator: _required,
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
                validator: _positiveNumber,
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
                  id: _id(),
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
            ? Venue(
                id: value.id,
                name: value.name,
                location: value.location,
                type: value.type,
                ownerPhone: value.ownerPhone,
                depositPercent: value.depositPercent,
                items: value.items,
                services: [...value.services, result],
              )
            : value)
        .toList();
    await _runSave(() => _commit(updated, _bookings));
  }

  Future<void> _removeItem(Venue venue, VenueItem item) async {
    final updatedVenues = _venues
        .map((value) => value.id == venue.id
            ? Venue(
                id: value.id,
                name: value.name,
                location: value.location,
                type: value.type,
                ownerPhone: value.ownerPhone,
                depositPercent: value.depositPercent,
                items:
                    value.items.where((entry) => entry.id != item.id).toList(),
                services: value.services,
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

  Future<void> _createBooking({
    required Venue venue,
    required VenueItem item,
    bool walkIn = false,
    DateTime? initialStart,
  }) async {
    final arabic = _language == 'AR';
    var customer = '';
    var phone = '';
    final formKey = GlobalKey<FormState>();
    var date = initialStart ?? DateTime.now();
    var time = TimeOfDay.fromDateTime(initialStart ??
        DateTime.now().add(walkIn ? Duration.zero : const Duration(hours: 1)));
    var durationMinutes = venue.type == VenueType.salon ? 30 : 60;
    var split = 1;
    var multi = false;
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

    double total() {
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

    final booking = await showDialog<Booking>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: _panel,
          surfaceTintColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          title: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_green, Color(0xFF059669)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.3),
                      blurRadius: 10,
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
                          ? _localized(arabic, 'Add Walk-in', 'إضافة حجز مباشر')
                          : _localized(arabic, 'Book Your Time', 'احجز موعدك'),
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _green.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${venue.name} · ${item.name}',
                        style: const TextStyle(
                          color: _green,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
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
                    TextFormField(
                      onChanged: (value) => customer = value,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: _localized(arabic, 'Your Name', 'الاسم'),
                        hintText: _localized(arabic, 'Enter Your Full Name',
                            'أدخل اسمك بالكامل'),
                        prefixIcon: const Icon(Icons.person_outline, color: _green),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _green, width: 2),
                        ),
                      ),
                      validator: _required,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      onChanged: (value) => phone = value,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText:
                            _localized(arabic, 'Phone Number', 'رقم الهاتف'),
                        hintText: '+20 10 1234 5678',
                        prefixIcon: const Icon(Icons.phone_outlined, color: _green),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _green, width: 2),
                        ),
                      ),
                      validator: _phoneValidator,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_outline_rounded, size: 13, color: _muted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _localized(
                                  arabic,
                                  'Fast & secure · phone used only for reservation updates.',
                                  'سريع وآمن · يستخدم الهاتف فقط لتحديثات الحجز.'),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _green.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: _green,
                                borderRadius: BorderRadius.circular(12),
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
                                    _localized(arabic, 'DATE & TIME',
                                        'التاريخ والوقت'),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.7,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${date.day}/${date.month}/${date.year} · ${time.format(context)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _panel,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _border),
                              ),
                              child: Text(
                                _localized(arabic, 'Change', 'تعديل'),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (venue.type == VenueType.salon &&
                        venue.services.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                          _localized(
                              arabic,
                              'Choose Services (Stacked Back-to-Back)',
                              'اختر الخدمات (تُحجز بالتتابع)'),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 6),
                      ...venue.services.map((service) => CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: selectedServices.contains(service.id),
                            title: Text(service.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                '${service.minutes} min · ${_money(service.price)} EGP',
                                style: const TextStyle(color: _muted)),
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
                      DropdownButtonFormField<int>(
                        initialValue: durationMinutes,
                        decoration: InputDecoration(
                          labelText: venue.type == VenueType.salon
                              ? 'Extra duration (15-minute blocks)'
                              : 'Duration',
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _green, width: 2),
                          ),
                          prefixIcon: const Icon(Icons.timer_outlined, color: _green),
                        ),
                        items: (venue.type == VenueType.salon
                                ? List.generate(8, (index) => (index + 1) * 15)
                                : [60, 90, 120, 180, 240])
                            .map((minutes) => DropdownMenuItem(
                                  value: minutes,
                                  child: Text(
                                    minutes < 60
                                        ? '$minutes minutes'
                                        : minutes % 60 == 0
                                            ? '${minutes ~/ 60} hour${minutes == 60 ? '' : 's'}'
                                            : '${minutes ~/ 60} hr ${minutes % 60} min',
                                  ),
                                ))
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => durationMinutes = value ?? 60),
                      ),
                    ],
                    if (venue.type == VenueType.lounge &&
                        item.kind == 'PS5 room' &&
                        item.multiRate > 0)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(_localized(
                            arabic, 'Multiple Controllers', 'عدة أذرع تحكم')),
                        subtitle: Text(
                            'Single ${_money(item.hourlyRate)} · Multi ${_money(item.multiRate)} EGP/hour'),
                        value: multi,
                        onChanged: (value) =>
                            setDialogState(() => multi = value),
                      ),
                    if (venue.type == VenueType.sports) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<int>(
                        initialValue: split,
                        decoration: InputDecoration(
                          labelText: _localized(arabic, 'Split Pitch Payment',
                              'تقسيم دفع الملعب'),
                          filled: true,
                          fillColor: const Color(0xFFF9FAFB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: _green, width: 2),
                          ),
                          prefixIcon: const Icon(Icons.group_outlined, color: _green),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 1,
                              child: Text(
                                  _localized(arabic, 'One Payer', 'شخص واحد'))),
                          DropdownMenuItem(
                              value: 4,
                              child: Text(_localized(arabic, 'Split 4 Ways',
                                  'تقسيم على ٤ أشخاص'))),
                          DropdownMenuItem(
                              value: 10,
                              child: Text(_localized(arabic, 'Split 10 Ways',
                                  'تقسيم على ١٠ أشخاص'))),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => split = value ?? 1),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Builder(
                      builder: (context) {
                        final amount = total();
                        final parts = split > 1 ? amount / split : amount;
                        final deposit = split > 1
                            ? amount / split
                            : amount * venue.depositPercent / 100;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0FDF4),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFBBF7D0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _localized(arabic, 'Total Amount', 'المبلغ الإجمالي'),
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: _muted),
                                  ),
                                  Text(
                                    _localized(
                                      arabic,
                                      '${_money(amount)} EGP${split > 1 ? ' (${_money(parts)}/person)' : ''}',
                                      '${_money(amount)} جنيه${split > 1 ? ' (${_money(parts)} للفرد)' : ''}',
                                    ),
                                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                                  ),
                                ],
                              ),
                              const Divider(height: 16),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _localized(arabic, 'Deposit Due Now', 'العربون المستحق الآن'),
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF047857)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _green,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${_money(deposit)} EGP',
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                              if (split == 1 && venue.depositPercent <= 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _localized(
                                      arabic,
                                      'This venue has not set a deposit, so this time cannot be reserved yet.',
                                      'لم يحدد المكان قيمة العربون، لذلك لا يمكن حجز هذا الوقت حالياً.'),
                                  style: const TextStyle(
                                    color: Color(0xFFB45309),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.shield_outlined, size: 14, color: Color(0xFF059669)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _localized(
                                          arabic,
                                          'Your time is held for 15 minutes while you pay. It is not confirmed until the deposit is verified.',
                                          'نحتفظ بالموعد لمدة ١٥ دقيقة. لا يتأكد الحجز إلا بعد التحقق من دفع العربون.'),
                                      style: const TextStyle(color: Color(0xFF047857), fontSize: 11),
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
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text(
                _localized(arabic, 'Cancel', 'إلغاء'),
                style: const TextStyle(fontWeight: FontWeight.w600, color: _muted),
              ),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
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
                  _message('This time is already held or booked.', error: true);
                  return;
                }
                final dueNow = split > 1
                    ? total() / split
                    : total() * venue.depositPercent / 100;
                if (!walkIn && dueNow <= 0) {
                  _message(
                    'This venue has no deposit configured, so reservations cannot be confirmed.',
                    error: true,
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  Booking(
                    id: _id(),
                    venueId: venue.id,
                    itemId: item.id,
                    customer: customer.trim(),
                    startsAt: startsAt(),
                    durationMinutes: duration(),
                    price: total(),
                    serviceNames: venue.services
                        .where(
                            (service) => selectedServices.contains(service.id))
                        .map((service) => service.name)
                        .toList(),
                    splitCount: split,
                    multiController: multi,
                    phone: phone.trim(),
                    email: '',
                    dueNow: walkIn ? 0 : dueNow,
                    status: walkIn ? 'confirmed' : 'pending_payment',
                    paymentStatus: walkIn ? 'unpaid' : 'unpaid',
                    holdExpiresAt: walkIn
                        ? null
                        : DateTime.now().add(const Duration(minutes: 15)),
                  ),
                );
              },
              icon: Icon(walkIn ? Icons.check_circle_outline : Icons.arrow_forward_rounded, size: 18),
              label: Text(
                walkIn
                    ? _localized(arabic, 'Save walk-in', 'حفظ الحجز المباشر')
                    : _localized(arabic, 'Continue to deposit',
                        'المتابعة إلى دفع العربون'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
    if (booking == null) return;
    var savedBooking = booking;
    var dueNow = booking.dueNow ?? booking.price;
    try {
      if (_api.isConfigured) {
        final remote = await _api.createBooking(
          {
            ...booking.toJson(),
            'serviceIds': selectedServices.toList(),
            'walkIn': walkIn,
          },
          adminToken: _mode == 'admin' ? _adminToken : null,
        );
        savedBooking = Booking.fromJson(remote);
        dueNow = (remote['dueNow'] as num?)?.toDouble() ?? booking.price;
      }
      await _commit(_venues, [..._bookings, savedBooking]);
      if (!walkIn) {
        await _showPaymentMethods(savedBooking, dueNow);
      }
    } catch (error) {
      _message('Could not create the reservation: $error', error: true);
    }
  }

  Future<void> _showPaymentMethods(Booking booking, double dueNow) async {
    final arabic = _language == 'AR';
    final method = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 520),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 28,
                offset: Offset(0, 8),
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
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4D4D8),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  _localized(arabic, 'Secure Your Time', 'أكّد موعدك'),
                  style: const TextStyle(
                      fontSize: 23, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 5),
                Text(
                  _localized(
                      arabic,
                      'Choose a payment method for your deposit.',
                      'اختر طريقة دفع العربون.'),
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: _page,
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                    border: Border.fromBorderSide(
                      BorderSide(color: _border),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_clock_outlined, color: _green),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _localized(arabic, '15-minute reservation hold',
                                  'حجز مؤقت لمدة ١٥ دقيقة'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _localized(
                                  arabic,
                                  'Not confirmed until payment is verified',
                                  'لا يتأكد الحجز إلا بعد التحقق من الدفع'),
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_money(dueNow)} ${_localized(arabic, 'EGP', 'جنيه')}',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_api.isConfigured) ...[
                  const SizedBox(height: 12),
                  Text(
                    _localized(
                        arabic,
                        'Saved on this device only. Connect the Hagzy API to share bookings.',
                        'محفوظ على هذا الجهاز فقط. اربط واجهة حجزي لمشاركة الحجوزات.'),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 14),
                _PaymentMethodTile(
                  icon: Icons.credit_card_rounded,
                  title: 'Paymob',
                  subtitle: _api.isConfigured
                      ? _localized(
                          arabic, 'Secure Online Checkout', 'دفع إلكتروني آمن')
                      : _localized(
                          arabic,
                          'Unavailable until shared checkout is configured',
                          'غير متاح حتى إعداد الدفع المشترك'),
                  enabled: _api.isConfigured,
                  onTap: () => Navigator.pop(context, 'paymob'),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Fawry',
                  subtitle: _localized(arabic, 'Checkout is not available yet',
                      'الدفع عبر فوري غير متاح حالياً'),
                ),
                const SizedBox(height: 8),
                _PaymentMethodTile(
                  icon: Icons.account_balance_outlined,
                  title: 'InstaPay',
                  subtitle: _localized(arabic, 'Not configured for this venue',
                      'لم يتم إعداد إنستا باي لهذا المكان'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, 'whatsapp'),
                  icon: const Icon(Icons.chat_outlined),
                  label: Text(_localized(
                      arabic, 'Continue in WhatsApp', 'تابع عبر واتساب')),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _localized(
                        arabic,
                        'WhatsApp opens a message to Hagzy. A chat does not confirm your booking or verify payment.',
                        'سيفتح واتساب رسالة إلى حجزي. المحادثة لا تؤكد الحجز ولا تتحقق من الدفع.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'later'),
                  child: Text(_localized(arabic, 'Pay later', 'ادفع لاحقاً')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (method == 'paymob') {
      await _startPaymobCheckout(booking);
    } else if (method == 'later') {
      if (mounted) setState(() => _tab = 1);
      if (!_api.isConfigured) {
        _message(_localized(
            arabic,
            'Reservation saved on this device only. Payment is still pending.',
            'تم حفظ الحجز على هذا الجهاز فقط. الدفع ما زال معلقاً.'));
      }
    } else if (method == 'whatsapp') {
      await _openWhatsAppBookingChat(booking);
    }
  }

  Future<void> _openWhatsAppBookingChat(Booking booking) async {
    final arabic = _language == 'AR';
    final venue =
        _venues.where((value) => value.id == booking.venueId).firstOrNull;
    final message = [
      _localized(arabic, 'Hello Hagzy, I need help with this reservation.',
          'مرحباً حجزي، أحتاج مساعدة بخصوص هذا الحجز.'),
      '${_localized(arabic, 'Reference', 'رقم الحجز')}: ${booking.id}',
      '${_localized(arabic, 'Name', 'الاسم')}: ${booking.customer}',
      '${_localized(arabic, 'Phone', 'الهاتف')}: ${booking.phone}',
      if (venue != null)
        '${_localized(arabic, 'Venue', 'المكان')}: ${venue.name}',
      '${_localized(arabic, 'Date and Time', 'التاريخ والوقت')}: ${_dateTime(booking.startsAt)}',
      '${_localized(arabic, 'Deposit Due', 'العربون المستحق')}: ${_money(booking.dueNow ?? booking.price)} ${_localized(arabic, 'EGP', 'جنيه')}',
      _localized(
          arabic,
          'Please note: I understand this is only a temporary hold until the deposit is verified.',
          'أفهم أن هذا الحجز مؤقت حتى يتم التحقق من دفع العربون.'),
    ].join('\n');
    final uri = Uri.https(
      'wa.me',
      '/$_whatsappBusinessNumber',
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
      _message('Could not open WhatsApp: $error', error: true);
    }
  }

  Future<void> _startPaymobCheckout(Booking booking) async {
    try {
      final parts = booking.customer.trim().split(RegExp(r'\s+'));
      final url = await _api.createPaymobCheckout(
        booking.id,
        firstName: parts.first,
        lastName: parts.length > 1 ? parts.skip(1).join(' ') : 'Customer',
        email: booking.email,
        phone: booking.phone,
      );
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw StateError('Could not open Paymob checkout.');
      _message(
          'Checkout opened. This time remains a hold until the server verifies your deposit.');
      if (!_api.isConfigured) return;
      // Poll for payment confirmation for up to 5 minutes
      var pollCount = 0;
      _paymentPollingTimer?.cancel();
      _paymentPollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
        pollCount++;
        if (pollCount > 60) {
          timer.cancel();
          return;
        }
        try {
          final remote = await _api.bookingStatus(booking.id);
          final updated = Booking.fromJson(remote);
          if (updated.isConfirmed) {
            timer.cancel();
            final newBookings = _bookings.map((b) => b.id == booking.id ? updated : b).toList();
            final newCustomerBookings = _customerBookings.map((b) => b.id == booking.id ? updated : b).toList();
            await _commit(_venues, newBookings);
            if (mounted) {
              setState(() => _customerBookings = newCustomerBookings);
            }
            _message(_language == 'AR' ? 'تم تأكيد حجزك! ✓' : 'Your booking is confirmed! ✓');
            return;
          }
          // Stop if hold expired
          if (!updated.isPendingPayment && !updated.isConfirmed) {
            timer.cancel();
          }
        } catch (_) {
          // Polling errors are silent — the booking card still shows the button
        }
      });
    } catch (error) {
      _message('Could not start Paymob checkout: $error', error: true);
    }
  }

  Future<void> _cancelBooking(Booking booking) async {
    final updated = _bookings
        .map((value) => value.id == booking.id
            ? Booking(
                id: value.id,
                venueId: value.venueId,
                itemId: value.itemId,
                customer: value.customer,
                startsAt: value.startsAt,
                durationMinutes: value.durationMinutes,
                price: value.price,
                serviceNames: value.serviceNames,
                splitCount: value.splitCount,
                multiController: value.multiController,
                cancelled: true,
                phone: value.phone,
                email: value.email,
                dueNow: value.dueNow,
                status: 'cancelled',
                paymentStatus: value.paymentStatus,
                holdExpiresAt: value.holdExpiresAt,
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

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
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
        ? const ['Explore', 'My Bookings']
        : const ['Explore', 'My Bookings', 'Manage Venues', 'Payment Settings'];
    final venueLabel = _venues.length == 1 ? 'venue' : 'venues';
    final bookingCount =
        _bookings.where((booking) => !booking.cancelled).length;
    final bookingLabel = bookingCount == 1 ? 'booking' : 'bookings';
    final arabic = _language == 'AR';
    final appTitles = arabic
        ? const ['استكشف', 'حجوزاتي', 'إدارة الأماكن', 'إعدادات الدفع']
        : titles;
    final mainApp = Localizations.override(
      context: context,
      locale: Locale(arabic ? 'ar' : 'en'),
      child: Theme(
        data: Theme.of(context).copyWith(
          textTheme: _buildTextTheme(context, arabic),
        ),
        child: Directionality(
          textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 72,
              titleSpacing: 16,
              title: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _showSplash = true),
                        child: const _HagzyLogoMark(size: 40, withGlow: true),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(arabic ? 'حجزي' : 'Hagzy',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, color: _ink)),
                          Text(appTitles[_tab],
                              style:
                                  const TextStyle(fontSize: 12, color: _muted)),
                        ],
                      ),
                      const Spacer(),
                      if (MediaQuery.sizeOf(context).width >= 360)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _LanguageOption(
                                label: 'EN',
                                selected: _language == 'EN',
                                onTap: () => _changeLanguage('EN'),
                              ),
                              _LanguageOption(
                                label: 'AR',
                                selected: _language == 'AR',
                                onTap: () => _changeLanguage('AR'),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 10),
                      if (MediaQuery.sizeOf(context).width >= 840)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 9),
                          decoration: BoxDecoration(
                            color: _dark,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            arabic
                                ? '${_venues.length} أماكن  ·  $bookingCount حجوزات'
                                : '${_venues.length} $venueLabel  ·  $bookingCount $bookingLabel',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700),
                          ),
                        ),
                      if (!isCustomer) ...[
                        const SizedBox(width: 6),
                        IconButton(
                          tooltip: 'Sign out',
                          onPressed: _returnToPortal,
                          icon: const Icon(Icons.logout),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              bottom: const PreferredSize(
                preferredSize: Size.fromHeight(1),
                child: Divider(height: 1, thickness: 1, color: _border),
              ),
            ),
            body: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = constraints.maxWidth < 600 ? 480.0 : 1120.0;
                final contentWidth = constraints.maxWidth < maxWidth
                    ? constraints.maxWidth
                    : maxWidth;
                return Center(
                  child: SizedBox(
                    width: contentWidth,
                    height: constraints.maxHeight,
                    child: ColoredBox(
                      color: _page,
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
                            child: isCustomer
                                ? IndexedStack(
                                    index: _tab,
                                    children: [
                                      _BookTab(
                                        venues: _venues,
                                        bookings: _bookings,
                                        arabic: arabic,
                                        onBook: (venue, item, startsAt) =>
                                            _createBooking(
                                          venue: venue,
                                          item: item,
                                          initialStart: startsAt,
                                        ),
                                      ),
                                      _MyBookingsTab(
                                        venues: _venues,
                                        bookings: _bookings,
                                        arabic: arabic,
                                        onChoosePayment: (booking) =>
                                            _showPaymentMethods(
                                          booking,
                                          booking.dueNow ?? booking.price,
                                        ),
                                        api: _api,
                                        apiConfigured: _api.isConfigured,
                                      ),
                                    ],
                                  )
                                : switch (_tab) {
                                    0 => _BookTab(
                                        venues: _venues,
                                        bookings: _bookings,
                                        arabic: arabic,
                                        onBook: (venue, item, startsAt) =>
                                            _createBooking(
                                          venue: venue,
                                          item: item,
                                          initialStart: startsAt,
                                        ),
                                        onAddVenue: (type) => _addVenue(
                                          initialType: type ?? VenueType.sports,
                                        ),
                                      ),
                                    1 => _MyBookingsTab(
                                        venues: _venues,
                                        bookings: _customerBookings,
                                        arabic: arabic,
                                        onChoosePayment: (booking) =>
                                            _showPaymentMethods(
                                          booking,
                                          booking.dueNow ?? booking.price,
                                        ),
                                        api: _api,
                                        apiConfigured: _api.isConfigured,
                                      ),
                                    2 => _AdminManageWorkspace(
                                        venues: _venues,
                                        bookings: _bookings,
                                        onAddVenue: _addVenue,
                                        onAddItem: _addItem,
                                        onAddService: _addService,
                                        onDelete: _deleteVenue,
                                        onRemoveItem: _removeItem,
                                        onWalkIn: (venue, item) =>
                                            _createBooking(
                                          venue: venue,
                                          item: item,
                                          walkIn: true,
                                        ),
                                        onCancel: _cancelBooking,
                                      ),
                                    _ => _PaymentTab(
                                        apiConfigured: _api.isConfigured,
                                        localPreview: isPreview,
                                      ),
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            bottomNavigationBar: _FloatingDock(
              selectedIndex: _tab,
              customerMode: isCustomer,
              arabic: arabic,
              onDestinationSelected: (value) => setState(() => _tab = value),
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
          child: _HagzySplashOverlay(
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
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const _IconBox(icon: Icons.lock_outline),
                const SizedBox(height: 18),
                const Text('Welcome back',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  _api.isConfigured
                      ? 'Sign in with the admin account created for your Hagzy server.'
                      : 'Connect your Hagzy API to sign in and sync venue data across devices.',
                  style: const TextStyle(color: _muted),
                ),
                const SizedBox(height: 20),
                if (_api.isConfigured) ...[
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                        labelText: 'Admin email',
                        prefixIcon: Icon(Icons.email_outlined)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    onSubmitted: (_) => _working ? null : _loginAdmin(),
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.key_outlined)),
                  ),
                  if (_loginError != null) ...[
                    const SizedBox(height: 12),
                    Text(_loginError!,
                        style: const TextStyle(color: Colors.redAccent)),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: _working ? null : _loginAdmin,
                    child: _working
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Sign in securely'),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _enterAdminPreview,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Open local preview'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Local preview data stays on this device and is not shared with customers on other phones.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
}

class _LocalPreviewNotice extends StatelessWidget {
  const _LocalPreviewNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF422006),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF854D0E)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: Color(0xFFFCD34D)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Local preview mode · Data stays on this device. Configure HAGZY_API_URL to share venues and reservations across phones.',
                style: TextStyle(color: Color(0xFFFDE68A)),
              ),
            ),
          ],
        ),
      );
}

class _MyBookingsTab extends StatefulWidget {
  const _MyBookingsTab({
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onChoosePayment,
    required this.api,
    required this.apiConfigured,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final bool arabic;
  final Future<void> Function(Booking booking) onChoosePayment;
  final HagzyApi api;
  final bool apiConfigured;

  @override
  State<_MyBookingsTab> createState() => _MyBookingsTabState();
}

class _MyBookingsTabState extends State<_MyBookingsTab> {
  bool _lookingUp = false;
  String? _lookupError;

  Future<void> _lookupByPhone() async {
    var phone = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_localized(
            widget.arabic, 'Find my bookings', 'ابحث عن حجوزاتي')),
        content: TextField(
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: _localized(
                widget.arabic, 'Phone number', 'رقم الهاتف'),
            hintText: '+20 10 1234 5678',
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
          onChanged: (value) => phone = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_localized(widget.arabic, 'Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_localized(widget.arabic, 'Search', 'بحث')),
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
      final results = await widget.api.bookingsByPhone(phone);
      final found = results
          .map((item) => Booking.fromJson(item as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      if (found.isEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_localized(
                widget.arabic, 'No bookings found', 'لم يتم العثور على حجوزات')),
            content: Text(_localized(
                widget.arabic,
                'No active bookings were found for this phone number.',
                'لا توجد حجوزات نشطة لهذا الرقم.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_localized(widget.arabic, 'OK', 'حسناً')),
              ),
            ],
          ),
        );
      } else {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_localized(
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
                      ? _localized(widget.arabic, 'Confirmed', 'مؤكد')
                      : b.isPendingPayment
                          ? _localized(widget.arabic, 'Pending', 'معلق')
                          : _localized(widget.arabic, 'Expired', 'منتهي');
                  return ListTile(
                    title: Text(b.customer),
                    subtitle: Text(
                      '${venue?.name ?? b.venueId} · ${_dateTime(b.startsAt)} · $statusLabel',
                    ),
                    trailing: Text(
                      '${_money(b.price)} EGP',
                      style: const TextStyle(
                          color: _green, fontWeight: FontWeight.w700),
                    ),
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_localized(widget.arabic, 'Close', 'إغلاق')),
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
          _IntroCard(
            title: _localized(arabic, 'Your Bookings', 'حجوزاتك'),
            subtitle: _localized(
                arabic,
                'Reservations you make will appear here.',
                'ستظهر حجوزاتك هنا.'),
            icon: Icons.calendar_month_outlined,
          ),
          const SizedBox(height: 16),
          _EmptyCard(
            icon: Icons.event_available_outlined,
            title:
                _localized(arabic, 'Nothing Booked Yet', 'لا توجد حجوزات بعد'),
            body: _localized(
                arabic,
                'Explore a venue and choose a time to get started.',
                'استكشف الأماكن واختر وقتاً للبدء.'),
          ),
          if (widget.apiConfigured) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _lookingUp ? null : () => _lookupByPhone(),
                icon: _lookingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.phone_outlined),
                label: Text(_localized(arabic, 'Find my bookings by phone',
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
        _IntroCard(
          title: _localized(arabic, 'Your Bookings', 'حجوزاتك'),
          subtitle: _localized(arabic, 'Keep track of upcoming reservations.',
              'تابع حجوزاتك القادمة.'),
          icon: Icons.calendar_month_outlined,
        ),
        const SizedBox(height: 12),
        ...active.map((booking) {
          final venue =
              widget.venues.where((item) => item.id == booking.venueId).firstOrNull;
          final status = booking.isConfirmed
              ? _localized(arabic, 'Confirmed', 'مؤكد')
              : booking.isPendingPayment
                  ? _localized(arabic, 'Awaiting Deposit', 'بانتظار العربون')
                  : _localized(arabic, 'Hold Expired', 'انتهى الحجز المؤقت');
          final statusColor = booking.isConfirmed
              ? _green
              : booking.isPendingPayment
                  ? const Color(0xFFB45309)
                  : _muted;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4F1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.event_available_rounded,
                          color: _green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              venue?.name ??
                                  _localized(
                                      arabic, 'Hagzy Reservation', 'حجز حجزي'),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            if (venue?.location.isNotEmpty ?? false)
                              Text(
                                venue!.location,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F7F5),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded,
                            color: _green, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            '${_dateTime(booking.startsAt)} · ${booking.durationMinutes} ${_localized(arabic, 'min', 'دقيقة')}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${_money(booking.price)} ${_localized(arabic, 'EGP', 'جنيه')}',
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!booking.isConfirmed) ...[
                    const SizedBox(height: 10),
                    Text(
                      booking.isPendingPayment
                          ? _localized(
                              arabic,
                              'This time is held temporarily. It is not confirmed until the deposit is paid and verified.',
                              'هذا الوقت محجوز مؤقتاً. لن يتأكد الحجز حتى يتم دفع العربون والتحقق منه.')
                          : _localized(
                              arabic,
                              'The payment window ended. Choose another available time to reserve.',
                              'انتهت مهلة الدفع. اختر وقتاً آخر متاحاً للحجز.'),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (booking.serviceNames.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      booking.serviceNames.join(' · '),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: booking.isPendingPayment
                          ? SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: () => widget.onChoosePayment(booking),
                                icon: const Icon(
                                    Icons.account_balance_wallet_outlined),
                                label: Text(_localized(
                                    arabic,
                                    'Pay Deposit · ${_money(booking.dueNow ?? booking.price)} EGP',
                                    'ادفع العربون · ${_money(booking.dueNow ?? booking.price)} جنيه')),
                              ),
                            )
                          : Text(
                              status,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
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
}

class _BookTab extends StatefulWidget {
  const _BookTab({
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onBook,
    this.onAddVenue,
  });
  final List<Venue> venues;
  final List<Booking> bookings;
  final bool arabic;
  final void Function(Venue venue, VenueItem item, DateTime startsAt) onBook;
  final ValueChanged<VenueType?>? onAddVenue;

  @override
  State<_BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<_BookTab> {
  VenueType? _type;
  String? _venueId;
  String? _itemId;
  String _query = '';
  String _area = _allEgyptAreas;
  Set<String> _favoriteIds = {};
  bool _favoritesOnly = false;
  bool _sortByPrice = false;
  DateTime _date = DateTime.now().hour >= 21
      ? DateTime.now().add(const Duration(days: 1))
      : DateTime.now();
  DateTime? _selectedStart;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bookingSectionKey = GlobalKey();
  final GlobalKey _spaceStepKey = GlobalKey();
  final GlobalKey _timeStepKey = GlobalKey();
  final GlobalKey _quoteStepKey = GlobalKey();
  final Map<String, GlobalKey> _venueCardKeys = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _selectVenue(Venue value) {
    if (_venueId == value.id) {
      setState(() {
        _venueId = null;
        _itemId = null;
        _selectedStart = null;
      });
      return;
    }
    setState(() {
      _venueId = value.id;
      _itemId = value.items.firstOrNull?.id;
      _selectedStart = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _venueCardKeys[value.id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
      }
    });
  }

  void _selectSpace(String itemId) {
    setState(() {
      _itemId = itemId;
      _selectedStart = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _timeStepKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.1,
        );
      }
    });
  }

  void _selectTime(DateTime start) {
    setState(() => _selectedStart = start);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _quoteStepKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      }
    });
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        alignment: 0.05,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadCustomerPreferences();
  }

  Future<void> _loadCustomerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favoriteIds =
          (prefs.getStringList(_favoriteStorageKey) ?? const <String>[])
              .toSet();
      _area = prefs.getString('hagzy_customer_area') ?? _allEgyptAreas;
    });
  }

  Future<void> _toggleFavorite(Venue venue) async {
    try {
      final next = {..._favoriteIds};
      if (!next.add(venue.id)) next.remove(venue.id);
      final prefs = await SharedPreferences.getInstance();
      final saved =
          await prefs.setStringList(_favoriteStorageKey, next.toList());
      if (!saved) {
        throw StateError('Could not save your favorites on this device.');
      }
      if (mounted) setState(() => _favoriteIds = next);
    } catch (error) {
      _showPreferenceError(error);
    }
  }

  Future<void> _chooseArea() async {
    var query = '';
    final area = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final options = [
            (
              _allEgyptAreas,
              _localized(widget.arabic, 'All Egypt', 'كل محافظات مصر')
            ),
            ..._egyptGovernorates.map(
              (governorate) => (
                governorate.$1,
                widget.arabic ? governorate.$2 : governorate.$1,
              ),
            ),
          ].where((entry) =>
              entry.$1.toLowerCase().contains(query.toLowerCase()) ||
              entry.$2.contains(query));
          return AlertDialog(
            title: Text(_localized(
                widget.arabic, 'Choose a governorate', 'اختر المحافظة')),
            content: SizedBox(
              width: 420,
              height: 480,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    textDirection:
                        widget.arabic ? TextDirection.rtl : TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: _localized(widget.arabic, 'Search governorates',
                          'ابحث عن محافظة'),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => query = value.trim()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = options.elementAt(index);
                        return ListTile(
                          title: Text(entry.$2),
                          trailing: entry.$1 == _area
                              ? const Icon(Icons.check, color: _green)
                              : null,
                          onTap: () => Navigator.pop(context, entry.$1),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_localized(widget.arabic, 'Cancel', 'إلغاء')),
              ),
            ],
          );
        },
      ),
    );
    if (area == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString('hagzy_customer_area', area);
      if (!saved) throw StateError('Could not save your selected area.');
      if (mounted) setState(() => _area = area);
    } catch (error) {
      _showPreferenceError(error);
    }
  }

  bool _locationMatchesArea(String location) {
    if (_area == _allEgyptAreas ||
        location.trim().isEmpty ||
        location.toLowerCase().contains('kafr el sheikh')) {
      return true;
    }
    final normalized = location.toLowerCase();
    final governorate =
        _egyptGovernorates.where((entry) => entry.$1 == _area).firstOrNull;
    if (governorate == null) return normalized.contains(_area.toLowerCase());
    if (normalized.contains(governorate.$1.toLowerCase()) ||
        location.contains(governorate.$2)) {
      return true;
    }
    final aliases = <String, List<String>>{
      'Cairo': [
        'new cairo',
        'heliopolis',
        'nasr city',
        'maadi',
        'zamalek',
        'tagamo3',
        'التجمع',
        'مصر الجديدة',
        'مدينة نصر',
        'المعادي',
        'الزمالك'
      ],
      'Giza': [
        '6th of october',
        '6 october',
        'sixth of october',
        'sheikh zayed',
        'الجيزة',
        'السادس من أكتوبر',
        'الشيخ زايد'
      ],
      'Alexandria': ['alex', 'اسكندرية'],
      'Kafr El Sheikh': ['kafr el sheikh', 'كفر الشيخ'],
    };
    return (aliases[_area] ?? const <String>[]).any((alias) =>
        normalized.contains(alias.toLowerCase()) || location.contains(alias));
  }

  void _showPreferenceError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not save this preference: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchingVenues = _upsertNaderSalon(widget.venues).where((venue) {
      final matchesCategory = _type == null || venue.type == _type;
      final matchesSearch = '${venue.name} ${venue.location}'
          .toLowerCase()
          .contains(_query.toLowerCase());
      final matchesFavorite =
          !_favoritesOnly || _favoriteIds.contains(venue.id);
      final matchesArea = _locationMatchesArea(venue.location);
      return matchesCategory && matchesSearch && matchesFavorite && matchesArea;
    }).toList()
      ..sort((a, b) {
        if (!_sortByPrice) return a.name.compareTo(b.name);
        return _startingPrice(a).compareTo(_startingPrice(b));
      });
    final venue =
        matchingVenues.where((value) => value.id == _venueId).firstOrNull;
    final item =
        venue?.items.where((value) => value.id == _itemId).firstOrNull ??
            venue?.items.firstOrNull;
    final estimatedMinutes = venue?.type == VenueType.salon
        ? venue!.services.isEmpty
            ? 30
            : venue.services.first.minutes
        : 60;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _CustomerAreaBar(
          area: _governorateName(_area, widget.arabic),
          arabic: widget.arabic,
          onTap: _chooseArea,
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: InputDecoration(
            hintText: _localized(
                widget.arabic,
                'Search venues, sports, salons...',
                'ابحث عن الأماكن والأنشطة...'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    onPressed: () => setState(() => _query = ''),
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() {
            _query = value;
            _venueId = null;
            _itemId = null;
            _selectedStart = null;
          }),
        ),
        const SizedBox(height: 14),
        RepaintBoundary(
          child: _CustomerHero(
            venueCount: widget.venues.length,
            type: _type,
            arabic: widget.arabic,
          ),
        ),
        const SizedBox(height: 20),
        _SectionHeading(
          title: _localized(
              widget.arabic, 'Explore Categories', 'استكشف التصنيفات'),
          subtitle: _localized(widget.arabic,
              'Something good is around the corner', 'أماكن مميزة بانتظارك'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            _CustomPill(
              label: _localized(widget.arabic, 'Everything', 'الكل'),
              icon: Icons.grid_view_rounded,
              selected: _type == null,
              onTap: () => _selectCategory(null),
            ),
            ...VenueType.values.map((type) => _CustomPill(
                  label: switch (type) {
                    VenueType.sports => _localized(
                        widget.arabic, 'Padel & Football', 'بادل وكرة قدم'),
                    VenueType.salon => _localized(
                        widget.arabic, 'Hair & Beauty', 'العناية والجمال'),
                    VenueType.lounge => _localized(
                        widget.arabic, 'Gaming & Tables', 'ألعاب وطاولات'),
                  },
                  icon: type.icon,
                  selected: _type == type,
                  onTap: () => _selectCategory(type),
                )),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _favoritesOnly
                    ? _localized(
                        widget.arabic, 'Your Saved Places', 'أماكنك المفضلة')
                    : _localized(
                        widget.arabic, 'Places to Book', 'أماكن للحجز'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: _localized(
                  widget.arabic,
                  _sortByPrice ? 'Sort Alphabetically' : 'Sort by Price',
                  _sortByPrice ? 'ترتيب أبجدي' : 'ترتيب حسب السعر'),
              onPressed: () => setState(() => _sortByPrice = !_sortByPrice),
              icon: Icon(
                  _sortByPrice ? Icons.sort_by_alpha : Icons.swap_vert_rounded),
            ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CustomPill(
                selected: !_favoritesOnly,
                label: _localized(widget.arabic, 'All Places', 'كل الأماكن'),
                onTap: () => setState(() => _favoritesOnly = false),
              ),
              const SizedBox(width: 8),
              _CustomPill(
                selected: _favoritesOnly,
                icon: Icons.favorite_border,
                label: _localized(widget.arabic, 'Saved', 'المفضلة'),
                onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
              ),
              if (_sortByPrice) ...[
                const SizedBox(width: 8),
                _CustomPill(
                  icon: Icons.south,
                  label: _localized(widget.arabic, 'Lowest Price', 'أقل سعر'),
                  selected: false,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (matchingVenues.isEmpty)
          _EmptyCard(
            icon: _favoritesOnly ? Icons.favorite_border : Icons.store_outlined,
            title: _favoritesOnly
                ? _localized(widget.arabic, 'No Saved Places Yet',
                    'لا توجد أماكن مفضلة بعد')
                : _localized(
                    widget.arabic, 'No Places Found Here', 'لا توجد أماكن هنا'),
            body: _favoritesOnly
                ? _localized(
                    widget.arabic,
                    'Tap the heart on a venue to keep it close.',
                    'اضغط على القلب لحفظ المكان في المفضلة.')
                : widget.venues.isEmpty
                    ? _localized(
                        widget.arabic,
                        'We’re bringing great local venues to Hagzy. Check back soon.',
                        'نعمل على إضافة أماكن رائعة بالقرب منك. تفقّدنا قريباً.')
                    : _localized(
                        widget.arabic,
                        'Try another category, search or area.',
                        'جرّب تصنيفاً أو بحثاً أو محافظة أخرى.'),
            action: !_favoritesOnly && widget.onAddVenue != null
                ? () => widget.onAddVenue!(_type)
                : null,
            actionLabel: _localized(
                widget.arabic,
                'Add New Venue / Pitch / Barber',
                'أضف مكاناً أو ملعباً أو حلاقاً'),
          )
        else
          ...matchingVenues.expand((value) {
            final selected = value.id == venue?.id;
            return [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: RepaintBoundary(
                  child: _VenueBrowseCard(
                    key: _venueCardKeys.putIfAbsent(value.id, () => GlobalKey()),
                    venue: value,
                    arabic: widget.arabic,
                    selected: selected,
                    favorite: _favoriteIds.contains(value.id),
                    onTap: () => _selectVenue(value),
                    onFavorite: () => _toggleFavorite(value),
                  ),
                ),
              ),
              if (selected && venue != null) ...[
                _buildConsecutiveStepper(
                  venue: venue,
                  item: item,
                  selectedStart: _selectedStart,
                  arabic: widget.arabic,
                ),
                _StepPanel(
                  key: _bookingSectionKey,
                  number: '1',
                  title: _localized(widget.arabic, 'Your Booking', 'حجزك'),
                  subtitle: _localized(
                      widget.arabic,
                      'Choose a space and time at your selected venue',
                      'اختر المكان والوقت المناسبين'),
                  isCompleted: true,
                  trailing: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _venueId = null;
                        _itemId = null;
                        _selectedStart = null;
                      });
                      _scrollController.animateTo(
                        0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text(_localized(widget.arabic, 'Close', 'إغلاق')),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _green.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _green.withValues(alpha: 0.18)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(venue.type.icon, size: 20, color: _green),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${venue.name}${venue.location.isEmpty ? '' : ' · ${venue.location}'}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _localized(
                                    widget.arabic,
                                    'Venue selected · Pick your space and time below',
                                    'تم اختيار المكان · حدد المساحة والوقت بالأسفل'),
                                style: const TextStyle(
                                    color: _green, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _StepPanel(
                  key: _spaceStepKey,
                  number: '02',
                  title:
                      _localized(widget.arabic, 'Choose Your Space', 'اختر المساحة'),
                  subtitle: _localized(
                      widget.arabic,
                      'Court, barber chair, PS5 room or table',
                      'ملعب أو كرسي حلاقة أو غرفة بلايستيشن أو طاولة'),
                  isCompleted: item != null,
                  child: venue.items.isEmpty
                      ? Text(
                          _localized(
                              widget.arabic,
                              'This venue has no bookable spaces yet.',
                              'لا توجد مساحات متاحة للحجز حالياً.'),
                          style: const TextStyle(color: _muted))
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: venue.items.map((val) {
                            final sel = val.id == item?.id;
                            return _CustomPill(
                              icon: venue.type.icon,
                              label:
                                  '${val.name} · ${_money(val.hourlyRate)} EGP${venue.type == VenueType.salon ? '/15m' : '/h'}',
                              selected: sel,
                              onTap: () => _selectSpace(val.id),
                            );
                          }).toList(),
                        ),
                ),
                if (item != null) ...[
                  const SizedBox(height: 12),
                  _StepPanel(
                    key: _timeStepKey,
                    number: '03',
                    title: _localized(
                        widget.arabic, 'Pick an Available Time', 'اختر وقتاً متاحاً'),
                    subtitle: _localized(
                        widget.arabic,
                        'Availability preview checks a $estimatedMinutes-minute block. Final duration is set at checkout.',
                        'معاينة التوفر لمدة $estimatedMinutes دقيقة. يتم تأكيد المدة عند الدفع.'),
                    isCompleted: _selectedStart != null,
                    trailing: Container(
                      decoration: BoxDecoration(
                        color: _panel,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          final selectedDate = await showDatePicker(
                            context: context,
                            initialDate:
                                _date.isBefore(DateTime.now()) ? DateTime.now() : _date,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 180)),
                          );
                          if (selectedDate != null) {
                            setState(() {
                              _date = selectedDate;
                              _selectedStart = null;
                            });
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_month, size: 16, color: _green),
                              const SizedBox(width: 6),
                              Text(
                                '${_date.day}/${_date.month}/${_date.year}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    child: Builder(
                      builder: (context) {
                        final allSlots = _timesFor(venue, item, estimatedMinutes);
                        final morningSlots =
                            allSlots.where((s) => s.start.hour < 13).toList();
                        final afternoonSlots = allSlots
                            .where((s) => s.start.hour >= 13 && s.start.hour < 17)
                            .toList();
                        final eveningSlots =
                            allSlots.where((s) => s.start.hour >= 17).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _localized(widget.arabic, 'Select Date', 'اختر التاريخ'),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 12, color: _green),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$estimatedMinutes ${_localized(widget.arabic, 'min', 'دقيقة')}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _green,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildDateStrip(widget.arabic),
                            const SizedBox(height: 18),
                            _buildTimeSlotGroup(
                              title: _localized(widget.arabic, 'Morning (10 AM - 1 PM)',
                                  'الصباح (١٠ ص - ١ م)'),
                              icon: Icons.wb_sunny_rounded,
                              slots: morningSlots,
                              arabic: widget.arabic,
                            ),
                            _buildTimeSlotGroup(
                              title: _localized(widget.arabic,
                                  'Afternoon (1 PM - 5 PM)', 'بعد الظهر (١ م - ٥ م)'),
                              icon: Icons.wb_twilight_rounded,
                              slots: afternoonSlots,
                              arabic: widget.arabic,
                            ),
                            _buildTimeSlotGroup(
                              title: _localized(widget.arabic,
                                  'Evening & Night (5 PM - 10 PM)',
                                  'المساء والليل (٥ م - ١٠ م)'),
                              icon: Icons.nightlight_round,
                              slots: eveningSlots,
                              arabic: widget.arabic,
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StepPanel(
                    key: _quoteStepKey,
                    number: '04',
                    title:
                        _localized(widget.arabic, 'Review and Secure', 'راجع وأكّد'),
                    subtitle: _localized(
                        widget.arabic,
                        'Your name and phone are enough to continue.',
                        'يكفي الاسم ورقم الهاتف للمتابعة.'),
                    child: _ReservationQuote(
                      venue: venue,
                      item: item,
                      arabic: widget.arabic,
                      estimatedMinutes: estimatedMinutes,
                      selectedStart: _selectedStart,
                      onReserve: _selectedStart == null
                          ? null
                          : () => widget.onBook(venue, item, _selectedStart!),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
              ],
            ];
          }),
      ],
    );
  }

  List<_TimeSlot> _timesFor(Venue venue, VenueItem item, int durationMinutes) {
    final slots = <_TimeSlot>[];
    final day = DateTime(_date.year, _date.month, _date.day);
    for (var minutes = 10 * 60; minutes <= 22 * 60; minutes += 30) {
      final start = day.add(Duration(minutes: minutes));
      final end = start.add(Duration(minutes: durationMinutes));
      final isPast = !start.isAfter(DateTime.now());
      final overlap = widget.bookings
          .where((booking) =>
              booking.blocksAvailability &&
              booking.venueId == venue.id &&
              booking.itemId == item.id &&
              start.isBefore(booking.endsAt) &&
              end.isAfter(booking.startsAt))
          .firstOrNull;
      final isBooked = overlap != null;
      final isHold = overlap?.isPendingPayment ?? false;
      slots.add(_TimeSlot(
        start: start,
        label:
            '${TimeOfDay.fromDateTime(start).format(context)}${isBooked ? (isHold ? ' · Held' : ' · Booked') : ''}',
        available: !isPast && !isBooked,
      ));
    }
    return slots;
  }

  void _selectCategory(VenueType? type) {
    setState(() {
      _type = type;
      _venueId = null;
      _itemId = null;
      _selectedStart = null;
    });
  }

  double _startingPrice(Venue venue) {
    if (venue.type == VenueType.salon && venue.services.isNotEmpty) {
      return venue.services
          .map((service) => service.price)
          .reduce((a, b) => a < b ? a : b);
    }
    if (venue.items.isEmpty) return double.infinity;
    return venue.items
        .map((item) => item.hourlyRate)
        .reduce((a, b) => a < b ? a : b);
  }

  String _dayLabel(DateTime date, bool arabic) {
    final now = DateTime.now();
    final isToday = date.year == now.year && date.month == now.month && date.day == now.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day;
    if (isToday) return _localized(arabic, 'Today', 'اليوم');
    if (isTomorrow) return _localized(arabic, 'Tomorrow', 'غداً');
    final weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekdaysAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    return _localized(arabic, weekdaysEn[date.weekday - 1], weekdaysAr[date.weekday - 1]);
  }

  String _monthLabel(int month, bool arabic) {
    const monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const monthsAr = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return _localized(arabic, monthsEn[month - 1], monthsAr[month - 1]);
  }

  Widget _buildDateStrip(bool arabic) {
    final today = DateTime.now();
    final days = List.generate(
      14,
      (index) => DateTime(today.year, today.month, today.day).add(Duration(days: index)),
    );
    return SizedBox(
      height: 78,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (context, index) {
          final d = days[index];
          final isSelected = d.year == _date.year && d.month == _date.month && d.day == _date.day;
          return Padding(
            padding: EdgeInsets.only(right: arabic ? 0 : 8, left: arabic ? 8 : 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() {
                  _date = d;
                  _selectedStart = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 66,
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [_green, Color(0xFF059669)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        )
                      : null,
                  color: isSelected ? null : _panel,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? _green : _border,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _dayLabel(d, arabic),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: isSelected ? Colors.white70 : _muted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: isSelected ? Colors.white : _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _monthLabel(d.month, arabic),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected ? Colors.white70 : _muted,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 3),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeSlotGroup({
    required String title,
    required IconData icon,
    required List<_TimeSlot> slots,
    required bool arabic,
  }) {
    if (slots.isEmpty) return const SizedBox.shrink();
    final availableCount = slots.where((s) => s.available).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(icon, size: 15, color: _muted),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: availableCount > 0
                        ? const Color(0xFF10B981).withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    availableCount > 0
                        ? _localized(arabic, '$availableCount available', '$availableCount متاح')
                        : _localized(arabic, 'Fully booked', 'مكتمل'),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: availableCount > 0
                          ? const Color(0xFF059669)
                          : _muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: slots.map((slot) {
              final selected = _selectedStart == slot.start;
              return _TimeSlotPill(
                label: slot.label,
                selected: selected,
                available: slot.available,
                onTap: slot.available
                    ? () => _selectTime(slot.start)
                    : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildConsecutiveStepper({
    required Venue venue,
    required VenueItem? item,
    required DateTime? selectedStart,
    required bool arabic,
  }) {
    final hasSpace = item != null;
    final hasTime = selectedStart != null;

    Widget buildStepIndicator({
      required String stepNumber,
      required String title,
      required String? subtitle,
      required bool isDone,
      required bool isActive,
      required VoidCallback onTap,
    }) {
      final color = isDone
          ? const Color(0xFF10B981)
          : isActive
              ? _green
              : _muted.withValues(alpha: 0.5);

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? _green.withValues(alpha: 0.08) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive ? _green : Colors.transparent,
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                  child: Center(
                    child: isDone
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : Text(
                            stepNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isActive ? _ink : _muted,
                        ),
                      ),
                      if (subtitle != null && subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: isDone ? const Color(0xFF059669) : _muted,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          buildStepIndicator(
            stepNumber: '1',
            title: _localized(arabic, 'Space', 'المساحة'),
            subtitle: item?.name,
            isDone: hasSpace,
            isActive: !hasSpace || !hasTime,
            onTap: () => _scrollToKey(_spaceStepKey),
          ),
          Icon(
            arabic ? Icons.chevron_left : Icons.chevron_right,
            size: 16,
            color: _muted.withValues(alpha: 0.4),
          ),
          buildStepIndicator(
            stepNumber: '2',
            title: _localized(arabic, 'Date & Time', 'الموعد'),
            subtitle: selectedStart != null
                ? TimeOfDay.fromDateTime(selectedStart).format(context)
                : null,
            isDone: hasTime,
            isActive: hasSpace && !hasTime,
            onTap: () => _scrollToKey(_timeStepKey),
          ),
          Icon(
            arabic ? Icons.chevron_left : Icons.chevron_right,
            size: 16,
            color: _muted.withValues(alpha: 0.4),
          ),
          buildStepIndicator(
            stepNumber: '3',
            title: _localized(arabic, 'Confirm', 'تأكيد'),
            subtitle: hasTime ? '${_money(venue.depositPercent)}%' : null,
            isDone: false,
            isActive: hasSpace && hasTime,
            onTap: () => _scrollToKey(_quoteStepKey),
          ),
        ],
      ),
    );
  }
}

class _ReservationQuote extends StatelessWidget {
  const _ReservationQuote({
    required this.venue,
    required this.item,
    required this.estimatedMinutes,
    required this.arabic,
    required this.selectedStart,
    required this.onReserve,
  });

  final Venue venue;
  final VenueItem item;
  final int estimatedMinutes;
  final bool arabic;
  final DateTime? selectedStart;
  final VoidCallback? onReserve;

  @override
  Widget build(BuildContext context) {
    final total = venue.type == VenueType.salon && venue.services.isNotEmpty
        ? venue.services.first.price
        : item.hourlyRate *
            estimatedMinutes /
            (venue.type == VenueType.salon ? 15 : 60);
    final deposit = total * venue.depositPercent / 100;
    return Container(
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (selectedStart != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.event_available_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dateTime(selectedStart!),
                          style: const TextStyle(
                            color: _green,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$estimatedMinutes min',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _muted),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_localized(arabic, 'Total Estimate', 'الإجمالي التقريبي'),
                  style: const TextStyle(color: _muted)),
              Text('${_money(total)} ${_localized(arabic, 'EGP', 'جنيه')}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                  '${_localized(arabic, 'Deposit', 'العربون')} (${_money(venue.depositPercent)}%)',
                  style: const TextStyle(color: _muted)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_money(deposit)} ${_localized(arabic, 'EGP', 'جنيه')}',
                  style: const TextStyle(
                      color: _green, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (selectedStart != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_localized(arabic, 'Selected Time', 'الوقت المختار'),
                    style: const TextStyle(color: _muted)),
                Text(_dateTime(selectedStart!),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined,
                    size: 18, color: Color(0xFFD97706)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _localized(
                        arabic,
                        'We hold the time for 15 minutes. It is confirmed only after the deposit is verified.',
                        'نحتفظ بالموعد لمدة ١٥ دقيقة. يتأكد الحجز فقط بعد التحقق من دفع العربون.'),
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: onReserve,
              icon: const Icon(Icons.lock_outline_rounded, size: 18),
              label: Text(
                _localized(arabic, 'Reserve & pay deposit', 'احجز وادفع العربون'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeSlot {
  const _TimeSlot(
      {required this.start, required this.label, required this.available});
  final DateTime start;
  final String label;
  final bool available;
}

class _TimeSlotPill extends StatelessWidget {
  const _TimeSlotPill({
    required this.label,
    required this.selected,
    required this.available,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool available;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? _green
              : available
                  ? _panel
                  : const Color(0xFFF4F4F5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _green
                : available
                    ? _border
                    : const Color(0xFFE4E4E7),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : available
                            ? Icons.schedule_rounded
                            : Icons.lock_clock_outlined,
                    size: 15,
                    color: selected
                        ? Colors.white
                        : available
                            ? _green
                            : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : available
                              ? const Color(0xFF27272A)
                              : const Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _CustomerAreaBar extends StatelessWidget {
  const _CustomerAreaBar({
    required this.area,
    required this.arabic,
    required this.onTap,
  });

  final String area;
  final bool arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: _green, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_localized(arabic, 'YOUR AREA', 'محافظتك'),
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6)),
                    const SizedBox(height: 1),
                    Text(area,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: _ink)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _page,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_localized(arabic, 'Change', 'تغيير'),
                        style: const TextStyle(
                            color: _ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(width: 3),
                    const Icon(Icons.keyboard_arrow_down,
                        color: _muted, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _CustomerHero extends StatelessWidget {
  const _CustomerHero({
    required this.venueCount,
    required this.type,
    required this.arabic,
  });

  final int venueCount;
  final VenueType? type;
  final bool arabic;

  (List<Color>, IconData, String, String) get _content => switch (type) {
        VenueType.sports => (
            const [Color(0xFF0F172A), Color(0xFF1E3A8A)],
            Icons.sports_tennis,
            _localized(arabic, 'Padel & Football', 'بادل وكرة قدم'),
            _localized(arabic, 'Courts, Pitches & Split-Pay Matches',
                'ملاعب ومباريات مع تقسيم الدفع'),
          ),
        VenueType.salon => (
            const [Color(0xFF18181B), Color(0xFF3F3F46)],
            Icons.content_cut,
            _localized(arabic, 'Hair & Beauty', 'العناية والجمال'),
            _localized(arabic, 'Barbershops, Grooming & Chair Locks',
                'حلاقة وعناية وحجز الكراسي'),
          ),
        VenueType.lounge => (
            const [Color(0xFF0F172A), Color(0xFF312E81)],
            Icons.sports_esports,
            _localized(arabic, 'Gaming & Tables', 'ألعاب وطاولات'),
            _localized(arabic, 'PS5 VIP Rooms, Billiards & Ping Pong',
                'غرف بلايستيشن وبلياردو وبينغ بونغ'),
          ),
        null => (
            const [Color(0xFF0F172A), Color(0xFF064E3B)],
            Icons.event_available,
            _localized(arabic, 'Find your next favorite', 'اكتشف مكانك المفضل'),
            arabic
                ? '$venueCount ${venueCount == 1 ? 'مكان محلي لاكتشافه' : 'أماكن محلية لاكتشافها'}'
                : '$venueCount local ${venueCount == 1 ? 'place' : 'places'} to discover',
          ),
      };

  String get _image => switch (type) {
        VenueType.sports =>
          'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=480&q=65',
        VenueType.salon =>
          'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=480&q=65',
        VenueType.lounge =>
          'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=480&q=65',
        null =>
          'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=480&q=65',
      };

  @override
  Widget build(BuildContext context) {
    final content = _content;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Container(
        key: ValueKey(type),
        height: 156,
        padding: const EdgeInsets.all(20),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: content.$1,
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Stack(
          children: [
            Positioned(
              right: arabic ? null : -4,
              left: arabic ? -4 : null,
              top: -4,
              bottom: -4,
              width: MediaQuery.sizeOf(context).width * .48,
              child: Image.network(
                _image,
                fit: BoxFit.cover,
                cacheWidth: 600,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) => Align(
                  alignment: Alignment.centerRight,
                  child: Icon(content.$2,
                      size: 124, color: Colors.white.withValues(alpha: .19)),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    stops: const [0, .43, 1],
                    colors: [
                      content.$1.first,
                      content.$1.first.withValues(alpha: .94),
                      content.$1.last.withValues(alpha: .12),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: arabic ? Alignment.centerRight : Alignment.centerLeft,
              child: Column(
                crossAxisAlignment:
                    arabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(content.$3,
                      style: const TextStyle(
                          color: Color(0xFFFFD19A),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5)),
                  const SizedBox(height: 9),
                  SizedBox(
                    width: MediaQuery.sizeOf(context).width * .62,
                    child: Text(
                      content.$4,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          height: 1.18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.45),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_rounded,
                          size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      Text(
                        arabic
                            ? '$venueCount ${venueCount == 1 ? 'مكان قريب' : 'أماكن قريبة'}'
                            : '$venueCount ${venueCount == 1 ? 'place' : 'places'} nearby',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
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
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      );
}

class _CustomPill extends StatelessWidget {
  const _CustomPill({
    required this.label,
    this.icon,
    required this.selected,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: selected ? _green : _panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _green : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(
                      icon,
                      size: 16,
                      color: selected ? Colors.white : _muted,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? Colors.white : _ink,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _LanguageOption extends StatelessWidget {
  const _LanguageOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? _dark : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : _muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
}

class _FloatingDock extends StatelessWidget {
  const _FloatingDock({
    required this.selectedIndex,
    required this.customerMode,
    required this.arabic,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final bool customerMode;
  final bool arabic;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final items = customerMode
        ? const [
            (Icons.explore_rounded, 'Explore'),
            (Icons.calendar_month_rounded, 'My Bookings'),
          ]
        : const [
            (Icons.explore_rounded, 'Explore'),
            (Icons.calendar_month_rounded, 'My Bookings'),
            (Icons.storefront_rounded, 'Manage Venues'),
            (Icons.account_balance_wallet_rounded, 'Payment Settings'),
          ];
    final localizedItems = items
        .map((item) => (
              item.$1,
              switch (item.$2) {
                'Explore' => _localized(arabic, 'Explore', 'استكشف'),
                'My Bookings' => _localized(arabic, 'My Bookings', 'حجوزاتي'),
                'Manage Venues' =>
                  _localized(arabic, 'Manage Venues', 'إدارة الأماكن'),
                'Payment Settings' =>
                  _localized(arabic, 'Payment Settings', 'إعدادات الدفع'),
                _ => item.$2,
              },
            ))
        .toList();
    return Container(
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(top: BorderSide(color: _border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Row(
                children: List.generate(localizedItems.length, (index) {
                  final selected = selectedIndex == index;
                  return Expanded(
                    child: InkWell(
                      onTap: () => onDestinationSelected(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: selected
                                    ? _green.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                localizedItems[index].$1,
                                size: 21,
                                color: selected ? _green : _muted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              localizedItems[index].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: selected ? _ink : _muted,
                                fontSize: 10,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VenueBrowseCard extends StatelessWidget {
  const _VenueBrowseCard({
    super.key,
    required this.venue,
    required this.arabic,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
  });

  final Venue venue;
  final bool arabic;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  Color get _accent => switch (venue.type) {
        VenueType.sports => const Color(0xFF4778A8),
        VenueType.salon => const Color(0xFFB16C68),
        VenueType.lounge => const Color(0xFF7968A8),
      };

  String get _image =>
      (venue.imageUrl != null && venue.imageUrl!.isNotEmpty)
          ? venue.imageUrl!
          : switch (venue.type) {
              VenueType.sports =>
                'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=400&q=65',
              VenueType.salon =>
                'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=400&q=65',
              VenueType.lounge =>
                'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=400&q=65',
            };

  @override
  Widget build(BuildContext context) {
    final lowestPrice =
        venue.type == VenueType.salon && venue.services.isNotEmpty
            ? venue.services
                .map((service) => service.price)
                .reduce((a, b) => a < b ? a : b)
            : venue.items.isEmpty
                ? null
                : venue.items
                    .map((item) => item.hourlyRate)
                    .reduce((a, b) => a < b ? a : b);
    final rateLabel = venue.type == VenueType.salon
        ? _localized(arabic, 'per service', 'للخدمة')
        : _localized(arabic, 'per hour', 'للساعة');
    final spaceLabel = switch (venue.type) {
      VenueType.sports => _localized(arabic, 'Courts', 'ملاعب'),
      VenueType.salon => _localized(arabic, 'Chairs', 'كراسي'),
      VenueType.lounge => _localized(arabic, 'Spaces', 'أماكن'),
    };
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: selected ? _green : _border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 112,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _accent.withValues(alpha: .96),
                    _accent.withValues(alpha: .72),
                  ],
                  begin: Alignment.bottomLeft,
                  end: Alignment.topRight,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      _image,
                      fit: BoxFit.cover,
                      cacheWidth: 480,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            _accent.withValues(alpha: .86),
                            _accent.withValues(alpha: .24),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(venue.type.icon, size: 12, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            switch (venue.type) {
                              VenueType.sports => _localized(
                                  arabic, 'SPORTS & COURTS', 'رياضة وملاعب'),
                              VenueType.salon =>
                                _localized(arabic, 'HAIR & BEAUTY', 'عناية وجمال'),
                              VenueType.lounge => _localized(
                                  arabic, 'GAMES & TABLES', 'ألعاب وطاولات'),
                            },
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                letterSpacing: .6,
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: favorite
                            ? _localized(
                                arabic, 'Remove from Saved', 'إزالة من المفضلة')
                            : _localized(arabic, 'Save Venue', 'أضف للمفضلة'),
                        visualDensity: VisualDensity.compact,
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite ? Icons.favorite : Icons.favorite_border,
                          color: favorite ? Colors.redAccent : _muted,
                          size: 19,
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 3),
                          Text(
                            _localized(arabic, '4.9 · Verified', '4.9 · مكان معتمد'),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 13, 16, 15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(venue.name,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w800)),
                      ),
                      if (selected)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle,
                                  color: _green, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                _localized(arabic, 'Selected', 'محدد'),
                                style: const TextStyle(
                                  color: _green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 15, color: _muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          venue.location.isEmpty
                              ? _localized(
                                  arabic,
                                  'Location Details Available on Booking',
                                  'تفاصيل الموقع عند الحجز')
                              : venue.location,
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                      Icon(Icons.circle, size: 6, color: _accent),
                      const SizedBox(width: 5),
                      Text('${venue.items.length} $spaceLabel',
                          style: const TextStyle(color: _muted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(color: _ink, fontSize: 12),
                            children: [
                              TextSpan(
                                  text:
                                      _localized(arabic, 'From ', 'يبدأ من ')),
                              TextSpan(
                                text: lowestPrice == null
                                    ? _localized(arabic, 'Price on Request',
                                        'السعر عند الطلب')
                                    : '${_money(lowestPrice)} EGP',
                                style: const TextStyle(
                                    color: _green,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800),
                              ),
                              if (lowestPrice != null)
                                TextSpan(
                                  text: ' $rateLabel',
                                  style: const TextStyle(color: _muted),
                                ),
                            ],
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: selected
                              ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                              : _green.withValues(alpha: 0.12),
                          foregroundColor:
                              selected ? const Color(0xFFEF4444) : _green,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          elevation: 0,
                        ),
                        onPressed: onTap,
                        icon: Icon(
                          selected
                              ? Icons.close_rounded
                              : Icons.calendar_today_rounded,
                          size: 15,
                        ),
                        label: Text(selected
                            ? _localized(arabic, 'Close', 'إغلاق')
                            : _localized(arabic, 'View Times', 'عرض الأوقات')),
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
  }
}

class _StepPanel extends StatelessWidget {
  const _StepPanel({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
    this.isCompleted = false,
  });
  final String number;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? _green
                          : _green.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : Text(
                              number,
                              style: const TextStyle(
                                color: _green,
                                fontWeight: FontWeight.w800,
                                fontSize: 10,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _ink),
                              ),
                            ),
                            if (isCompleted) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '✓',
                                  style: TextStyle(
                                    color: _green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle,
                            style:
                                const TextStyle(color: _muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      );
}

class _ManageTab extends StatelessWidget {
  const _ManageTab({
    required this.venues,
    required this.onAddVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onDelete,
    required this.onRemoveItem,
  });
  final List<Venue> venues;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          _IntroCard(
            title: 'Your self-service builder',
            subtitle:
                'Add a venue after contacting its owner, then list bookable spaces and services.',
            icon: Icons.add_business_outlined,
            action: FilledButton.icon(
              onPressed: onAddVenue,
              icon: const Icon(Icons.add),
              label: const Text('Add venue'),
            ),
          ),
          const SizedBox(height: 14),
          if (venues.isEmpty)
            const _EmptyCard(
              icon: Icons.add_business_outlined,
              title: 'Build your first venue',
              body:
                  'Choose a venue type, add spaces or chairs, then set prices.',
            ),
          ...venues.map((venue) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _IconBox(icon: venue.type.icon),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(venue.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text(venue.type.label,
                                    style: const TextStyle(color: _muted)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Delete venue',
                            onPressed: () => onDelete(venue),
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                          ),
                        ],
                      ),
                      if (venue.location.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(venue.location,
                              style: const TextStyle(color: _muted)),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Owner phone: ${venue.ownerPhone.isEmpty ? 'Not provided' : venue.ownerPhone} · '
                          'Deposit policy: ${_money(venue.depositPercent)}%',
                          style: const TextStyle(color: _muted),
                        ),
                      ),
                      const Divider(height: 24),
                      Text(
                          '${venue.items.length} bookable spaces · ${venue.services.length} services'),
                      ...venue.items.map((item) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text('${item.name} · ${item.kind}'),
                            subtitle: Text(
                                '${_money(item.hourlyRate)} EGP${item.multiRate > 0 ? ' / ${_money(item.multiRate)} multi' : ''}'),
                            trailing: IconButton(
                              tooltip: 'Remove space',
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => onRemoveItem(venue, item),
                            ),
                          )),
                      if (venue.services.isNotEmpty)
                        ...venue.services.map((service) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.content_cut),
                              title: Text(service.name),
                              subtitle: Text(
                                  '${service.minutes} minutes · ${_money(service.price)} EGP'),
                            )),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => onAddItem(venue),
                            icon: const Icon(Icons.add_box_outlined),
                            label: Text(venue.type == VenueType.salon
                                ? 'Add chair'
                                : 'Add court / table'),
                          ),
                          if (venue.type == VenueType.salon)
                            OutlinedButton.icon(
                              onPressed: () => onAddService(venue),
                              icon: const Icon(Icons.content_cut),
                              label: const Text('Add service'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              )),
        ],
      );
}

class _AdminManageWorkspace extends StatefulWidget {
  const _AdminManageWorkspace({
    required this.venues,
    required this.bookings,
    required this.onAddVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onDelete,
    required this.onRemoveItem,
    required this.onWalkIn,
    required this.onCancel,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final ValueChanged<Booking> onCancel;

  @override
  State<_AdminManageWorkspace> createState() => _AdminManageWorkspaceState();
}

class _AdminManageWorkspaceState extends State<_AdminManageWorkspace> {
  int _section = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Wrap(
              spacing: 8,
              children: [
                _CustomPill(
                  label: 'Manage venues',
                  icon: Icons.storefront_outlined,
                  selected: _section == 0,
                  onTap: () => setState(() => _section = 0),
                ),
                _CustomPill(
                  label: 'POS timeline',
                  icon: Icons.view_timeline_outlined,
                  selected: _section == 1,
                  onTap: () => setState(() => _section = 1),
                ),
              ],
            ),
          ),
          Expanded(
            child: _section == 0
                ? _ManageTab(
                    venues: widget.venues,
                    onAddVenue: widget.onAddVenue,
                    onAddItem: widget.onAddItem,
                    onAddService: widget.onAddService,
                    onDelete: widget.onDelete,
                    onRemoveItem: widget.onRemoveItem,
                  )
                : _PosTab(
                    venues: widget.venues,
                    bookings: widget.bookings,
                    onWalkIn: widget.onWalkIn,
                    onCancel: widget.onCancel,
                  ),
          ),
        ],
      );
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.enabled = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          color: enabled ? _panel : _page,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: enabled ? _green.withValues(alpha: .24) : _border,
          ),
        ),
        child: ListTile(
          onTap: enabled ? onTap : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          leading: Icon(
            icon,
            color: enabled ? _green : const Color(0xFFA1A1AA),
          ),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: enabled
              ? const Icon(Icons.arrow_forward_rounded, color: _green)
              : const Text(
                  'SOON',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      );
}

class _PosTab extends StatelessWidget {
  const _PosTab({
    required this.venues,
    required this.bookings,
    required this.onWalkIn,
    required this.onCancel,
  });
  final List<Venue> venues;
  final List<Booking> bookings;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final ValueChanged<Booking> onCancel;

  @override
  Widget build(BuildContext context) {
    final active = bookings
        .where((booking) =>
            booking.blocksAvailability &&
            booking.endsAt.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _IntroCard(
          title: 'POS timeline',
          subtitle: 'Confirmed bookings and temporary unpaid holds.',
          icon: Icons.view_timeline_outlined,
          action: active.isEmpty
              ? null
              : Text('${active.length} active',
                  style: const TextStyle(
                      color: _green, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 14),
        if (venues.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Walk-in customer',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...venues.expand((venue) => venue.items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${venue.name} · ${item.name}'),
                          subtitle: Text(item.kind),
                          trailing: IconButton.filledTonal(
                            tooltip: 'Add walk-in',
                            onPressed: () => onWalkIn(venue, item),
                            icon: const Icon(Icons.person_add_alt_1),
                          ),
                        ),
                      )),
                  if (venues.every((venue) => venue.items.isEmpty))
                    const Text('Add bookable spaces in Manage venues.'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        if (active.isEmpty)
          const _EmptyCard(
            icon: Icons.event_note_outlined,
            title: 'No active bookings',
            body: 'New customer and walk-in bookings appear here.',
          ),
        ...active.map((booking) {
          final venue = venues.where((value) => value.id == booking.venueId);
          final item = venue.isEmpty
              ? null
              : venue.first.items
                  .where((value) => value.id == booking.itemId)
                  .firstOrNull;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: const _IconBox(icon: Icons.event_available),
              title: Text(booking.customer,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${venue.isEmpty ? 'Venue' : venue.first.name} · ${item?.name ?? 'Resource'}\n'
                '${_dateTime(booking.startsAt)} – ${TimeOfDay.fromDateTime(booking.endsAt).format(context)} · '
                '${booking.durationMinutes} min'
                '${booking.serviceNames.isEmpty ? '' : '\n${booking.serviceNames.join(' + ')}'}'
                '${booking.splitCount > 1 ? '\n${booking.splitCount}-way · ${_money(booking.price / booking.splitCount)} EGP each' : ''}'
                '${booking.isPendingPayment ? '\nAwaiting deposit · not confirmed' : '\nConfirmed by venue'}',
              ),
              isThreeLine: true,
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_money(booking.price)} EGP',
                      style: const TextStyle(
                          color: _green, fontWeight: FontWeight.bold)),
                  IconButton(
                    tooltip: 'Cancel booking',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onCancel(booking),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _PaymentTab extends StatelessWidget {
  const _PaymentTab({required this.apiConfigured, required this.localPreview});

  final bool apiConfigured;
  final bool localPreview;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const _IntroCard(
            title: 'Payments & deposits',
            subtitle:
                'Payment credentials belong on the trusted Hagzy server, never in this app.',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 12),
          if (!apiConfigured || localPreview) const _LocalPreviewNotice(),
          if (apiConfigured && !localPreview)
            const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_done_outlined, color: _green),
                title: Text('Backend connected'),
                subtitle: Text(
                    'Configure payment provider keys as server environment variables before enabling checkout.'),
              ),
            ),
          const SizedBox(height: 12),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Paymob',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                      'The API can create a Paymob intention through the backend. Set PAYMOB_SECRET_KEY, PAYMOB_PUBLIC_KEY, and PAYMOB_INTEGRATION_ID on the server. A checkout is not marked paid until a verified provider callback is implemented.',
                      style: TextStyle(color: _muted)),
                ],
              ),
            ),
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fawry',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                      'Fawry checkout is not connected to the shared backend yet. Do not treat a signed reference or customer screenshot as confirmed payment.',
                      style: TextStyle(color: _muted)),
                ],
              ),
            ),
          ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('InstaPay',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                      'InstaPay transfers require manual instructions and verification. Do not store your IPA or mark a booking paid based only on a transfer claim.',
                      style: TextStyle(color: _muted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Reservations remain unpaid/pending until a trusted provider confirmation updates their status.',
              style: TextStyle(color: _muted, fontSize: 12)),
        ],
      );
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
        color: _panel,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _IconBox(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            color: _ink,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: _muted)),
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: 8),
                action!,
              ],
            ],
          ),
        ),
      );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(icon, size: 38, color: _green),
              const SizedBox(height: 10),
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted)),
              if (action != null) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: action,
                    icon: const Icon(Icons.add),
                    label:
                        Text(actionLabel ?? 'Add New Venue / Pitch / Barber'),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _HagzyLogoMark extends StatelessWidget {
  const _HagzyLogoMark({this.size = 40, this.withGlow = false});

  final double size;
  final bool withGlow;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _HagzyLogoPainter()),
    );
    if (!withGlow) return mark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF059669).withValues(alpha: 0.25),
            blurRadius: size * 0.25,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: mark,
    );
  }
}

class _HagzyLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 40;
    final paint = Paint()..isAntiAlias = true;
    final rect = Offset.zero & size;

    // 1. Sleek squircle background with rich emerald gradient
    paint.shader = const LinearGradient(
      colors: [Color(0xFF047857), Color(0xFF059669)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ).createShader(rect);

    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(11 * scale));
    canvas.drawRRect(rrect, paint);

    // 2. Subtle specular inner rim border
    paint
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8 * scale
      ..color = Colors.white.withValues(alpha: 0.22);
    canvas.drawRRect(rrect, paint);

    // 3. Bold, bespoke architectural "H" monogram with dynamic stadium arch
    final glyphPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.8 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white;

    // Left vertical pillar
    canvas.drawLine(
      Offset(12.5 * scale, 11 * scale),
      Offset(12.5 * scale, 29 * scale),
      glyphPaint,
    );

    // Right vertical pillar
    canvas.drawLine(
      Offset(27.5 * scale, 11 * scale),
      Offset(27.5 * scale, 29 * scale),
      glyphPaint,
    );

    // Dynamic architectural stadium arch bridge
    final archPath = Path()
      ..moveTo(12.5 * scale, 21 * scale)
      ..quadraticBezierTo(
        20 * scale,
        14.5 * scale,
        27.5 * scale,
        21 * scale,
      );
    canvas.drawPath(archPath, glyphPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HagzySplashOverlay extends StatefulWidget {
  const _HagzySplashOverlay({
    required this.arabic,
    required this.onDismiss,
  });

  final bool arabic;
  final VoidCallback onDismiss;

  @override
  State<_HagzySplashOverlay> createState() => _HagzySplashOverlayState();
}

class _HagzySplashOverlayState extends State<_HagzySplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _exitFadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2100),
    );

    // Sleek subtle cinematic scale
    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    // Subtle upward drift into place
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.04),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutCubic),
      ),
    );

    // Silky fade-in
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.25, curve: Curves.easeOut),
    );

    // Smooth exit dissolve
    _exitFadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.85, 1.0, curve: Curves.easeInOutCubic),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDismiss();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismissNow() {
    if (_controller.isAnimating) {
      _controller.stop();
    }
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: _dismissNow,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final opacity =
                (_fadeAnimation.value * (1.0 - _exitFadeAnimation.value))
                    .clamp(0.0, 1.0);
            return Opacity(
              opacity: opacity,
              child: child,
            );
          },
          child: Material(
            color: Colors.transparent,
            child: SizedBox.expand(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF022C22), // Deep emerald night
                      Color(0xFF064E3B), // Core emerald
                      Color(0xFF0B1322), // Deep midnight slate
                    ],
                    stops: [0.0, 0.45, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        const Color(0xFF10B981)
                                            .withValues(alpha: 0.28),
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                                const _HagzyLogoMark(size: 88, withGlow: true),
                              ],
                            ),
                            const SizedBox(height: 26),
                            Text(
                              widget.arabic ? 'حجزي' : 'HAGZY',
                              style: TextStyle(
                                fontSize: widget.arabic ? 36 : 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: widget.arabic ? 1.0 : 5.0,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.arabic
                                  ? 'حجز فوري ومؤكد للملاعب والصالونات'
                                  : 'SPORTS · SALONS · SPACES',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: widget.arabic ? 13 : 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.72),
                                letterSpacing: widget.arabic ? 0.3 : 2.5,
                              ),
                            ),
                            const SizedBox(height: 38),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 140,
                                height: 2.5,
                                color: Colors.white.withValues(alpha: 0.12),
                                child: Align(
                                  alignment: widget.arabic
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: (_controller.value / 0.85)
                                        .clamp(0.0, 1.0),
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Color(0xFF34D399),
                                            Color(0xFF059669),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFE0F4E7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: _green),
      );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'This field is required' : null;

String? _positiveNumber(String? value) {
  final number = double.tryParse(value ?? '');
  return number == null || !number.isFinite || number <= 0
      ? 'Enter an amount greater than zero'
      : null;
}

String? _phoneValidator(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  return digits.length >= 7 ? null : 'Enter a valid phone number';
}

String _id() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(0x7fffffff)}';

String _money(double amount) => amount.toStringAsFixed(2);

String _dateTime(DateTime value) =>
    '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
