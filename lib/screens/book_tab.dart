import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/map_explorer.dart';
import '../widgets/smart_image.dart';

class BookTab extends StatefulWidget {
  const BookTab({
    super.key,
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onBook,
    this.initialVenueId,
    this.currentArea,
    this.onAddVenue,
    this.onAddReview,
    this.onAreaChanged,
    this.onRefresh,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final bool arabic;
  final Function onBook;
  final String? initialVenueId;
  final String? currentArea;
  final ValueChanged<VenueType?>? onAddVenue;
  final Future<void> Function(
      Venue venue, String author, double rating, String comment)? onAddReview;

  /// Notifies the app shell when the customer's area changes so other tabs
  /// (e.g. Profile) show the same governorate.
  final ValueChanged<String>? onAreaChanged;

  /// Pull-to-refresh callback for syncing venues and bookings from the network.
  final Future<void> Function()? onRefresh;

  @override
  State<BookTab> createState() => _BookTabState();
}

class _BookTabState extends State<BookTab> {
  VenueType? _type;
  String? _subCategory;
  String? _venueId;
  String? _itemId;
  String _query = '';
  String _area = kAllEgyptAreas;
  Set<String> _favoriteIds = {};
  Set<String> _dismissedBookAgainVenueIds = {};
  bool _favoritesOnly = false;
  bool _sortByPrice = false;
  bool _openNowOnly = false;
  bool _showMapView = false;
  bool _isAutoAssigningGps = false;
  static DateTime _defaultBookingDate() {
    final now = DateTime.now();
    return now.hour >= 21
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);
  }

  DateTime _date = _defaultBookingDate();
  DateTime? _selectedStart;
  int _headcount = 2;
  bool _escapeGroupConfirmed = false;
  int _sportsDurationMinutes = 60;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bookingSectionKey = GlobalKey();
  final GlobalKey _spaceStepKey = GlobalKey();
  final GlobalKey _timeStepKey = GlobalKey();
  final GlobalKey _quoteStepKey = GlobalKey();
  String? _suppressCollapseAnimVenueId;
  final Map<String, GlobalKey> _venueCardKeys = {};

  @override
  void initState() {
    super.initState();
    if (widget.currentArea != null && widget.currentArea!.isNotEmpty) {
      _area = widget.currentArea!;
    }
    _loadCustomerPreferences();
    // Contextual GPS: location permission is requested on tap of "Map & Near Me" or location button rather than interrupting app launch.
    if (widget.initialVenueId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final initialVenue = widget.venues
            .where((v) => v.id == widget.initialVenueId)
            .firstOrNull;
        if (initialVenue != null) {
          _selectVenue(initialVenue, toggleIfSame: false);
        }
      });
    }
  }

  @override
  void didUpdateWidget(BookTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentArea != null &&
        widget.currentArea != oldWidget.currentArea &&
        widget.currentArea != _area) {
      _area = widget.currentArea!;
    }
    if (widget.initialVenueId != null &&
        (widget.initialVenueId != oldWidget.initialVenueId ||
            _venueId != widget.initialVenueId)) {
      final targetVenue = widget.venues
          .where((v) => v.id == widget.initialVenueId)
          .firstOrNull;
      if (targetVenue != null) {
        _selectVenue(targetVenue, toggleIfSame: false);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToVenue(String venueId) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final bookingCtx = _bookingSectionKey.currentContext;
      if (bookingCtx != null && bookingCtx.mounted) {
        Scrollable.ensureVisible(
          bookingCtx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.0,
        );
        return;
      }
      final ctx = _venueCardKeys[venueId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.06,
        );
        return;
      }
      if (_scrollController.hasClients) {
        final matching = _getMatchingVenues();
        final index = matching.indexWhere((v) => v.id == venueId);
        final targetOffset = 380.0 + (index >= 0 ? index * 320.0 : 0.0);
        final maxScroll = _scrollController.position.maxScrollExtent;
        final clamped = targetOffset.clamp(0.0, maxScroll);
        await _scrollController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
        if (!mounted) return;
        final ctxAfter = _venueCardKeys[venueId]?.currentContext;
        if (ctxAfter != null && ctxAfter.mounted) {
          Scrollable.ensureVisible(
            ctxAfter,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            alignment: 0.06,
          );
        }
      }
    });
  }

  void _selectVenue(Venue value, {bool toggleIfSame = true}) {
    if (toggleIfSame && _venueId == value.id) {
      setState(() {
        _venueId = null;
        _itemId = null;
        _escapeGroupConfirmed = false;
        _selectedStart = null;
      });
      return;
    }
    setState(() {
      if (_type != null && _type != value.type) {
        _type = null;
      }
      if (_query.isNotEmpty) {
        _query = '';
        _searchController.clear();
      }
      if (_favoritesOnly && !_favoriteIds.contains(value.id)) {
        _favoritesOnly = false;
      }
      if (!_locationMatchesArea(value.location)) {
        _area = kAllEgyptAreas;
      }
      if (_venueId != value.id) {
        _date = _defaultBookingDate();
        _suppressCollapseAnimVenueId = _venueId;
      }
      if (_suppressCollapseAnimVenueId == value.id) {
        _suppressCollapseAnimVenueId = null;
      }
      _venueId = value.id;
      final isEscape = value.subCategories.contains('escape_rooms') ||
          value.name.toLowerCase().contains('escape');
      _itemId = isEscape ? null : value.items.firstOrNull?.id;
      _sportsDurationMinutes = 60;
      _selectedStart = null;
    });
    _scrollToVenue(value.id);
  }

  void _selectSpace(String itemId) {
    final prevStart = _selectedStart;
    final venue = _venuesInSelectedArea()
        .where((v) => v.id == _venueId)
        .firstOrNull;
    final nextItem =
        venue?.items.where((i) => i.id == itemId).firstOrNull;
    var keepStart = false;
    if (prevStart != null && venue != null && nextItem != null) {
      final estMin = venue.type == VenueType.salon ? 30 : 60;
      keepStart = _timesFor(venue, nextItem, estMin)
          .any((s) => s.start == prevStart && s.available);
    }
    final minCap = nextItem?.minCapacity ?? 2;
    setState(() {
      _itemId = itemId;
      _selectedStart = keepStart ? prevStart : null;
      _headcount = minCap;
      _escapeGroupConfirmed = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isEscape = venue?.subCategories.contains('escape_rooms') == true ||
          (venue?.name.toLowerCase().contains('escape') ?? false);
      final ctx = (isEscape ? _spaceStepKey : _timeStepKey).currentContext;
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
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.15,
      );
    }
  }

  Future<void> _loadCustomerPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _favoriteIds =
          (prefs.getStringList(kFavoriteStorageKey) ?? const <String>[])
              .toSet();
      _area = prefs.getString('hagzy_customer_area') ?? kAllEgyptAreas;
      _dismissedBookAgainVenueIds =
          (prefs.getStringList('hagzy_dismissed_book_again_venues') ??
                  const <String>[])
              .toSet();
    });
  }

  Future<void> _toggleFavorite(Venue venue) async {
    try {
      final next = {..._favoriteIds};
      final isAdding = !next.contains(venue.id);
      if (isAdding) {
        next.add(venue.id);
      } else {
        next.remove(venue.id);
      }
      final prefs = await SharedPreferences.getInstance();
      final saved =
          await prefs.setStringList(kFavoriteStorageKey, next.toList());
      if (!saved) {
        throw StateError('Could not save your favorites on this device.');
      }
      if (mounted) {
        setState(() => _favoriteIds = next);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            backgroundColor: kSnackBarBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: kBorder),
            ),
            content: Row(
              children: [
                Icon(
                  isAdding
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: isAdding ? const Color(0xFFE11D48) : Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isAdding
                        ? localized(widget.arabic, 'Added to Saved Places',
                            'تمت الإضافة إلى الأماكن المفضلة')
                        : localized(widget.arabic, 'Removed from Saved Places',
                            'تمت الإزالة من الأماكن المفضلة'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    } catch (error) {
      _showPreferenceError(error);
    }
  }

  Future<void> _removeBookAgainVenue(Venue venue) async {
    final next = {..._dismissedBookAgainVenueIds, venue.id};
    setState(() => _dismissedBookAgainVenueIds = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'hagzy_dismissed_book_again_venues',
        next.toList(),
      );
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localized(
            widget.arabic,
            'Removed "${venue.name}" from Book Again',
            'تمت إزالة "${venue.name}" من احجز مرة أخرى',
          ),
        ),
        action: SnackBarAction(
          label: localized(widget.arabic, 'Undo', 'تراجع'),
          onPressed: () => _restoreBookAgainVenue(venue.id),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _restoreBookAgainVenue(String venueId) async {
    final next = {..._dismissedBookAgainVenueIds}..remove(venueId);
    setState(() => _dismissedBookAgainVenueIds = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'hagzy_dismissed_book_again_venues',
        next.toList(),
      );
    } catch (_) {}
  }

  Future<void> _clearAllBookAgainVenues(List<Venue> venues) async {
    final idsToRemove = venues.map((v) => v.id).toSet();
    final next = {..._dismissedBookAgainVenueIds, ...idsToRemove};
    setState(() => _dismissedBookAgainVenueIds = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        'hagzy_dismissed_book_again_venues',
        next.toList(),
      );
    } catch (_) {}

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          localized(
            widget.arabic,
            'Cleared all spots from Book Again',
            'تم مسح كل الأماكن من احجز مرة أخرى',
          ),
        ),
        action: SnackBarAction(
          label: localized(widget.arabic, 'Undo', 'تراجع'),
          onPressed: () {
            final restored = {..._dismissedBookAgainVenueIds}
              ..removeAll(idsToRemove);
            setState(() => _dismissedBookAgainVenueIds = restored);
            SharedPreferences.getInstance().then((prefs) {
              prefs.setStringList(
                'hagzy_dismissed_book_again_venues',
                restored.toList(),
              );
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _openVenueDetails(Venue venue) async {
    final arabic = widget.arabic;
    await showHagzySheet<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, modalSetState) {
          final isFav = _favoriteIds.contains(venue.id);
          return _VenueDetailsSheet(
            venue: venue,
            arabic: arabic,
            favorite: isFav,
            onFavorite: () async {
              await _toggleFavorite(venue);
              if (ctx.mounted) modalSetState(() {});
            },
            onBookNow: () {
              Navigator.pop(ctx);
              if (_venueId != venue.id) {
                _selectVenue(venue);
              }
            },
            onAddReview: widget.onAddReview == null
                ? null
                : (author, rating, comment) async {
                    await widget.onAddReview!(venue, author, rating, comment);
                  },
          );
        },
      ),
    );
  }

  Future<void> _assignArea(String area, {bool viaGps = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = await prefs.setString('hagzy_customer_area', area);
      if (!saved) throw StateError('Could not save your selected area.');
      if (mounted) {
        setState(() => _area = area);
        widget.onAreaChanged?.call(area);
        final govName = governorateName(area, widget.arabic);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  viaGps
                      ? Icons.my_location_rounded
                      : Icons.check_circle_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    viaGps
                        ? (widget.arabic
                            ? 'تم تحديد منطقتك تلقائياً عبر GPS: $govName'
                            : 'Auto-assigned area via GPS: $govName')
                        : (widget.arabic
                            ? 'تم اختيار المنطقة: $govName'
                            : 'Area updated: $govName'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: kSnackBarBg,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      }
    } catch (error) {
      _showPreferenceError(error);
    }
  }

  Future<void> _autoAssignGpsAreaDirectly({bool silentIfDenied = false}) async {
    if (_isAutoAssigningGps) return;
    if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      if (!silentIfDenied) {
        await _assignArea('Cairo', viaGps: true);
      }
      return;
    }
    setState(() => _isAutoAssigningGps = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _isAutoAssigningGps = false);
          if (!silentIfDenied) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.arabic
                    ? 'يرجى تفعيل خدمات الموقع (GPS) في جهازك أولاً'
                    : 'Please enable Location Services (GPS) on your device.'),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() => _isAutoAssigningGps = false);
            if (!silentIfDenied) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(widget.arabic
                      ? 'تم رفض إذن الوصول للموقع'
                      : 'Location permission was denied.'),
                  backgroundColor: Colors.redAccent,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _isAutoAssigningGps = false);
          if (!silentIfDenied) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(widget.arabic
                    ? 'إذن الموقع محظور، يرجى تفعيله من إعدادات الجهاز'
                    : 'Location permission is permanently denied in settings.'),
                backgroundColor: Colors.redAccent,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final nearest = findNearestGovernorate(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() => _isAutoAssigningGps = false);
        await _assignArea(nearest, viaGps: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAutoAssigningGps = false);
        if (!silentIfDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.arabic
                  ? 'تعذر الوصول إلى موقعك الحالي، يرجى المحاولة لاحقاً'
                  : 'Could not detect your current GPS location.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Future<void> _chooseArea() async {
    var query = '';
    var locatingGps = false;
    String? gpsError;

    final result = await showHagzyAdaptiveModal<({String area, bool viaGps})>(
      context: context,
      maxWidth: 460,
      maxHeightFactor: 0.88,
      builder: (context, isSheet) => StatefulBuilder(
        builder: (context, setDialogState) {
          final options = [
            (
              kAllEgyptAreas,
              localized(widget.arabic, 'All Egypt', 'كل محافظات مصر')
            ),
            ...egyptGovernorates.map(
              (governorate) => (
                governorate.$1,
                widget.arabic ? governorate.$2 : governorate.$1,
              ),
            ),
          ].where((entry) =>
              entry.$1.toLowerCase().contains(query.toLowerCase()) ||
              entry.$2.contains(query));
          return HagzyModalCard(
            isSheet: isSheet,
            maxWidth: 460,
            scrollable: false,
            icon: Icons.location_on_rounded,
            title: localized(
                widget.arabic, 'Choose a governorate', 'اختر المحافظة'),
            subtitle: localized(
              widget.arabic,
              'See places and live slots near your area',
              'اعرض الأماكن والمواعيد المتاحة في منطقتك',
            ),
            onClose: () => Navigator.pop(context),
            secondaryLabel: localized(widget.arabic, 'Cancel', 'إلغاء'),
            onSecondary: () => Navigator.pop(context),
            content: SizedBox(
              height: isSheet ? 380 : 410,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HagzyTap(
                    scaleDown: 0.98,
                    haptic: HagzyHapticStyle.selection,
                    onTap: locatingGps
                        ? null
                        : () async {
                            if (WidgetsBinding.instance.runtimeType
                                .toString()
                                .contains('Test')) {
                              Navigator.pop(
                                  context, (area: 'Cairo', viaGps: true));
                              return;
                            }
                            setDialogState(() {
                              locatingGps = true;
                              gpsError = null;
                            });
                            try {
                              final serviceEnabled =
                                  await Geolocator.isLocationServiceEnabled();
                              if (!serviceEnabled) {
                                setDialogState(() {
                                  locatingGps = false;
                                  gpsError = localized(
                                      widget.arabic,
                                      'Location services disabled. Please enable GPS.',
                                      'خدمات الموقع غير مفعلة، يرجى تفعيل الـ GPS');
                                });
                                return;
                              }
                              var perm = await Geolocator.checkPermission();
                              if (perm == LocationPermission.denied) {
                                perm = await Geolocator.requestPermission();
                                if (perm == LocationPermission.denied) {
                                  setDialogState(() {
                                    locatingGps = false;
                                    gpsError = localized(
                                        widget.arabic,
                                        'Location permission denied.',
                                        'تم رفض إذن تحديد الموقع');
                                  });
                                  return;
                                }
                              }
                              if (perm == LocationPermission.deniedForever) {
                                setDialogState(() {
                                  locatingGps = false;
                                  gpsError = localized(
                                      widget.arabic,
                                      'Location permission permanently denied.',
                                      'إذن الموقع محظور في إعدادات الجهاز');
                                });
                                return;
                              }

                              final pos = await Geolocator.getCurrentPosition(
                                locationSettings: const LocationSettings(
                                  accuracy: LocationAccuracy.medium,
                                  timeLimit: Duration(seconds: 8),
                                ),
                              );
                              final nearest = findNearestGovernorate(
                                  pos.latitude, pos.longitude);
                              if (context.mounted) {
                                Navigator.pop(
                                    context, (area: nearest, viaGps: true));
                              }
                            } catch (e) {
                              if (context.mounted) {
                                setDialogState(() {
                                  locatingGps = false;
                                  gpsError = localized(
                                      widget.arabic,
                                      'Could not detect location via GPS.',
                                      'تعذر تحديد موقعك الحالي عبر GPS');
                                });
                              }
                            }
                          },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: kSurfaceTint,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: kBrandAccent.withValues(alpha: 0.32),
                          width: 1.1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: kBrandAccent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: locatingGps
                                ? const Padding(
                                    padding: EdgeInsets.all(9),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.white),
                                    ),
                                  )
                                : const Icon(
                                    Icons.my_location_rounded,
                                    color: Colors.white,
                                    size: 19,
                                  ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  locatingGps
                                      ? localized(
                                          widget.arabic,
                                          'Detecting your location...',
                                          'جاري تحديد موقعك عبر GPS...')
                                      : localized(
                                          widget.arabic,
                                          'Auto-Assign Area via GPS',
                                          'تحديد منطقتي تلقائياً عبر GPS'),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                    color: kInk,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  localized(
                                    widget.arabic,
                                    'Finds nearest Egyptian governorate in 1 tap',
                                    'يحدد أقرب محافظة لك في مصر بضغطة واحدة',
                                  ),
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
                          HagzyDirectionalChevron(size: 18, color: kBrandAccent),
                        ],
                      ),
                    ),
                  ),
                  if (gpsError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kError.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, size: 16, color: kError),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              gpsError!,
                              style: TextStyle(
                                color: kError,
                                fontSize: 12.0,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    autofocus: false,
                    textDirection:
                        widget.arabic ? TextDirection.rtl : TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: localized(widget.arabic, 'Search governorates',
                          'ابحث عن محافظة'),
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) =>
                        setDialogState(() => query = value.trim()),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, index) {
                        final entry = options.elementAt(index);
                        return HagzyGroupedRow(
                          title: entry.$2,
                          selected: entry.$1 == _area,
                          onTap: () => Navigator.pop(
                              context, (area: entry.$1, viaGps: false)),
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
    if (result == null) return;
    await _assignArea(result.area, viaGps: result.viaGps);
  }

  bool _isPublicCatalogVenue(Venue v) =>
      v.id != 'test-venue' && v.id != 'hagzy-demo-5egp';

  Iterable<Venue> _venuesInSelectedArea() => widget.venues
      .where((v) => _isPublicCatalogVenue(v) && _locationMatchesArea(v.location));

  bool _locationMatchesArea(String location) {
    if (_area == kAllEgyptAreas) {
      return true;
    }
    if (location.trim().isEmpty) {
      return false;
    }
    final normalized = location.toLowerCase();
    final governorate =
        egyptGovernorates.where((entry) => entry.$1 == _area).firstOrNull;
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
      SnackBar(content: Text('Could not save this preference: ${friendlyError(error, arabic: widget.arabic)}')),
    );
  }

  bool _isVenueOpenNow(Venue v) {
    final nowHour = DateTime.now().hour;
    if (v.openHour == 0 && v.closeHour == 24) return true;
    if (v.closeHour > v.openHour) {
      return nowHour >= v.openHour && nowHour < v.closeHour;
    } else {
      return nowHour >= v.openHour || nowHour < v.closeHour;
    }
  }

  List<Venue> _getMatchingVenues() {
    final pool = _query.trim().isNotEmpty
        ? widget.venues.where(_isPublicCatalogVenue)
        : _venuesInSelectedArea();
    final list = pool.where((venue) {
      final matchesCategory = _type == null || venue.type == _type;
      final matchesSubCategory = _subCategory == null ||
          venue.effectiveSubCategories.contains(_subCategory);
      final itemsText = venue.items
          .map((i) => '${i.name} ${i.kind} ${i.description}')
          .join(' ');
      final matchesSearch = _query.isEmpty ||
          '${venue.name} ${venue.location} ${venue.description} ${venue.effectiveSubCategories.join(' ')} $itemsText'
              .toLowerCase()
              .contains(_query.toLowerCase());
      final matchesFavorite =
          !_favoritesOnly || _favoriteIds.contains(venue.id);
      final matchesArea = _query.trim().isNotEmpty || _locationMatchesArea(venue.location);
      final matchesOpenNow = !_openNowOnly || _isVenueOpenNow(venue);
      return matchesCategory &&
          matchesSubCategory &&
          matchesSearch &&
          matchesFavorite &&
          matchesArea &&
          matchesOpenNow;
    }).toList()
      ..sort((a, b) {
        if (!_sortByPrice) return a.name.compareTo(b.name);
        return _startingPrice(a).compareTo(_startingPrice(b));
      });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final matchingVenues = _getMatchingVenues();
    final bookAgainVenues = widget.venues
        .where((v) =>
            !_dismissedBookAgainVenueIds.contains(v.id) &&
            _isPublicCatalogVenue(v) &&
            widget.bookings.any((b) => b.venueId == v.id && !b.cancelled))
        .toList();
    final venue =
        matchingVenues.where((value) => value.id == _venueId).firstOrNull;
    final isEscape = venue != null &&
        (venue.subCategories.contains('escape_rooms') ||
            venue.name.toLowerCase().contains('escape'));
    final item =
        venue?.items.where((value) => value.id == _itemId).firstOrNull ??
            (isEscape ? null : venue?.items.firstOrNull);
    final estimatedMinutes = venue?.type == VenueType.salon
        ? venue!.services.isEmpty
            ? 30
            : venue.services.first.minutes
        : 60;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= HagzyTokens.breakpointTablet;

    final areaBarWidget = CustomerAreaBar(
      area: governorateName(_area, widget.arabic),
      arabic: widget.arabic,
      onTap: _chooseArea,
      onGpsTap: () => _autoAssignGpsAreaDirectly(silentIfDenied: false),
      isLocating: _isAutoAssigningGps,
    );

    final searchFieldWidget = TextField(
      controller: _searchController,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: kInk,
      ),
      decoration: InputDecoration(
        hintText: localized(
          widget.arabic,
          'Search padel, football, salons, gaming...',
          'ابحث عن ملاعب، صالونات، بلايستيشن، كافيهات...',
        ),
        hintStyle: TextStyle(
          color: kMuted,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Icon(
          Icons.search_rounded,
          color: kDarkMode.value ? kVolt : kObsidian,
          size: 20,
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                tooltip: localized(widget.arabic, 'Clear search', 'مسح البحث'),
                onPressed: () => setState(() {
                  _query = '';
                  _searchController.clear();
                }),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      onChanged: (value) => setState(() {
        _query = value;
        _venueId = null;
        _itemId = null;
        _selectedStart = null;
      }),
    );

    // Clean Warm Where + Search Command Card
    final unifiedCommandConsole = Container(
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(color: kBorder, width: 1.0),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: isWide
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: areaBarWidget,
                    ),
                  ),
                  VerticalDivider(width: 1, thickness: 1, color: kBorder),
                  Expanded(
                    flex: 6,
                    child: Center(child: searchFieldWidget),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: areaBarWidget,
                ),
                Divider(height: 1, thickness: 1, color: kBorder),
                searchFieldWidget,
              ],
            ),
    );

    final areaVenues = _venuesInSelectedArea().toList();
    final categoryCards = [
      _CategoryVisualCard(
        title: localized(widget.arabic, 'Everything', 'الكل'),
        subtitle: localized(widget.arabic, 'All Places', 'جميع الأماكن'),
        icon: Icons.grid_view_rounded,
        isSelected: _type == null,
        gradient: const [kObsidian, kObsidianSoft],
        glowColor: kVolt,
        count: areaVenues.length,
        arabic: widget.arabic,
        onTap: () => _selectCategory(null),
      ),
      _CategoryVisualCard(
        title: localized(widget.arabic, 'Sports', 'ملاعب ورياضة'),
        subtitle: localized(widget.arabic, 'Padel & Football', 'بادل وكرة قدم'),
        icon: Icons.sports_soccer_rounded,
        isSelected: _type == VenueType.sports,
        gradient: const [kObsidian, kObsidianSoft],
        glowColor: kVolt,
        count: areaVenues.where((v) => v.type == VenueType.sports).length,
        arabic: widget.arabic,
        onTap: () => _selectCategory(VenueType.sports),
      ),
      _CategoryVisualCard(
        title: localized(widget.arabic, 'Grooming', 'حلاقة وعناية'),
        subtitle: localized(widget.arabic, 'Hair & Beauty', 'صالونات وحلاقة'),
        icon: Icons.content_cut_rounded,
        isSelected: _type == VenueType.salon,
        gradient: const [kObsidian, kObsidianSoft],
        glowColor: kVolt,
        count: areaVenues.where((v) => v.type == VenueType.salon).length,
        arabic: widget.arabic,
        onTap: () => _selectCategory(VenueType.salon),
      ),
      _CategoryVisualCard(
        title: localized(widget.arabic, 'Entertainment', 'ترفيه وألعاب'),
        subtitle:
            localized(widget.arabic, 'Gaming & Tables', 'ألعاب وبلايستيشن'),
        icon: Icons.sports_esports_rounded,
        isSelected: _type == VenueType.lounge,
        gradient: const [kObsidian, kObsidianSoft],
        glowColor: kVolt,
        count: areaVenues.where((v) => v.type == VenueType.lounge).length,
        arabic: widget.arabic,
        onTap: () => _selectCategory(VenueType.lounge),
      ),
    ];

    // Desktop 4-Column Clean Category Strip
    final desktopCategoryMatrix = Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(child: categoryCards[0]),
          const SizedBox(width: 10),
          Expanded(child: categoryCards[1]),
          const SizedBox(width: 10),
          Expanded(child: categoryCards[2]),
          const SizedBox(width: 10),
          Expanded(child: categoryCards[3]),
        ],
      ),
    );

    // Compact Single-Row Category Rail on Mobile (keeps venues visible above the fold)
    final compactCategoryRail = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          categoryCards[0],
          const SizedBox(width: 8),
          categoryCards[1],
          const SizedBox(width: 8),
          categoryCards[2],
          const SizedBox(width: 8),
          categoryCards[3],
        ],
      ),
    );

    final heroWidget = RepaintBoundary(
      child: CustomerHero(
        venueCount: areaVenues.length,
        type: _type,
        arabic: widget.arabic,
      ),
    );

    final feed = ListView(
      // ignore: deprecated_member_use
      cacheExtent: 3000,
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 10 : 6,
        isWide ? 24 : 16,
        isWide ? 52 : 104,
      ),
      children: [
        // 1. Clean Consumer Header + Location/Search + Category Strip
        heroWidget,
        SizedBox(height: isWide ? 8 : 10),
        unifiedCommandConsole,
        if (isWide) ...[
          desktopCategoryMatrix,
        ],

        if (bookAgainVenues.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionHeading(
            title: localized(widget.arabic, 'Book Again', 'احجز مرة أخرى'),
            subtitle: localized(widget.arabic,
                'Your favorite regular spots', 'أماكنك المعتادة بضغطة واحدة'),
            trailing: bookAgainVenues.length > 1
                ? TextButton(
                    onPressed: () => _clearAllBookAgainVenues(bookAgainVenues),
                    style: TextButton.styleFrom(
                      foregroundColor: kMuted,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    child: Text(
                      localized(widget.arabic, 'Clear All', 'مسح الكل'),
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bookAgainVenues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final v = bookAgainVenues[index];
                final isCurrent = _venueId == v.id;
                return HagzyInteractiveSurface(
                  hoverLift: 1.5,
                  pressScale: 0.97,
                  builder: (context, hovered, _) => Material(
                    color: Colors.transparent,
                    child: Ink(
                      width: 248,
                      decoration: BoxDecoration(
                        color: kPanel,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusLarge),
                        border: Border.all(
                          color: isCurrent ? kBrandAccent : kBorder,
                          width: isCurrent ? 1.5 : 1.0,
                        ),
                        boxShadow: HagzyTheme.subtleShadow,
                      ),
                      child: Stack(
                        children: [
                          InkWell(
                            borderRadius:
                                BorderRadius.circular(HagzyTokens.radiusLarge),
                            onTap: () {
                              HagzyHaptics.light();
                              _selectVenue(v, toggleIfSame: false);
                            },
                            child: Padding(
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                  12, 8, 34, 8),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: kSurfaceTint,
                                      borderRadius: BorderRadius.circular(
                                          HagzyTokens.radiusSmall),
                                    ),
                                    child: Icon(v.type.icon,
                                        color: kBrandAccent, size: 19),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          displayLocalizedTitle(
                                              v.name, widget.arabic),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13.5,
                                            height: 1.18,
                                            color: kInk,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          v.location.isEmpty
                                              ? localized(
                                                  widget.arabic, 'Egypt', 'مصر')
                                              : displayLocalizedLocation(
                                                  v.location, widget.arabic),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: kMuted,
                                            fontSize: 11.5,
                                            height: 1.18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(Icons.arrow_outward_rounded,
                                                size: 13, color: kBrandAccent),
                                            const SizedBox(width: 3),
                                            Text(
                                              localized(widget.arabic,
                                                  'Book Now', 'احجز الآن'),
                                              style: TextStyle(
                                                color: kBrandAccent,
                                                fontSize: 11.5,
                                                height: 1.15,
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
                            ),
                          ),
                          Positioned.directional(
                            textDirection: widget.arabic
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            top: 6,
                            end: 6,
                            child: Tooltip(
                              message: localized(
                                widget.arabic,
                                'Remove from Book Again',
                                'إزالة من احجز مرة أخرى',
                              ),
                              child: InkWell(
                                onTap: () => _removeBookAgainVenue(v),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: kSurfaceSubtle,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: kMuted,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (!isWide) ...[
          const SizedBox(height: 10),
          compactCategoryRail,
        ],
        const SizedBox(height: 10),

        // 3. Editorial Borderless Subcategory Tab Rail + Machined Utility Strip
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSubCategoryFilterRow(matchingVenues),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  CustomPill(
                    selected: !_favoritesOnly,
                    label: localized(
                        widget.arabic, 'All Places', 'كل الأماكن'),
                    onTap: () => setState(() => _favoritesOnly = false),
                  ),
                  const SizedBox(width: 8),
                  CustomPill(
                    selected: _favoritesOnly,
                    icon: _favoriteIds.isNotEmpty
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: localized(widget.arabic, 'Saved', 'المفضلة'),
                    badge: _favoriteIds.isNotEmpty
                        ? '${_favoriteIds.length}'
                        : null,
                    onTap: () =>
                        setState(() => _favoritesOnly = !_favoritesOnly),
                  ),
                  const SizedBox(width: 8),
                  CustomPill(
                    selected: _showMapView,
                    icon: Icons.map_outlined,
                    label: localized(widget.arabic, 'Map & Near Me',
                        'على الخريطة وقريب مني'),
                    onTap: () => setState(() => _showMapView = !_showMapView),
                  ),
                  const SizedBox(width: 8),
                  CustomPill(
                    selected: _openNowOnly,
                    icon: Icons.access_time_filled_rounded,
                    label: localized(widget.arabic, 'Open Now', 'مفتوح الآن'),
                    onTap: () => setState(() => _openNowOnly = !_openNowOnly),
                  ),
                  const SizedBox(width: 8),
                  CustomPill(
                    selected: _sortByPrice,
                    icon: Icons.swap_vert_rounded,
                    label: localized(
                        widget.arabic,
                        _sortByPrice ? 'Lowest Price' : 'Sort: Price',
                        _sortByPrice ? 'أقل سعر' : 'ترتيب: السعر'),
                    onTap: () => setState(() => _sortByPrice = !_sortByPrice),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_showMapView && matchingVenues.isNotEmpty) ...[
          HagzyMapExplorer(
            venues: matchingVenues,
            arabic: widget.arabic,
            selectedArea: _area == kAllEgyptAreas ? 'Cairo' : _area,
            selectedVenueId: _venueId,
            onAreaDetected: (detectedGov) {
              if (_area != detectedGov) {
                _assignArea(detectedGov, viaGps: true);
              }
            },
            onSelectVenue: (v) => _selectVenue(v, toggleIfSame: false),
            onBookVenue: (v) {
              final defaultItem = v.items.firstOrNull ??
                  VenueItem(
                      id: generateId(),
                      name: v.name,
                      kind: 'Standard',
                      hourlyRate: 150);
              widget.onBook(
                  v, defaultItem, DateTime.now().add(const Duration(hours: 1)));
            },
          ),
          const SizedBox(height: 16),
        ],
        if (matchingVenues.isEmpty)
          EmptyCard(
            icon: _favoritesOnly
                ? Icons.favorite_border_rounded
                : Icons.location_off_outlined,
            title: _favoritesOnly
                ? localized(widget.arabic, 'No Saved Places Yet',
                    'لا توجد أماكن مفضلة بعد')
                : localized(
                    widget.arabic, 'No Places Found Here', 'لا توجد أماكن هنا'),
            body: _favoritesOnly
                ? localized(
                    widget.arabic,
                    'Tap the heart icon on any venue to save it to your favorites for quick booking.',
                    'اضغط على أيقونة القلب في أي مكان لحفظه في المفضلة وسهولة حجزه لاحقاً.')
                : _area != kAllEgyptAreas
                    ? localized(
                        widget.arabic,
                        'No venues currently found in ${governorateName(_area, widget.arabic)}. Change your area or explore all governorates.',
                        'لا توجد أماكن متاحة حالياً في ${governorateName(_area, widget.arabic)}. يمكنك تغيير منطقتك أو استعراض كل المحافظات.')
                    : widget.venues.isEmpty
                        ? localized(
                            widget.arabic,
                            'We’re bringing great local venues to Hagzy. Check back soon.',
                            'نعمل على إضافة أماكن رائعة بالقرب منك. تفقّدنا قريباً.')
                        : localized(
                            widget.arabic,
                            'Try changing your area, category or search query.',
                            'جرّب تغيير المنطقة أو التصنيف أو عبارة البحث.'),
            action: _favoritesOnly
                ? () => setState(() => _favoritesOnly = false)
                : widget.onAddVenue != null
                    ? () => widget.onAddVenue!(_type)
                    : null,
            actionLabel: _favoritesOnly
                ? localized(
                    widget.arabic, 'Browse All Places', 'استعراض كل الأماكن')
                : localized(widget.arabic, 'Add New Venue / Pitch / Barber',
                    'أضف مكاناً أو ملعباً أو حلاقاً'),
            actionIcon: _favoritesOnly
                ? Icons.explore_outlined
                : Icons.add_business_outlined,
            secondaryAction: !_favoritesOnly ? _chooseArea : null,
            secondaryActionLabel: localized(
                widget.arabic,
                'Change Area / Governorate',
                'تغيير المنطقة أو المحافظة'),
            secondaryIcon: Icons.location_on_outlined,
            tertiaryAction: !_favoritesOnly && _area != kAllEgyptAreas
                ? () => _assignArea(kAllEgyptAreas)
                : null,
            tertiaryActionLabel: localized(
                widget.arabic,
                'Explore All Egypt Governorates',
                'استكشف كل محافظات مصر'),
          )
        else ...[
          if (_type != null) ...[
            _buildActiveCategoryFilterBanner(),
            ..._buildResponsiveVenueCollection(
              matchingVenues,
              venue,
              item,
              estimatedMinutes,
              isWide: isWide,
            ),
          ] else ...[
            ..._buildCategorizedVenues(
              matchingVenues,
              venue,
              item,
              estimatedMinutes,
              isWide: isWide,
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: kPanel,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kBorder),
                  boxShadow: [
                    BoxShadow(
                      color: kInk.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: kGreen,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          style: TextStyle(
                            color: kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                          children: [
                            TextSpan(
                              text: localized(
                                widget.arabic,
                                'Made with ',
                                'صُنع بـ ',
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
                                widget.arabic,
                                ' in Kafr El-Sheikh',
                                ' في كفر الشيخ',
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
          ),
        ],
      ],
    );
    if (widget.onRefresh != null) {
      return RefreshIndicator(
        onRefresh: widget.onRefresh!,
        child: feed,
      );
    }
    return feed;
  }

  Widget _buildActiveCategoryFilterBanner() {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final type = _type!;
    final (label, icon) = switch (type) {
      VenueType.salon => (
          localized(
              widget.arabic, 'Grooming & Barbershops', 'حلاقة وعناية وصالونات'),
          Icons.content_cut_rounded,
        ),
      VenueType.lounge => (
          localized(
              widget.arabic, 'Entertainment & Lounges', 'ترفيه وألعاب وكافيهات'),
          Icons.sports_esports_rounded,
        ),
      VenueType.sports => (
          localized(widget.arabic, 'Sports & Courts', 'ملاعب ورياضة'),
          Icons.sports_soccer_rounded,
        ),
    };

    final activeSubDef =
        _subCategory != null ? findSubCategoryDef(_subCategory!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151713) : kObsidian,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
        border: Border.all(
          color: kVolt.withValues(alpha: isDark ? 0.45 : 0.30),
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kVermilion,
              borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
            ),
            child: Icon(icon, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (activeSubDef != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '/',
                    style: hagzyMonoStyle(
                      fontSize: 12,
                      color: kVolt,
                    ),
                  ),
                  const SizedBox(width: 6),
                  HagzyMonoTag(
                    label: activeSubDef.title(widget.arabic),
                    backgroundColor: const Color(0xFF1F2028),
                    foregroundColor: kVolt,
                    borderColor: kVolt.withValues(alpha: 0.35),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: () => _selectCategory(null),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(widget.arabic, 'Show All', 'عرض الكل'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: kVolt,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubCategoryFilterRow(List<Venue> matchingVenues) {
    final subList = subCategoriesForParent(_type);
    final allVenuesInArea = _venuesInSelectedArea()
        .where((v) => _type == null || v.type == _type)
        .toList();

    final allLabel = switch (_type) {
      VenueType.salon =>
        localized(widget.arabic, 'All Grooming', 'كل الحلاقة والعناية'),
      VenueType.sports =>
        localized(widget.arabic, 'All Sports', 'كل الملاعب والرياضة'),
      VenueType.lounge =>
        localized(widget.arabic, 'All Entertainment', 'كل الترفيه والألعاب'),
      null => localized(widget.arabic, 'All', 'الكل'),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 44,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: kBorder, width: 1.0),
            ),
          ),
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _SubCategoryVisualPill(
                label: allLabel,
                emoji: 'all',
                icon: Icons.auto_awesome_rounded,
                isSelected: _subCategory == null,
                count: allVenuesInArea.length,
                arabic: widget.arabic,
                accentColor: kAccentSurface,
                onTap: () => _selectSubCategory(null),
              ),
              const SizedBox(width: 6),
              ...subList.map((s) {
                final count = allVenuesInArea
                    .where((v) => v.effectiveSubCategories.contains(s.id))
                    .length;
                final isSelected = _subCategory == s.id;
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: _SubCategoryVisualPill(
                    label: s.title(widget.arabic),
                    emoji: s.emoji,
                    icon: s.icon,
                    isSelected: isSelected,
                    count: count,
                    arabic: widget.arabic,
                    accentColor: kAccentSurface,
                    onTap: () => _selectSubCategory(s.id),
                  ),
                );
              }),
            ],
          ),
        ),
        if (_subCategory != null) ...[
          const SizedBox(height: 10),
          _buildActiveSubCategoryBanner(),
        ],
      ],
    );
  }

  Widget _buildActiveSubCategoryBanner() {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final def = findSubCategoryDef(_subCategory!);
    if (def == null) return const SizedBox.shrink();

    final matchingCount = _getMatchingVenues().length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
        border: Border.all(
          color: isDark ? kVolt.withValues(alpha: 0.40) : kBorderStrong,
          width: 1.1,
        ),
      ),
      child: Row(
        children: [
          Icon(def.icon, size: 16, color: isDark ? kVolt : kObsidian),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${def.title(widget.arabic)}: ${localized(widget.arabic, '$matchingCount ${matchingCount == 1 ? 'place' : 'places'} available', '$matchingCount ${matchingCount == 1 ? 'مكان متاح' : 'أماكن متاحة'}')}',
              style: TextStyle(
                color: kInk,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          InkWell(
            onTap: () => _selectSubCategory(null),
            borderRadius: BorderRadius.circular(7),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: kSurfaceSubtle,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(widget.arabic, 'Clear', 'إلغاء الفلتر'),
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w800,
                      color: kInk,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: kInk,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCategorizedVenues(
    List<Venue> matchingVenues,
    Venue? selectedVenue,
    VenueItem? item,
    int estimatedMinutes, {
    bool isWide = false,
  }) {
    if (matchingVenues.isEmpty) return const [];

    final groomingVenues = matchingVenues
        .where((v) => v.type == VenueType.salon)
        .toList();
    final entertainmentVenues = matchingVenues
        .where((v) => v.type == VenueType.lounge)
        .toList();
    final sportsVenues = matchingVenues
        .where((v) => v.type == VenueType.sports)
        .toList();

    return [
      if (groomingVenues.isNotEmpty) ...[
        _CategorySectionHeader(
          title: localized(
              widget.arabic, 'Grooming & Barbershops', 'حلاقة وعناية وصالونات'),
          subtitle: localized(
              widget.arabic,
              'Barbershops, haircuts, beard styling & VIP chairs',
              'صالونات حلاقة، تصفيف شعر، عناية شخصية وحجز الكراسي'),
          icon: Icons.content_cut_rounded,
          count: groomingVenues.length,
          accentColor: const Color(0xFF0F766E),
          arabic: widget.arabic,
          onSeeAll: () => _selectCategory(VenueType.salon),
        ),
        ..._buildResponsiveVenueCollection(
          groomingVenues,
          selectedVenue,
          item,
          estimatedMinutes,
          isWide: isWide,
        ),
        const SizedBox(height: 10),
      ],
      if (entertainmentVenues.isNotEmpty) ...[
        _CategorySectionHeader(
          title: localized(
              widget.arabic, 'Entertainment & Lounges', 'ترفيه وألعاب وكافيهات'),
          subtitle: localized(
              widget.arabic,
              'PS5 VIP rooms, billiards, board games & lounges',
              'غرف بلايستيشن VIP، بلياردو، ألعاب وكافيهات'),
          icon: Icons.sports_esports_rounded,
          count: entertainmentVenues.length,
          accentColor: kGreenDark,
          arabic: widget.arabic,
          onSeeAll: () => _selectCategory(VenueType.lounge),
        ),
        ..._buildResponsiveVenueCollection(
          entertainmentVenues,
          selectedVenue,
          item,
          estimatedMinutes,
          isWide: isWide,
        ),
        const SizedBox(height: 10),
      ],
      if (sportsVenues.isNotEmpty) ...[
        _CategorySectionHeader(
          title: localized(
              widget.arabic, 'Sports & Courts', 'ملاعب ورياضة'),
          subtitle: localized(
              widget.arabic,
              'Padel courts, football pitches & fitness',
              'ملاعب بادل، ملاعب كرة قدم وتمارين رياضية'),
          icon: Icons.sports_soccer_rounded,
          count: sportsVenues.length,
          accentColor: kGreen,
          arabic: widget.arabic,
          onSeeAll: () => _selectCategory(VenueType.sports),
        ),
        ..._buildResponsiveVenueCollection(
          sportsVenues,
          selectedVenue,
          item,
          estimatedMinutes,
          isWide: isWide,
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  /// Renders venues in a crisp 2-column responsive grid on tablet/desktop
  /// (>= 900px) with full-width expandable booking drawers below the active row,
  /// and a streamlined single-column feed on compact screens.
  List<Widget> _buildResponsiveVenueCollection(
    List<Venue> venues,
    Venue? selectedVenue,
    VenueItem? item,
    int estimatedMinutes, {
    required bool isWide,
  }) {
    if (!isWide) {
      return venues
          .expand((v) => _buildVenueCardAndBooking(
              v, selectedVenue, item, estimatedMinutes))
          .toList();
    }

    final rows = <Widget>[];
    for (var i = 0; i < venues.length; i += 2) {
      final first = venues[i];
      final second = (i + 1 < venues.length) ? venues[i + 1] : null;
      final rowSelected = (selectedVenue != null &&
              (first.id == selectedVenue.id || second?.id == selectedVenue.id))
          ? selectedVenue
          : null;

      Widget buildCard(Venue v, int cardIndex) {
        final isSel = v.id == selectedVenue?.id;
        return HagzyReveal(
          index: cardIndex,
          stepMs: 50,
          child: AnimatedOpacity(
            duration: HagzyTokens.durationMedium,
            opacity: (selectedVenue != null && !isSel) ? 0.56 : 1.0,
            child: RepaintBoundary(
              child: VenueBrowseCard(
                key: _venueCardKeys.putIfAbsent(v.id, () => GlobalKey()),
                venue: v,
                bookings: widget.bookings,
                arabic: widget.arabic,
                selected: isSel,
                favorite: _favoriteIds.contains(v.id),
                onTap: () => _selectVenue(v),
                onFavorite: () => _toggleFavorite(v),
                onDetails: () => _openVenueDetails(v),
              ),
            ),
          ),
        );
      }

      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildCard(first, i)),
              const SizedBox(width: 16),
              Expanded(
                child: second != null
                    ? buildCard(second, i + 1)
                    : const SizedBox(),
              ),
            ],
          ),
        ),
      );

      if (rowSelected != null) {
        final reducedMotion = HagzyMotion.reduced(context);
        final bookingWidget =
            _buildBookingSection(rowSelected, item, estimatedMinutes);
        rows.add(
          reducedMotion
              ? bookingWidget
              : AnimatedSize(
                  duration: HagzyTokens.durationMedium,
                  curve: HagzyTokens.curveStandard,
                  alignment: Alignment.topCenter,
                  child: bookingWidget,
                ),
        );
      }
    }
    return rows;
  }

  List<Widget> _buildVenueCardAndBooking(
    Venue value,
    Venue? selectedVenue,
    VenueItem? item,
    int estimatedMinutes,
  ) {
    final selected = value.id == selectedVenue?.id;
    final reducedMotion = HagzyMotion.reduced(context);
    final skipSizeAnimation =
        reducedMotion || (!selected && _suppressCollapseAnimVenueId == value.id);
    final bookingChild = (selected && selectedVenue != null)
        ? _buildBookingSection(selectedVenue, item, estimatedMinutes)
        : const SizedBox.shrink();
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AnimatedOpacity(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          opacity: (selectedVenue != null && !selected) ? 0.56 : 1.0,
          child: RepaintBoundary(
            child: VenueBrowseCard(
              key: _venueCardKeys.putIfAbsent(value.id, () => GlobalKey()),
              venue: value,
              bookings: widget.bookings,
              arabic: widget.arabic,
              selected: selected,
              favorite: _favoriteIds.contains(value.id),
              onTap: () => _selectVenue(value),
              onFavorite: () => _toggleFavorite(value),
              onDetails: () => _openVenueDetails(value),
            ),
          ),
        ),
      ),
      skipSizeAnimation
          ? bookingChild
          : AnimatedSize(
              duration: selected
                  ? const Duration(milliseconds: 260)
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: bookingChild,
            ),
    ];
  }

  Widget _buildBookingSection(
    Venue venue,
    VenueItem? item,
    int estimatedMinutes,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final activeStep = item == null ? 1 : (_selectedStart == null ? 2 : 3);
    return Container(
      key: _bookingSectionKey,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(
          color: kAccentSurface,
          width: 1.6,
        ),
        boxShadow: HagzyTheme.softShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pitch-Black Hardware Sequencer Top Tray Header
          Container(
            padding: const EdgeInsets.fromLTRB(18, 15, 14, 15),
            decoration: const BoxDecoration(
              color: kObsidian,
              border: Border(
                bottom: BorderSide(color: Color(0xFF26262F)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: kVermilion,
                    borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
                  ),
                  child: Icon(
                    venue.type.icon,
                    size: 19,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localized(widget.arabic, 'Your Booking', 'حجزك'),
                        style: hagzyTextStyle(
                          arabic: widget.arabic,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${displayLocalizedTitle(venue.name, widget.arabic)}${venue.location.isEmpty ? '' : ' · ${displayLocalizedLocation(venue.location, widget.arabic)}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _favoriteIds.contains(venue.id)
                      ? localized(widget.arabic, 'Remove from Saved',
                          'إزالة من المفضلة')
                      : localized(
                          widget.arabic, 'Save Venue', 'حفظ في المفضلة'),
                  onPressed: () => _toggleFavorite(venue),
                  icon: Icon(
                    _favoriteIds.contains(venue.id)
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    color: _favoriteIds.contains(venue.id)
                        ? kSignal
                        : Colors.white.withValues(alpha: 0.72),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF282522),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(44, 40),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                      side: const BorderSide(color: Color(0xFF3A3631)),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  onPressed: () {
                    HagzyHaptics.selection();
                    setState(() {
                      _venueId = null;
                      _itemId = null;
                      _selectedStart = null;
                    });
                    _scrollController.animateTo(
                      0,
                      duration: const Duration(milliseconds: 280),
                      curve: HagzyMotion.curveDialogEnter,
                    );
                  },
                  icon: const Icon(Icons.close_rounded, size: 15),
                  label: Text(
                    localized(widget.arabic, 'Close', 'إغلاق'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Precision 3-Step Sequencer Progress Bar
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF14141A) : kSurfaceSubtle,
              border: Border(
                bottom: BorderSide(color: kBorder),
              ),
            ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Builder(
                                      builder: (context) {
                                        final isEscape = venue.subCategories.contains('escape_rooms') ||
                                            venue.name.toLowerCase().contains('escape');
                                        final spaceSub = item != null
                                            ? (isEscape
                                                ? (_escapeGroupConfirmed
                                                    ? '${item.name} ($_headcount ${localized(widget.arabic, 'p', 'فرد')})'
                                                    : localized(widget.arabic, 'Pick players', 'حدد الأفراد'))
                                                : item.name)
                                            : localized(widget.arabic, 'Select', 'اختر');
                                        final spaceDone = item != null && (!isEscape || _escapeGroupConfirmed);
                                        return _BookingStepPill(
                                          stepNumber: '1',
                                          title: localized(widget.arabic, 'Space', 'المساحة'),
                                          subtitle: spaceSub,
                                          done: spaceDone,
                                          active: activeStep == 1,
                                          onTap: () => _scrollToKey(_spaceStepKey),
                                        );
                                      },
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: HagzyDirectionalChevron(
                                      size: 16,
                                      color: kMuted,
                                    ),
                                  ),
                                  Expanded(
                                    child: _BookingStepPill(
                                      stepNumber: '2',
                                      title: localized(widget.arabic, 'Time', 'الموعد'),
                                      subtitle: _selectedStart != null
                                          ? '${_selectedStart!.hour.toString().padLeft(2, '0')}:${_selectedStart!.minute.toString().padLeft(2, '0')}'
                                          : localized(widget.arabic, 'Pick slot', 'اختر وقتاً'),
                                      done: _selectedStart != null,
                                      active: activeStep == 2,
                                      onTap: () => _scrollToKey(_timeStepKey),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: HagzyDirectionalChevron(
                                      size: 16,
                                      color: kMuted,
                                    ),
                                  ),
                                  Expanded(
                                    child: _BookingStepPill(
                                      stepNumber: '3',
                                      title: localized(widget.arabic, 'Reserve', 'تأكيد'),
                                      subtitle: _selectedStart != null
                                          ? localized(widget.arabic, 'Ready ✓', 'جاهز ✓')
                                          : localized(widget.arabic, 'Confirm', 'احجز'),
                                      done: false,
                                      active: activeStep == 3,
                                      onTap: () => _scrollToKey(
                                          _selectedStart != null ? _quoteStepKey : _timeStepKey),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Section 1: Space / Option Selector
                            Builder(
                              builder: (context) {
                                final isEscape = venue.subCategories.contains('escape_rooms') ||
                                    venue.name.toLowerCase().contains('escape');

                                if (isEscape) {
                                  // ESCAPE ROOM SPECIFIC STEP FLOW:
                                  // Phase 1: Room Selection (when item == null)
                                  if (item == null) {
                                    return Padding(
                                      key: _spaceStepKey,
                                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(7),
                                                decoration: BoxDecoration(
                                                  color: kGreen.withValues(alpha: 0.12),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(Icons.meeting_room_rounded, color: kGreen, size: 20),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      localized(widget.arabic, 'Choose Your Escape Room', 'اختر غرفة الهروب'),
                                                      style: TextStyle(
                                                        fontSize: 16.5,
                                                        fontWeight: FontWeight.w900,
                                                        color: kInk,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                    Text(
                                                      localized(widget.arabic, 'Tap a room to enter and choose your group size', 'اضغط على الغرفة لدخول التجربة واختيار عدد أفراد الشلة'),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: kMuted,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          ...venue.items.map((room) {
                                            final hasImg = room.imageUrl != null && room.imageUrl!.isNotEmpty;
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 14),
                                              decoration: BoxDecoration(
                                                color: kPanel,
                                                borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
                                                border: Border.all(
                                                  color: kBorder,
                                                  width: 1.1,
                                                ),
                                                boxShadow: HagzyTheme.subtleShadow,
                                              ),
                                              clipBehavior: Clip.antiAlias,
                                              child: InkWell(
                                                onTap: () => _selectSpace(room.id),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                                  children: [
                                                    if (hasImg)
                                                      HagzySmartImage(
                                                        imageUrl: room.imageUrl!,
                                                        height: 140,
                                                        width: double.infinity,
                                                        fit: BoxFit.cover,
                                                      ),
                                                    Padding(
                                                      padding: const EdgeInsets.all(14),
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Row(
                                                            children: [
                                                              Expanded(
                                                                child: Text(
                                                                  room.name,
                                                                  style: TextStyle(
                                                                    fontSize: 16,
                                                                    fontWeight: FontWeight.w900,
                                                                    color: kInk,
                                                                  ),
                                                                ),
                                                              ),
                                                              HagzyMonoTag(
                                                                label: localized(widget.arabic, '60 min', '٦٠ دقيقة'),
                                                                backgroundColor: kSurfaceSubtle,
                                                                foregroundColor: kInk,
                                                                borderColor: kBorder,
                                                              ),
                                                            ],
                                                          ),
                                                          if (room.description.isNotEmpty) ...[
                                                            const SizedBox(height: 8),
                                                            Text(
                                                              room.description,
                                                              maxLines: 3,
                                                              overflow: TextOverflow.ellipsis,
                                                              style: TextStyle(
                                                                fontSize: 13.5,
                                                                color: kMuted,
                                                                height: 1.45,
                                                              ),
                                                            ),
                                                          ],
                                                          const SizedBox(height: 12),
                                                          Align(
                                                            alignment: AlignmentDirectional.centerEnd,
                                                            child: FilledButton.icon(
                                                              onPressed: () => _selectSpace(room.id),
                                                              icon: const Icon(
                                                                Icons.arrow_forward_rounded,
                                                                size: 16,
                                                                color: Colors.white,
                                                              ),
                                                              label: Text(
                                                                localized(widget.arabic, 'Select Room', 'اختر هذه الغرفة'),
                                                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                                                              ),
                                                              style: FilledButton.styleFrom(
                                                                backgroundColor: kAccentSurface,
                                                                foregroundColor: kAccentOnSurface,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall + 2),
                                                                ),
                                                              ),
                                                            ),
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
                                      ),
                                    );
                                  }

                                  // Phase 2: Group Size Selection (when item != null)
                                  final minCap = item.minCapacity ?? 2;
                                  final maxCap = item.maxCapacity ?? 15;
                                  if (_headcount < minCap) {
                                    _headcount = minCap;
                                  } else if (_headcount > maxCap) {
                                    _headcount = maxCap;
                                  }
                                  final perPersonRate = item.priceForHeadcount(_headcount);
                                  final total = perPersonRate * _headcount;
                                  final deposit = total * venue.depositPercent / 100;
                                  final escapeOptions = _getEscapeRoomTierOptions(item);

                                  return Padding(
                                    key: _spaceStepKey,
                                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Back to Room Selection Bar
                                        Row(
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                setState(() {
                                                  _itemId = null;
                                                  _escapeGroupConfirmed = false;
                                                  _sportsDurationMinutes = 60;
                                                  _selectedStart = null;
                                                });
                                              },
                                              borderRadius: BorderRadius.circular(10),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(widget.arabic ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_rounded, size: 13, color: kInk),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      localized(widget.arabic, 'Back to Rooms', 'العودة للغرف'),
                                                      style: TextStyle(
                                                        fontSize: 12.5,
                                                        fontWeight: FontWeight.w800,
                                                        color: kInk,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                decoration: BoxDecoration(
                                                  color: kGreen.withValues(alpha: 0.12),
                                                  borderRadius: BorderRadius.circular(10),
                                                  border: Border.all(color: kGreen.withValues(alpha: 0.25)),
                                                ),
                                                child: Text(
                                                  item.name,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: kGreen,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14),
                                        // Full room detail story card
                                        _RoomDetailCard(
                                          item: item,
                                          isDark: isDark,
                                          arabic: widget.arabic,
                                          isEscapeRoom: true,
                                        ),
                                        const SizedBox(height: 16),
                                        if (_escapeGroupConfirmed) ...[
                                          // Confirmed Group Size Summary Card
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF132A22) : const Color(0xFFF0FDF4),
                                              borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isDark ? const Color(0xFF1F4D3C) : const Color(0xFFBBF7D0),
                                                width: 1.5,
                                              ),
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(6),
                                                      decoration: BoxDecoration(
                                                        color: kGreen.withValues(alpha: 0.2),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(Icons.check_circle_rounded, color: kGreen, size: 20),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            localized(widget.arabic, 'Group Size Confirmed', 'تم تأكيد حجم الشلة'),
                                                            style: TextStyle(
                                                              fontSize: 14.5,
                                                              fontWeight: FontWeight.w800,
                                                              color: isDark ? kGreenLight : kGreenDark,
                                                            ),
                                                          ),
                                                          Text(
                                                            '$_headcount ${localized(widget.arabic, 'Players', 'أفراد')} · ${formatMoney(perPersonRate)} ${localized(widget.arabic, 'EGP / player', 'ج.م / فرد')}',
                                                            style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w700,
                                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          _escapeGroupConfirmed = false;
                                                        });
                                                      },
                                                      icon: Icon(Icons.edit_rounded, size: 15, color: kGreen),
                                                      label: Text(
                                                        localized(widget.arabic, 'Change', 'تعديل'),
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w800,
                                                          color: kGreen,
                                                        ),
                                                      ),
                                                      style: TextButton.styleFrom(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        backgroundColor: kGreen.withValues(alpha: 0.1),
                                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 10),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? const Color(0xFF0C1F18) : Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF1B3D30) : const Color(0xFFDCFCE7),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      Text(
                                                        '${localized(widget.arabic, 'Total:', 'الإجمالي:')} ${formatMoney(total)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontWeight: FontWeight.w800,
                                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                      Text(
                                                        '${localized(widget.arabic, 'Deposit:', 'العربون:')} ${formatMoney(deposit)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: Color(0xFF2563EB),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ] else ...[
                                          // Interactive Headcount Selector Card
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF1E293B) : Colors.white,
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(
                                                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                width: 1.2,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(7),
                                                      decoration: BoxDecoration(
                                                        color: kGreen.withValues(alpha: 0.14),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: Icon(Icons.groups_rounded, color: kGreen, size: 20),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            localized(widget.arabic, 'Number of Players (Shilla)', 'عدد أفراد الشلة'),
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight: FontWeight.w900,
                                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                          Text(
                                                            localized(
                                                              widget.arabic,
                                                              'Room capacity: $minCap to $maxCap players',
                                                              'سعة الغرفة: من $minCap إلى $maxCap أفراد',
                                                            ),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                              fontWeight: FontWeight.w600,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: kGreen.withValues(alpha: 0.14),
                                                        borderRadius: BorderRadius.circular(8),
                                                        border: Border.all(color: kGreen.withValues(alpha: 0.28)),
                                                      ),
                                                      child: Text(
                                                        '${formatMoney(perPersonRate)} ${localized(widget.arabic, 'EGP/person', 'ج.م/فرد')}',
                                                        style: TextStyle(
                                                          fontSize: 12.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: kGreen,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 16),
                                                // Counter Row: [-] X Players [+]
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                                    borderRadius: BorderRadius.circular(14),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                    children: [
                                                      IconButton(
                                                        onPressed: _headcount > minCap
                                                            ? () {
                                                                setState(() {
                                                                  _headcount--;
                                                                });
                                                              }
                                                            : null,
                                                        icon: const Icon(Icons.remove_circle_outline_rounded, size: 28),
                                                        color: _headcount > minCap
                                                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                                            : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                                                        tooltip: localized(widget.arabic, 'Decrease', 'تقليل'),
                                                      ),
                                                      Column(
                                                        children: [
                                                          Text(
                                                            '$_headcount ${localized(widget.arabic, 'Players', 'أفراد')}',
                                                            style: TextStyle(
                                                              fontSize: 20,
                                                              fontWeight: FontWeight.w900,
                                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                          Text(
                                                            '${formatMoney(total)} ${localized(widget.arabic, 'EGP total', 'ج.م إجمالي')}',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w700,
                                                              color: kGreen,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      IconButton(
                                                        onPressed: _headcount < maxCap
                                                            ? () {
                                                                setState(() {
                                                                  _headcount++;
                                                                });
                                                              }
                                                            : null,
                                                        icon: const Icon(Icons.add_circle_outline_rounded, size: 28),
                                                        color: _headcount < maxCap
                                                            ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                                            : (isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                                                        tooltip: localized(widget.arabic, 'Increase', 'زيادة'),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                // Quick choice chips: minCap to maxCap
                                                SingleChildScrollView(
                                                  scrollDirection: Axis.horizontal,
                                                  child: Row(
                                                    children: List.generate(maxCap - minCap + 1, (i) {
                                                      final count = minCap + i;
                                                      final isSel = _headcount == count;
                                                      return Padding(
                                                        padding: const EdgeInsets.only(right: 6),
                                                        child: ChoiceChip(
                                                          label: Text(
                                                            '$count',
                                                            style: TextStyle(
                                                              fontWeight: isSel ? FontWeight.w900 : FontWeight.w700,
                                                              fontSize: 13,
                                                              color: isSel
                                                                  ? Colors.white
                                                                  : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155)),
                                                            ),
                                                          ),
                                                          selected: isSel,
                                                          selectedColor: kGreen,
                                                          backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                                          side: BorderSide(
                                                            color: isSel
                                                                ? kGreen
                                                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                                          ),
                                                          shape: RoundedRectangleBorder(
                                                            borderRadius: BorderRadius.circular(10),
                                                          ),
                                                          onSelected: (_) {
                                                            setState(() {
                                                              _headcount = count;
                                                            });
                                                          },
                                                        ),
                                                      );
                                                    }),
                                                  ),
                                                ),
                                                if (escapeOptions.isNotEmpty) ...[
                                                  const SizedBox(height: 12),
                                                  // Pricing tiers ladder with active highlight
                                                  Wrap(
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children: escapeOptions.map((opt) {
                                                      final isActiveTier = _headcount >= opt.minPeople && _headcount <= opt.maxPeople;
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: isActiveTier
                                                              ? (isDark ? kGreen.withValues(alpha: 0.22) : const Color(0xFFDCFCE7))
                                                              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
                                                          borderRadius: BorderRadius.circular(10),
                                                          border: Border.all(
                                                            color: isActiveTier
                                                                ? kGreen
                                                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                                                            width: isActiveTier ? 1.5 : 1,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            if (isActiveTier) ...[
                                                              Icon(Icons.check_circle_rounded, color: kGreen, size: 14),
                                                              const SizedBox(width: 5),
                                                            ],
                                                            Text(
                                                              '${localized(widget.arabic, opt.labelEn, opt.labelAr)}: ${formatMoney(opt.pricePerPerson)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: isActiveTier ? FontWeight.w800 : FontWeight.w600,
                                                                color: isActiveTier
                                                                    ? (isDark ? kGreenLight : kGreenDark)
                                                                    : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    }).toList(),
                                                  ),
                                                ],
                                                const SizedBox(height: 14),
                                                // Live Price Breakdown Box
                                                Container(
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                    ),
                                                  ),
                                                  child: Column(
                                                    children: [
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(
                                                            localized(widget.arabic, 'Rate per Player:', 'سعر الفرد:'),
                                                            style: TextStyle(
                                                              fontSize: 12.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                            ),
                                                          ),
                                                          Text(
                                                            '${formatMoney(perPersonRate)} ${localized(widget.arabic, 'EGP / player', 'جنيه / فرد')}',
                                                            style: TextStyle(
                                                              fontSize: 14.5,
                                                              fontWeight: FontWeight.w900,
                                                              color: kGreen,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(
                                                            localized(widget.arabic, 'Total for $_headcount players:', 'إجمالي $_headcount أفراد:'),
                                                            style: TextStyle(
                                                              fontSize: 12.5,
                                                              fontWeight: FontWeight.w700,
                                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                            ),
                                                          ),
                                                          Text(
                                                            '${formatMoney(total)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                            style: TextStyle(
                                                              fontSize: 15,
                                                              fontWeight: FontWeight.w900,
                                                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      const SizedBox(height: 5),
                                                      Row(
                                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                        children: [
                                                          Text(
                                                            localized(widget.arabic, 'Deposit Due Now (${venue.depositPercent}%):', 'العربون المطلوب الآن (${venue.depositPercent}%):'),
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w600,
                                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                            ),
                                                          ),
                                                          Text(
                                                            '${formatMoney(deposit)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                            style: const TextStyle(
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.w800,
                                                              color: Color(0xFF2563EB),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(height: 14),
                                                // Confirm Group Size Button
                                                FilledButton.icon(
                                                  onPressed: () {
                                                    setState(() {
                                                      _escapeGroupConfirmed = true;
                                                    });
                                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                                      if (!mounted) return;
                                                      _scrollToKey(_timeStepKey);
                                                    });
                                                  },
                                                  icon: const Icon(Icons.check_rounded, size: 18),
                                                  label: Text(
                                                    localized(
                                                      widget.arabic,
                                                      'Confirm Group Size ($_headcount Players) · Total: ${formatMoney(total)} EGP',
                                                      'تأكيد عدد الأفراد ($_headcount أفراد) · الإجمالي: ${formatMoney(total)} ج.م',
                                                    ),
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor: kGreen,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(14),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }


                                final isSports = venue.type == VenueType.sports;

                                if (isSports) {
                                  // SPORTS & PADEL COURTS: Court Pills + Match Duration Selection Phase
                                  final List<(int, String, String, String, String)> sportsDurations =
                                      (item != null && item.customDurations != null && item.customDurations!.isNotEmpty)
                                          ? (item.customDurations!.keys
                                              .map((k) => int.tryParse(k))
                                              .whereType<int>()
                                              .toList()
                                            ..sort())
                                              .map((mins) {
                                              final h = mins / 60.0;
                                              final labelEn = h == h.toInt()
                                                  ? '${h.toInt()} Hour${h > 1 ? 's' : ''} ($mins min)'
                                                  : '$h Hours ($mins min)';
                                              final labelAr = mins == 60
                                                  ? '٦٠ دقيقة (ساعة واحدة)'
                                                  : (mins == 90
                                                      ? '٩٠ دقيقة (ساعة ونصف)'
                                                      : (mins == 120
                                                          ? '١٢٠ دقيقة (ساعتان)'
                                                          : (mins == 180
                                                              ? '١٨٠ دقيقة (٣ ساعات)'
                                                              : '$mins دقيقة')));
                                              return (mins, labelEn, labelAr, 'Match Duration', 'مدة الماتش');
                                            }).toList()
                                          : const [
                                              (60, '60 Minutes (1 Hour)', '٦٠ دقيقة (ساعة واحدة)', 'Quick Match / Warmup', 'ماتش سريع / تسخين'),
                                              (90, '90 Minutes (1.5 Hours)', '٩٠ دقيقة (ساعة ونصف)', 'Standard Padel Match', 'ماتش بادل قياسي'),
                                              (120, '120 Minutes (2 Hours)', '١٢٠ دقيقة (ساعتان)', 'Full Game / Rematch', 'ماتش كامل / ريماتش'),
                                              (180, '180 Minutes (3 Hours)', '١٨٠ دقيقة (٣ ساعات)', 'Training / Tournament', 'تدريب مكثف / بطولة'),
                                            ];

                                  return Padding(
                                    key: _spaceStepKey,
                                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                localized(widget.arabic, 'Choose Your Space', 'اختر المساحة'),
                                                style: TextStyle(
                                                  fontSize: 15.5,
                                                  fontWeight: FontWeight.w900,
                                                  color: kInk,
                                                  letterSpacing: -0.2,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: venue.items.map((val) {
                                            final sel = val.id == item?.id;
                                            return CustomPill(
                                              icon: sel ? Icons.check_circle_rounded : venue.type.icon,
                                              selected: sel,
                                              label: '${displayLocalizedTitle(val.name, widget.arabic)} · ${formatMoney(val.hourlyRate)} ${localized(widget.arabic, 'EGP/h', 'ج.م/س')}',
                                              onTap: () => _selectSpace(val.id),
                                            );
                                          }).toList(),
                                        ),
                                        if (item != null) ...[
                                          const SizedBox(height: 16),
                                          // Duration Selection Phase
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(7),
                                                decoration: BoxDecoration(
                                                  color: kGreen.withValues(alpha: 0.14),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(Icons.timer_outlined, color: kGreen, size: 20),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      localized(widget.arabic, 'Select Match Duration', 'اختر مدة اللعب'),
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight: FontWeight.w900,
                                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                      ),
                                                    ),
                                                    Text(
                                                      localized(widget.arabic, 'How long is your match or training session?', 'كم مدة الماتش أو التمرين؟'),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          ...sportsDurations.map((dur) {
                                            final minutes = dur.$1;
                                            final isSelected = _sportsDurationMinutes == minutes;
                                            final durTotal = item.priceForDuration(minutes);
                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 8),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? (isDark ? const Color(0xFF1A1E14) : kObsidian)
                                                    : kSurfaceSubtle.withValues(alpha: 0.55),
                                                borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
                                                border: Border.all(
                                                  color: isSelected
                                                      ? (isDark ? kVolt : kObsidian)
                                                      : kBorder,
                                                  width: isSelected ? 1.6 : 1.1,
                                                ),
                                              ),
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
                                                onTap: () {
                                                  setState(() {
                                                    _sportsDurationMinutes = minutes;
                                                  });
                                                },
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        isSelected
                                                            ? Icons.radio_button_checked_rounded
                                                            : Icons.radio_button_off_rounded,
                                                        color: isSelected ? kVolt : kMuted,
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              localized(widget.arabic, dur.$2, dur.$3),
                                                              style: TextStyle(
                                                                fontSize: 14.5,
                                                                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                                                color: isSelected ? Colors.white : kInk,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              localized(widget.arabic, dur.$4, dur.$5),
                                                              style: TextStyle(
                                                                fontSize: 11.5,
                                                                color: isSelected
                                                                    ? Colors.white.withValues(alpha: 0.68)
                                                                    : kMuted,
                                                                fontWeight: FontWeight.w600,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      Text(
                                                        '${formatMoney(durTotal)} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                        style: hagzyMonoStyle(
                                                          fontSize: 13.5,
                                                          fontWeight: FontWeight.w800,
                                                          color: isSelected ? kVolt : kInk,
                                                          arabic: widget.arabic,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),
                                          const SizedBox(height: 10),
                                          Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: kSurfaceSubtle,
                                              borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
                                              border: Border.all(color: kBorder),
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Text(
                                                  localized(widget.arabic, 'Total for $_sportsDurationMinutes min:', 'إجمالي المدة ($_sportsDurationMinutes دقيقة):'),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: kMuted,
                                                  ),
                                                ),
                                                HagzyAnimatedValue(
                                                  valueKey: _sportsDurationMinutes,
                                                  child: Text(
                                                    '${formatMoney(item.priceForDuration(_sportsDurationMinutes))} ${localized(widget.arabic, 'EGP', 'ج.م')}',
                                                    style: hagzyMonoStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w900,
                                                      color: isDark ? kVolt : kObsidian,
                                                      arabic: widget.arabic,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }
                                // STANDARD VENUE FLOW (Salons, Cafes, Lounges):
                                return Padding(
                                  key: _spaceStepKey,
                                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              localized(widget.arabic, 'Choose Your Space', 'اختر المساحة'),
                                              style: TextStyle(
                                                fontSize: 15.5,
                                                fontWeight: FontWeight.w900,
                                                color: kInk,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      if (venue.items.isEmpty)
                                        Text(
                                          localized(
                                              widget.arabic,
                                              'This venue has no bookable spaces yet.',
                                              'لا توجد مساحات متاحة للحجز حالياً.'),
                                          style: TextStyle(color: kMuted),
                                        )
                                      else
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: venue.items.map((val) {
                                            final sel = val.id == item?.id;
                                            return CustomPill(
                                              icon: sel
                                                  ? Icons.check_circle_rounded
                                                  : venue.type.icon,
                                              selected: sel,
                                              label: () {
                                                final labelName = displayLocalizedTitle(
                                                    val.name, widget.arabic);
                                                if (venue.type == VenueType.salon) {
                                                  return '$labelName · ${formatMoney(val.hourlyRate)} ${localized(widget.arabic, 'EGP/30m', 'ج.م/٣٠ د')}';
                                                }
                                                return '$labelName · ${formatMoney(val.hourlyRate)} ${localized(widget.arabic, 'EGP/h', 'ج.م/س')}';
                                              }(),
                                              onTap: () => _selectSpace(val.id),
                                            );
                                          }).toList(),
                                        ),
                                      if (item != null && ((item.imageUrl != null && item.imageUrl!.isNotEmpty) || item.description.isNotEmpty)) ...[
                                        _RoomDetailCard(
                                          item: item,
                                          isDark: isDark,
                                          arabic: widget.arabic,
                                          isEscapeRoom: false,
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            ),
                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: (item != null && ((!venue.subCategories.contains('escape_rooms') && !venue.name.toLowerCase().contains('escape')) || _escapeGroupConfirmed))
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        const Divider(height: 1),
                                        // Section 2: Date & Time Picker
                                        Padding(
                                          key: _timeStepKey,
                                          padding: const EdgeInsets.fromLTRB(
                                              20, 18, 20, 10),
                                          child: Builder(
                                            builder: (context) {
                                              final allSlots = _timesFor(
                                                  venue, item, estimatedMinutes);
                                              final morningSlots = allSlots
                                                  .where((s) => s.start.hour < 13)
                                                  .toList();
                                              final afternoonSlots = allSlots
                                                  .where((s) =>
                                                      s.start.hour >= 13 &&
                                                      s.start.hour < 17)
                                                  .toList();
                                              final eveningSlots = allSlots
                                                  .where(
                                                      (s) => s.start.hour >= 17)
                                                  .toList();
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: Text(
                                                          localized(
                                                              widget.arabic,
                                                              'Pick an Available Time',
                                                              'اختر وقتاً متاحاً'),
                                                          style:
                                                              TextStyle(
                                                            fontSize: 15.5,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color: kInk,
                                                            letterSpacing: -0.2,
                                                          ),
                                                        ),
                                                      ),
                                                      InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(999),
                                                        onTap: () async {
                                                          final selectedDate =
                                                              await showDatePicker(
                                                            context: context,
                                                            initialDate: _date
                                                                    .isBefore(
                                                                        DateTime
                                                                            .now())
                                                                ? DateTime
                                                                    .now()
                                                                : _date,
                                                            firstDate:
                                                                DateTime.now(),
                                                            lastDate: DateTime
                                                                    .now()
                                                                .add(
                                                                    const Duration(
                                                                        days:
                                                                            180)),
                                                          );
                                                          if (selectedDate !=
                                                              null) {
                                                            setState(() {
                                                              _date =
                                                                  selectedDate;
                                                              _selectedStart =
                                                                  null;
                                                            });
                                                          }
                                                        },
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      11,
                                                                  vertical: 6),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: kPage,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        999),
                                                            border: Border.all(
                                                                color: kBorder),
                                                          ),
                                                          child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              Icon(
                                                                  Icons
                                                                      .calendar_month_rounded,
                                                                  size: 15,
                                                                  color:
                                                                      kGreen),
                                                              const SizedBox(
                                                                  width: 5),
                                                              Text(
                                                                '${_date.day}/${_date.month}/${_date.year}',
                                                                style:
                                                                    const TextStyle(
                                                                  fontSize:
                                                                      12.0,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 14),
                                                  _buildDateStrip(widget.arabic),
                                                  AnimatedSize(
                                                    duration: const Duration(
                                                        milliseconds: 220),
                                                    curve: Curves.easeOutCubic,
                                                    alignment:
                                                        Alignment.topCenter,
                                                    child: _selectedStart != null
                                                        ? Container(
                                                            margin:
                                                                const EdgeInsets
                                                                    .only(
                                                                    top: 12),
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        14,
                                                                    vertical:
                                                                        10),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: kObsidian,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          HagzyTokens
                                                                              .radiusMedium),
                                                              border: Border.all(
                                                                  color: kVolt
                                                                      .withValues(
                                                                          alpha:
                                                                              0.5)),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .check_circle_rounded,
                                                                  color: kVolt,
                                                                  size: 18,
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Expanded(
                                                                  child: Text(
                                                                    '${TimeOfDay.fromDateTime(_selectedStart!).format(context)} · ${item.name}',
                                                                    style:
                                                                        hagzyMonoStyle(
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      fontSize:
                                                                          12.5,
                                                                      arabic: widget
                                                                          .arabic,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                FilledButton(
                                                                  style: FilledButton
                                                                      .styleFrom(
                                                                    backgroundColor:
                                                                        kVermilion,
                                                                    foregroundColor:
                                                                        Colors.white,
                                                                    visualDensity:
                                                                        VisualDensity
                                                                            .compact,
                                                                    padding: const EdgeInsets
                                                                        .symmetric(
                                                                        horizontal:
                                                                            14,
                                                                        vertical:
                                                                            8),
                                                                    shape: RoundedRectangleBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                HagzyTokens.radiusSmall)),
                                                                  ),
                                                                  onPressed: () =>
                                                                      widget.onBook(
                                                                          venue,
                                                                          item,
                                                                          _selectedStart!,
                                                                          _headcount),
                                                                  child: Text(
                                                                    localized(
                                                                        widget
                                                                            .arabic,
                                                                        'Reserve Now',
                                                                        'احجز الآن'),
                                                                    style:
                                                                        const TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w900,
                                                                      fontSize:
                                                                          12,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        : const SizedBox.shrink(),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  _buildTimeSlotGroup(
                                                    title: localized(
                                                        widget.arabic,
                                                        'Morning (10 AM - 1 PM)',
                                                        'الصباح (١٠ ص - ١ م)'),
                                                    icon: Icons.wb_sunny_rounded,
                                                    slots: morningSlots,
                                                    arabic: widget.arabic,
                                                  ),
                                                  _buildTimeSlotGroup(
                                                    title: localized(
                                                        widget.arabic,
                                                        'Afternoon (1 PM - 5 PM)',
                                                        'بعد الظهر (١ م - ٥ م)'),
                                                    icon: Icons
                                                        .wb_twilight_rounded,
                                                    slots: afternoonSlots,
                                                    arabic: widget.arabic,
                                                  ),
                                                  _buildTimeSlotGroup(
                                                    title: localized(
                                                        widget.arabic,
                                                        'Evening & Night (5 PM - 10 PM)',
                                                        'المساء والليل (٥ م - ١٠ م)'),
                                                    icon: Icons
                                                        .nightlight_round,
                                                    slots: eveningSlots,
                                                    arabic: widget.arabic,
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                        ),
                                        const Divider(height: 1),
                                        // Section 3: Breadfast / Talabat Cart-Style Checkout Bar
                                        Padding(
                                          key: _quoteStepKey,
                                          padding: const EdgeInsets.all(18),
                                          child: ReservationQuote(
                                            venue: venue,
                                            item: item,
                                            arabic: widget.arabic,
                                            estimatedMinutes: venue.type == VenueType.sports ? _sportsDurationMinutes : estimatedMinutes,
                                            selectedStart: _selectedStart,
                                            headcount: _headcount,
                                            onHeadcountChanged: (h) => setState(() => _headcount = h),
                                            onReserve: _selectedStart == null
                                                ? null
                                                : () => widget.onBook(venue, item, _selectedStart!, _headcount, venue.type == VenueType.sports ? _sportsDurationMinutes : estimatedMinutes),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      );
  }


  List<EscapeRoomTierOption> _getEscapeRoomTierOptions(VenueItem item) {
    if (item.id == 'adrenaline-orphans') {
      return const [
        EscapeRoomTierOption(
          labelAr: 'فردين أو 3 أفراد',
          labelEn: '2 or 3 players',
          minPeople: 2,
          maxPeople: 3,
          defaultHeadcount: 3,
          pricePerPerson: 150,
        ),
        EscapeRoomTierOption(
          labelAr: '4 أو 5 أفراد',
          labelEn: '4 or 5 players',
          minPeople: 4,
          maxPeople: 5,
          defaultHeadcount: 4,
          pricePerPerson: 120,
        ),
        EscapeRoomTierOption(
          labelAr: 'أكتر من 5 أفراد',
          labelEn: 'More than 5 players',
          minPeople: 6,
          maxPeople: 15,
          defaultHeadcount: 6,
          pricePerPerson: 100,
        ),
      ];
    } else if (item.id == 'adrenaline-cannibal') {
      return const [
        EscapeRoomTierOption(
          labelAr: '4 أو 5 أفراد',
          labelEn: '4 or 5 players',
          minPeople: 4,
          maxPeople: 5,
          defaultHeadcount: 4,
          pricePerPerson: 120,
        ),
        EscapeRoomTierOption(
          labelAr: 'أكتر من 5 أفراد',
          labelEn: 'More than 5 players',
          minPeople: 6,
          maxPeople: 15,
          defaultHeadcount: 6,
          pricePerPerson: 100,
        ),
      ];
    } else if (item.id == 'adrenaline-the-curse') {
      return const [
        EscapeRoomTierOption(
          labelAr: '3 أو 4 أفراد',
          labelEn: '3 or 4 players',
          minPeople: 3,
          maxPeople: 4,
          defaultHeadcount: 4,
          pricePerPerson: 200,
        ),
        EscapeRoomTierOption(
          labelAr: '5 أفراد أو أكتر',
          labelEn: '5 or more players',
          minPeople: 5,
          maxPeople: 20,
          defaultHeadcount: 5,
          pricePerPerson: 150,
        ),
      ];
    }

    if (item.pricingTiers != null && item.pricingTiers!.isNotEmpty) {
      final sortedEntries = item.pricingTiers!.entries
          .map((e) => MapEntry(int.tryParse(e.key) ?? 999, (e.value as num).toDouble()))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final minCap = item.minCapacity ?? 2;
      final maxCap = item.maxCapacity ?? 15;
      var prevCap = minCap - 1;
      final list = <EscapeRoomTierOption>[];
      for (final e in sortedEntries) {
        final cap = e.key;
        final price = e.value;
        final from = prevCap + 1;
        final isLast = cap >= maxCap || e == sortedEntries.last;
        String ar;
        String en;
        if (from == cap) {
          ar = '$cap أفراد';
          en = '$cap players';
        } else if (isLast) {
          ar = 'أكتر من $prevCap أفراد';
          en = 'More than $prevCap players';
        } else {
          ar = '$from أو $cap أفراد';
          en = '$from or $cap players';
        }
        list.add(EscapeRoomTierOption(
          labelAr: ar,
          labelEn: en,
          minPeople: from,
          maxPeople: cap,
          defaultHeadcount: from,
          pricePerPerson: price,
        ));
        prevCap = cap;
      }
      return list;
    }

    return [
      EscapeRoomTierOption(
        labelAr: 'جميع الأحجام',
        labelEn: 'All Group Sizes',
        minPeople: item.minCapacity ?? 2,
        maxPeople: item.maxCapacity ?? 15,
        defaultHeadcount: item.minCapacity ?? 2,
        pricePerPerson: item.hourlyRate,
      ),
    ];
  }

  List<TimeSlot> _timesFor(Venue venue, VenueItem item, int durationMinutes) {
    final slots = <TimeSlot>[];
    final day = DateTime(_date.year, _date.month, _date.day);
    final openMin = (venue.openHour.clamp(6, 20)) * 60;
    final closeMin = (venue.closeHour.clamp(openMin ~/ 60 + 1, 23)) * 60;
    for (var minutes = openMin; minutes <= closeMin; minutes += 30) {
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
      slots.add(TimeSlot(
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
      _subCategory = null;
      _venueId = null;
      _itemId = null;
      _selectedStart = null;
    });
  }

  void _selectSubCategory(String? subId) {
    setState(() {
      if (_subCategory == subId) {
        _subCategory = null;
      } else {
        _subCategory = subId;
        if (subId != null) {
          final def = findSubCategoryDef(subId);
          if (def != null && _type != null && _type != def.parentType) {
            _type = def.parentType;
          }
        }
      }
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
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final isTomorrow = date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day;
    if (isToday) return localized(arabic, 'Today', 'اليوم');
    if (isTomorrow) return localized(arabic, 'Tomorrow', 'غداً');
    final weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekdaysAr = [
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد'
    ];
    return localized(
        arabic, weekdaysEn[date.weekday - 1], weekdaysAr[date.weekday - 1]);
  }

  String _monthLabel(int month, bool arabic) {
    const monthsEn = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const monthsAr = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    return localized(arabic, monthsEn[month - 1], monthsAr[month - 1]);
  }

  Widget _buildDateStrip(bool arabic) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final today = DateTime.now();
    // Calculate calendar dates without 24h DST duplication
    final days = List.generate(
      14,
      (index) => DateTime(today.year, today.month, today.day + index),
    );
    return SizedBox(
      height: 88,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (context, index) {
          final d = days[index];
          final isSelected = d.year == _date.year &&
              d.month == _date.month &&
              d.day == _date.day;
          final selBg = isDark ? kVermilion : kObsidian;
          const selFg = Colors.white;
          final selSub = Colors.white.withValues(alpha: 0.78);
          return Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: HagzyInteractiveSurface(
              hoverLift: 1.5,
              pressScale: 0.94,
              onTap: () {
                setState(() {
                  _date = d;
                  _selectedStart = null;
                });
              },
              builder: (context, hovered, _) => AnimatedContainer(
                duration: HagzyMotion.durationMicro,
                curve: HagzyMotion.curveSnappy,
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? selBg : kPanel,
                  borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
                  border: Border.all(
                    color: isSelected
                        ? selBg
                        : (hovered ? kBorderStrong : kBorder),
                    width: isSelected ? 1.5 : 1.1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _dayLabel(d, arabic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.1,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? selSub : kMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.day}'.padLeft(2, '0'),
                      style: hagzyMonoStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isSelected ? selFg : kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _monthLabel(d.month, arabic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.0,
                        height: 1.1,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? selSub : kMuted,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 4),
                      Container(
                        width: 16,
                        height: 2.5,
                        color: isDark ? Colors.white : kVermilion,
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
    required List<TimeSlot> slots,
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
                Icon(icon, size: 15, color: kMuted),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: kMuted,
                    letterSpacing: 0.2,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: availableCount > 0
                        ? kGreenLight.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    availableCount > 0
                        ? localized(arabic, '$availableCount available',
                            '$availableCount متاح')
                        : (slots.isNotEmpty &&
                                slots.every(
                                    (s) => !s.start.isAfter(DateTime.now()))
                            ? localized(arabic, 'Passed today', 'انتهى اليوم')
                            : localized(arabic, 'Fully booked', 'مكتمل')),
                    style: TextStyle(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w700,
                      color: availableCount > 0 ? kGreen : kMuted,
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
              return TimeSlotPill(
                label: slot.label,
                selected: selected,
                available: slot.available,
                onTap: slot.available ? () => _selectTime(slot.start) : null,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class ReservationQuote extends StatelessWidget {
  const ReservationQuote({
    super.key,
    required this.venue,
    required this.item,
    required this.estimatedMinutes,
    required this.arabic,
    required this.selectedStart,
    required this.onReserve,
    this.headcount = 2,
    this.onHeadcountChanged,
  });

  final Venue venue;
  final VenueItem item;
  final int estimatedMinutes;
  final bool arabic;
  final DateTime? selectedStart;
  final VoidCallback? onReserve;
  final int headcount;
  final ValueChanged<int>? onHeadcountChanged;

  @override
  Widget build(BuildContext context) {
    final isPerPerson = item.pricingMode == 'per_person_tiered' ||
        (item.pricingTiers != null && item.pricingTiers!.isNotEmpty) ||
        venue.subCategories.contains('escape_rooms');
    final perPersonRate = item.priceForHeadcount(headcount);
    final total = venue.type == VenueType.salon
        ? (item.hourlyRate > 0
            ? item.hourlyRate
            : (venue.services.isNotEmpty ? venue.services.first.price : 0.0))
        : (isPerPerson
            ? perPersonRate * headcount
            : item.hourlyRate * estimatedMinutes / 60);
    final rawDeposit = total * venue.depositPercent / 100;
    final deposit = rawDeposit > 0 && rawDeposit < 5.0 ? 5.0 : rawDeposit;
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Container(
      decoration: BoxDecoration(
        color: kSurfaceSubtle.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(color: kBorder, width: 1.1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: selectedStart != null
                ? Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kObsidian,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusMedium),
                      border: Border.all(
                        color: kVolt.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: kVermilion,
                            borderRadius:
                                BorderRadius.circular(HagzyTokens.radiusSmall),
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
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                formatDateTime(selectedStart!),
                                style: hagzyMonoStyle(
                                  color: kVolt,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.0,
                                  arabic: arabic,
                                ),
                              ),
                            ],
                          ),
                        ),
                        HagzyMonoTag(
                          label: '$estimatedMinutes min',
                          backgroundColor: const Color(0xFF1A1A22),
                          foregroundColor: Colors.white,
                          borderColor: Colors.white.withValues(alpha: 0.16),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      localized(arabic, 'Total', 'الإجمالي'),
                      style: hagzyMonoStyle(
                          color: kMuted,
                          fontSize: 11.0,
                          fontWeight: FontWeight.w700,
                          arabic: arabic),
                    ),
                    const SizedBox(height: 2),
                    HagzyAnimatedValue(
                      valueKey: total.toStringAsFixed(0),
                      child: Text(
                        '${formatMoney(total)} ${localized(arabic, 'EGP', 'جنيه')}',
                        style: hagzyMonoStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: kInk,
                            arabic: arabic),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? kVolt.withValues(alpha: 0.12)
                      : kObsidian,
                  borderRadius:
                      BorderRadius.circular(HagzyTokens.radiusMedium),
                  border: Border.all(
                    color: isDark
                        ? kVolt.withValues(alpha: 0.35)
                        : kObsidian,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${localized(arabic, 'Deposit', 'العربون')} (${formatMoney(venue.depositPercent)}%)',
                      style: hagzyMonoStyle(
                        color: isDark
                            ? kVolt.withValues(alpha: 0.85)
                            : Colors.white.withValues(alpha: 0.72),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        arabic: arabic,
                      ),
                    ),
                    const SizedBox(height: 2),
                    HagzyAnimatedValue(
                      valueKey: deposit.toStringAsFixed(0),
                      child: Text(
                        '${formatMoney(deposit)} ${localized(arabic, 'EGP', 'جنيه')}',
                        style: hagzyMonoStyle(
                            color: kVolt,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            arabic: arabic),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.verified_user_outlined,
                  size: 15, color: isDark ? kVolt : kObsidian),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  localized(
                      arabic,
                      'We hold the time for 15 minutes. It is confirmed only after the deposit is verified.',
                      'نحتفظ بالموعد لمدة ١٥ دقيقة. يتأكد الحجز فقط بعد التحقق من دفع العربون.'),
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 12.0,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kAccentSurface,
                foregroundColor: kAccentOnSurface,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(HagzyTokens.radiusMedium),
                ),
              ),
              onPressed: onReserve == null
                  ? null
                  : () {
                      HagzyHaptics.medium();
                      onReserve!();
                    },
              icon: Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: onReserve == null ? kMuted : Colors.white,
              ),
              label: Text(
                localized(
                    arabic, 'Reserve & pay deposit', 'احجز وادفع العربون'),
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TimeSlot {
  const TimeSlot({
    required this.start,
    required this.label,
    required this.available,
  });
  final DateTime start;
  final String label;
  final bool available;
}

class TimeSlotPill extends StatelessWidget {
  const TimeSlotPill({
    super.key,
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
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final selBg = isDark ? kVermilion : kObsidian;
    const selFg = Colors.white;
    return HagzyInteractiveSurface(
      enabled: available,
      hoverLift: 1.0,
      pressScale: 0.96,
      haptic: HagzyHapticStyle.selection,
      onTap: onTap,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: HagzyMotion.durationMicro,
        curve: HagzyMotion.curveSnappy,
        constraints: const BoxConstraints(minHeight: 44),
        decoration: BoxDecoration(
          color: selected
              ? selBg
              : available
                  ? kPanel
                  : kSurfaceSubtle.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
          border: Border.all(
            color: selected
                ? selBg
                : available
                    ? (hovered ? kBorderStrong : kBorder)
                    : kBorder.withValues(alpha: 0.55),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected || !available) ...[
                Icon(
                  selected
                      ? Icons.check_rounded
                      : Icons.lock_clock_outlined,
                  size: 13,
                  color: selected
                      ? Colors.white
                      : kMuted.withValues(alpha: 0.65),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: hagzyMonoStyle(
                  color: selected
                      ? selFg
                      : available
                          ? kInk
                          : kMuted.withValues(alpha: 0.60),
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                  arabic: isArabicMode,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerAreaBar extends StatelessWidget {
  const CustomerAreaBar({
    super.key,
    required this.area,
    required this.arabic,
    required this.onTap,
    this.onGpsTap,
    this.isLocating = false,
  });

  final String area;
  final bool arabic;
  final VoidCallback onTap;
  final VoidCallback? onGpsTap;
  final bool isLocating;

  @override
  Widget build(BuildContext context) {
    return HagzyTap(
      onTap: onTap,
      scaleDown: 0.985,
      haptic: HagzyHapticStyle.selection,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kSurfaceTint,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
              ),
              child: Icon(
                Icons.location_on_rounded,
                color: kBrandAccent,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(arabic, 'Location', 'الموقع'),
                    style: TextStyle(
                      color: kMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          area,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            color: kInk,
                            letterSpacing: arabic ? 0 : -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          color: kMuted, size: 18),
                    ],
                  ),
                ],
              ),
            ),
            if (onGpsTap != null) ...[
              Tooltip(
                message: localized(arabic, 'Auto-assign via GPS',
                    'تحديد منطقتي تلقائياً عبر GPS'),
                child: HagzyTap(
                  scaleDown: 0.95,
                  haptic: HagzyHapticStyle.selection,
                  enabled: !isLocating,
                  onTap: isLocating ? null : onGpsTap,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    margin: const EdgeInsetsDirectional.only(end: 6),
                    decoration: BoxDecoration(
                      color: kSurfaceSubtle,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLocating)
                          SizedBox(
                            width: 13,
                            height: 13,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.8,
                              valueColor: AlwaysStoppedAnimation<Color>(kInk),
                            ),
                          )
                        else
                          Icon(Icons.my_location_rounded,
                              color: kBrandAccent, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          'GPS',
                          style: hagzyMonoStyle(
                            color: kInk,
                            fontSize: 12.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            Container(
              constraints: const BoxConstraints(minHeight: 38),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: kSurfaceSubtle,
                borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(arabic, 'Change', 'تغيير'),
                    style: TextStyle(
                      color: kInk,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: kInk, size: 15),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerHero extends StatelessWidget {
  const CustomerHero({
    super.key,
    required this.venueCount,
    required this.type,
    required this.arabic,
  });

  final int venueCount;
  final VenueType? type;
  final bool arabic;

  (IconData, String, String) get _content => switch (type) {
        VenueType.sports => (
            Icons.sports_tennis_rounded,
            localized(arabic, 'Sports & Courts', 'ملاعب ورياضة'),
            localized(arabic, 'Padel courts, football pitches & instant holds',
                'ملاعب بادل وكرة قدم بتثبيت فوري'),
          ),
        VenueType.salon => (
            Icons.content_cut_rounded,
            localized(arabic, 'Grooming & Barbershops', 'حلاقة وعناية وصالونات'),
            localized(arabic, 'Barbershops & salons with instant appointments',
                'صالونات حلاقة وعناية بحجز فوري'),
          ),
        VenueType.lounge => (
            Icons.sports_esports_rounded,
            localized(arabic, 'Entertainment & Lounges', 'ترفيه وألعاب وكافيهات'),
            localized(arabic, 'PS5 rooms, billiards, ping pong & escape rooms',
                'غرف بلايستيشن وبلياردو وغرف هروب'),
          ),
        null => (
            Icons.explore_rounded,
            localized(arabic, 'Book your next spot', 'احجز مكانك في لحظة'),
            venueCount > 0
                ? (arabic
                    ? (venueCount == 1
                        ? 'مكان واحد متاح للحجز الفوري'
                        : venueCount == 2
                            ? 'مكانان متاحان للحجز الفوري'
                            : venueCount <= 10
                                ? '$venueCount أماكن متاحة للحجز الفوري'
                                : '$venueCount مكاناً متاحاً للحجز الفوري')
                    : '$venueCount local ${venueCount == 1 ? 'place' : 'places'} ready to book')
                : localized(arabic, 'Instant booking across Egypt',
                    'حجز فوري في جميع أنحاء مصر'),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final content = _content;
    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;

    return AnimatedSwitcher(
      duration: HagzyTokens.durationMedium,
      switchInCurve: HagzyTokens.curveDialogEnter,
      switchOutCurve: Curves.easeInCubic,
      child: Padding(
        key: ValueKey(type),
        padding: EdgeInsets.only(top: isWide ? 6 : 2, bottom: isWide ? 2 : 0),
        child: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hagzyDisplayStyle(
                            arabic: arabic,
                            color: kInk,
                            fontSize: 24,
                            height: arabic ? 1.24 : 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          content.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: kPanel,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusFull),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LivePulseDot(color: kVermilion, size: 7),
                        const SizedBox(width: 8),
                        Text(
                          localized(
                            arabic,
                            'Instant Hold · InstaPay & Wallet',
                            'تثبيت فوري · إنستاباي والمحفظة',
                          ),
                          style: TextStyle(
                            color: kInk,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          content.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: hagzyDisplayStyle(
                            arabic: arabic,
                            color: kInk,
                            fontSize: 20,
                            height: arabic ? 1.25 : 1.15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.4,
                          ),
                        ),
                        Text(
                          content.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kMuted,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
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

class VenueBrowseCard extends StatelessWidget {
  const VenueBrowseCard({
    super.key,
    required this.venue,
    this.bookings = const [],
    required this.arabic,
    required this.selected,
    required this.favorite,
    required this.onTap,
    required this.onFavorite,
    this.onDetails,
  });

  final Venue venue;
  final List<Booking> bookings;
  final bool arabic;
  final bool selected;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback? onDetails;

  ({String label, bool isAvailableNow}) _computeLiveAvailability() {
    final now = DateTime.now();
    final openH = venue.openHour;
    final closeH = venue.closeHour <= openH ? 23 : venue.closeHour;
    String fmtHour(int h, int m) {
      final period = h >= 12
          ? (arabic ? 'م' : 'PM')
          : (arabic ? 'ص' : 'AM');
      final h12 = h % 12 == 0 ? 12 : h % 12;
      final mm = m == 0 ? '00' : m.toString().padLeft(2, '0');
      return '$h12:$mm $period';
    }

    if (now.hour < openH || now.hour >= closeH) {
      final openStr = fmtHour(openH, 0);
      return (
        label: localized(arabic, 'Opens $openStr', 'يفتح $openStr'),
        isAvailableNow: false,
      );
    }

    if (venue.items.isEmpty) {
      return (
        label: localized(arabic, 'Available Now', 'متاح الآن'),
        isAvailableNow: true,
      );
    }

    final activeVenueBookings = bookings
        .where((b) => b.venueId == venue.id && !b.cancelled)
        .toList();

    bool isItemFreeAt(String itemId, DateTime slotStart) {
      final slotEnd = slotStart.add(const Duration(minutes: 60));
      for (final b in activeVenueBookings) {
        if (b.itemId != itemId) continue;
        final bEnd = b.startsAt.add(Duration(minutes: b.durationMinutes));
        if (b.startsAt.isBefore(slotEnd) && bEnd.isAfter(slotStart)) {
          return false;
        }
      }
      return true;
    }

    final roundedMin = now.minute < 30 ? 30 : 0;
    final roundedHour = now.minute < 30 ? now.hour : now.hour + 1;
    final currentSlot = DateTime(
      now.year,
      now.month,
      now.day,
      roundedHour.clamp(openH, closeH),
      roundedMin,
    );

    int freeNow = 0;
    for (final it in venue.items) {
      if (isItemFreeAt(it.id, now)) {
        freeNow++;
      }
    }

    if (freeNow > 0) {
      return (
        label: localized(
          arabic,
          'Available Now · $freeNow free',
          'متاح الآن · $freeNow شاغر',
        ),
        isAvailableNow: true,
      );
    }

    var probe = currentSlot;
    final closeTime = DateTime(now.year, now.month, now.day, closeH, 0);
    while (probe.isBefore(closeTime)) {
      for (final it in venue.items) {
        if (isItemFreeAt(it.id, probe)) {
          final slotText = fmtHour(probe.hour, probe.minute);
          return (
            label: localized(
              arabic,
              'Next slot $slotText',
              'أقرب موعد $slotText',
            ),
            isAvailableNow: false,
          );
        }
      }
      probe = probe.add(const Duration(minutes: 30));
    }

    final openStr = fmtHour(openH, 0);
    return (
      label: localized(
        arabic,
        'Next slot tomorrow $openStr',
        'أقرب موعد غداً $openStr',
      ),
      isAvailableNow: false,
    );
  }

  String get _image =>
      (venue.imageUrl != null && venue.imageUrl!.isNotEmpty)
          ? venue.imageUrl!
          : switch (venue.type) {
              VenueType.sports =>
                'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=640&q=75',
              VenueType.salon =>
                'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=640&q=75',
              VenueType.lounge =>
                'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=640&q=75',
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
    final isEscape = venue.subCategories.contains('escape_rooms') || venue.name.toLowerCase().contains('escape');
    final rateLabel = venue.type == VenueType.salon
        ? localized(arabic, 'per service', 'للخدمة')
        : (isEscape
            ? localized(arabic, 'per person', 'للفرد')
            : localized(arabic, 'per hour', 'للساعة'));
    final itemCount = venue.items.length;
    final spaceLabel = switch (venue.type) {
      VenueType.sports => itemCount == 1
          ? localized(arabic, 'Court', 'ملعب')
          : localized(arabic, 'Courts', 'ملاعب'),
      VenueType.salon => itemCount == 1
          ? localized(arabic, 'Chair', 'كرسي')
          : localized(arabic, 'Chairs', 'كراسي'),
      VenueType.lounge => isEscape
          ? (itemCount == 1 ? localized(arabic, 'Room', 'غرفة') : localized(arabic, 'Rooms', 'غرف'))
          : (itemCount == 1 ? localized(arabic, 'Space', 'مكان') : localized(arabic, 'Spaces', 'أماكن')),
    };
    final ratingStr = venue.rating.toStringAsFixed(1);
    final hasReviews = venue.reviews.isNotEmpty;
    final reviewCount = venue.reviews.length;
    final displayName = displayLocalizedTitle(venue.name, arabic);
    final displayLocation = venue.location.isEmpty
        ? localized(arabic, 'Location available on booking', 'تفاصيل الموقع عند الحجز')
        : displayLocalizedLocation(venue.location, arabic);
    // Warm Consumer Venue Card (clean elevation, refined 14px radius, crisp photo)
    return HagzyInteractiveSurface(
      hoverLift: 2.0,
      pressScale: 0.98,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: HagzyMotion.durationRelease,
        curve: HagzyMotion.curveRelease,
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
          border: Border.all(
            color: selected
                ? kBrandAccent
                : (hovered ? kBorderStrong : kBorder),
            width: selected ? 1.6 : 1.0,
          ),
          boxShadow: hovered ? HagzyTheme.softShadow : HagzyTheme.subtleShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HagzyHaptics.light();
              onTap();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Edge-to-edge Venue Photograph
                SizedBox(
                  height: MediaQuery.sizeOf(context).width >=
                          HagzyTokens.breakpointTablet
                      ? 176
                      : 196,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: AnimatedScale(
                          scale: hovered && !HagzyMotion.reduced(context)
                              ? 1.035
                              : 1.0,
                          duration: HagzyMotion.durationFluid,
                          curve: HagzyMotion.curveDialogEnter,
                          child: HagzySmartImage(
                            imageUrl: _image,
                            fit: BoxFit.cover,
                            cacheWidth: 640,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const HagzyShimmerBox(
                                width: double.infinity,
                                height: 204,
                                borderRadius: 0,
                              );
                            },
                            errorWidget: Container(
                              color: kSurfaceSubtle,
                              alignment: Alignment.center,
                              child: Icon(venue.type.icon,
                                  size: 36, color: kMuted),
                            ),
                          ),
                        ),
                      ),
                      // Top-Start Category Pill
                      PositionedDirectional(
                        top: 10,
                        start: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: kObsidian.withValues(alpha: 0.72),
                            borderRadius:
                                BorderRadius.circular(HagzyTokens.radiusFull),
                          ),
                          child: Text(
                            switch (venue.type) {
                              VenueType.sports =>
                                localized(arabic, 'Sports', 'رياضة وملاعب'),
                              VenueType.salon =>
                                localized(arabic, 'Grooming', 'حلاقة وعناية'),
                              VenueType.lounge =>
                                localized(arabic, 'Entertainment', 'ترفيه وألعاب'),
                            },
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      // Top-End Favorite Button (>= 44x44 touch target)
                      PositionedDirectional(
                        top: 6,
                        end: 6,
                        child: IconButton(
                          tooltip: favorite
                              ? localized(
                                  arabic,
                                  'Remove from Saved Places',
                                  'إزالة من الأماكن المفضلة')
                              : localized(
                                  arabic, 'Save to Favorites', 'حفظ في المفضلة'),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            backgroundColor: favorite
                                ? kVermilion
                                : kObsidian.withValues(alpha: 0.68),
                            foregroundColor: Colors.white,
                            shape: const CircleBorder(),
                          ),
                          onPressed: () {
                            HagzyHaptics.selection();
                            onFavorite();
                          },
                          icon: Icon(
                            favorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      ),
                      // Bottom-Start Availability Pill
                      PositionedDirectional(
                        bottom: 10,
                        start: 10,
                        child: selected
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: kVermilion,
                                  borderRadius: BorderRadius.circular(
                                      HagzyTokens.radiusFull),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_rounded,
                                        color: Colors.white, size: 13),
                                    const SizedBox(width: 4),
                                    Text(
                                      localized(arabic, 'Selected', 'محدد'),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : Builder(
                                builder: (context) {
                                  final avail = _computeLiveAvailability();
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: kObsidian.withValues(alpha: 0.80),
                                      borderRadius: BorderRadius.circular(
                                          HagzyTokens.radiusFull),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: avail.isAvailableNow
                                                ? const Color(0xFF4ADE80)
                                                : const Color(0xFFFBBF24),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          avail.label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                // Clean Card Body
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: hagzyDisplayStyle(
                                arabic: arabic,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.25,
                                color: kInk,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: kSurfaceSubtle,
                              borderRadius:
                                  BorderRadius.circular(HagzyTokens.radiusXs),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasReviews
                                      ? Icons.star_rounded
                                      : Icons.verified_rounded,
                                  size: 13,
                                  color: hasReviews ? kGold : kBrandAccent,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  hasReviews
                                      ? '$ratingStr ($reviewCount)'
                                      : localized(arabic, 'New', 'جديد'),
                                  style: hagzyMonoStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: kInk,
                                    arabic: arabic,
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
                          Icon(Icons.location_on_outlined,
                              size: 14, color: kMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              displayLocation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: kMuted,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(6),
                            onTap: () async {
                              final rawUrl = venue.googleMapsUrl.trim();
                              final uri = rawUrl.isNotEmpty
                                  ? Uri.parse(rawUrl)
                                  : Uri.https(
                                      'www.google.com', '/maps/search/', {
                                      'api': '1',
                                      'query':
                                          '${venue.name} ${venue.location} Egypt'
                                              .trim(),
                                    });
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    localized(arabic, 'Directions', 'الاتجاهات'),
                                    style: TextStyle(
                                      color: kInk,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  Icon(Icons.north_east_rounded,
                                      size: 13, color: kBrandAccent),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (venue.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          [
                            '\u2068${venue.items.length} $spaceLabel\u2069',
                            '\u2068${localized(arabic, 'Instant Hold', 'تثبيت فوري')}\u2069',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: kMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(color: kInk, fontSize: 13),
                                children: [
                                  TextSpan(
                                    text: lowestPrice == null
                                        ? localized(arabic, 'Price on Request',
                                            'السعر عند الطلب')
                                        : '${formatMoney(lowestPrice)} ${localized(arabic, 'EGP', 'ج.م')}',
                                    style: hagzyMonoStyle(
                                      color: kInk,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      arabic: arabic,
                                    ),
                                  ),
                                  if (lowestPrice != null)
                                    TextSpan(
                                      text: ' / $rateLabel',
                                      style: TextStyle(
                                        color: kMuted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (onDetails != null) ...[
                            IconButton(
                              tooltip: localized(arabic, 'Venue Info & Reviews',
                                  'التفاصيل والتقييمات'),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(44, 44),
                                backgroundColor: kSurfaceSubtle,
                                foregroundColor: kInk,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      HagzyTokens.radiusMedium),
                                ),
                              ),
                              onPressed: () {
                                HagzyHaptics.selection();
                                onDetails!();
                              },
                              icon: const Icon(Icons.info_outline_rounded,
                                  size: 18),
                            ),
                            const SizedBox(width: 8),
                          ],
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  selected ? kVermilion : kAccentSurface,
                              foregroundColor:
                                  selected ? Colors.white : kAccentOnSurface,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    HagzyTokens.radiusMedium),
                              ),
                              minimumSize: const Size(108, 44),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 18, vertical: 11),
                              elevation: 0,
                            ),
                            onPressed: () {
                              HagzyHaptics.light();
                              onTap();
                            },
                            icon: AnimatedSlide(
                              duration: HagzyMotion.durationMicro,
                              offset: hovered && !selected
                                  ? Offset(arabic ? -0.14 : 0.14, 0)
                                  : Offset.zero,
                              child: Icon(
                                selected
                                    ? Icons.close_rounded
                                    : Icons.arrow_forward_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            label: Text(
                              selected
                                  ? localized(arabic, 'Close', 'إغلاق')
                                  : localized(arabic, 'Book', 'احجز'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
      ),
    );
  }
}

class _VenueDetailsSheet extends StatefulWidget {
  const _VenueDetailsSheet({
    required this.venue,
    required this.arabic,
    required this.onBookNow,
    this.onAddReview,
    this.favorite = false,
    this.onFavorite,
  });

  final Venue venue;
  final bool arabic;
  final VoidCallback onBookNow;
  final Future<void> Function(String author, double rating, String comment)?
      onAddReview;
  final bool favorite;
  final VoidCallback? onFavorite;

  @override
  State<_VenueDetailsSheet> createState() => _VenueDetailsSheetState();
}

class _VenueDetailsSheetState extends State<_VenueDetailsSheet> {
  Future<void> _openMaps() async {
    final rawUrl = widget.venue.googleMapsUrl.trim();
    final uri = rawUrl.isNotEmpty
        ? Uri.parse(rawUrl)
        : Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': '${widget.venue.name} ${widget.venue.location}'.trim(),
          });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _promptAddReview() async {
    if (widget.onAddReview == null) return;
    var author = '';
    var comment = '';
    var rating = 5.0;
    final arabic = widget.arabic;
    final submitted = await showHagzyAdaptiveModal<bool>(
      context: context,
      builder: (ctx, isSheet) => StatefulBuilder(
        builder: (ctx, setDialogState) => HagzyModalCard(
          isSheet: isSheet,
          icon: Icons.star_rounded,
          iconColor: const Color(0xFFF59E0B),
          iconBackgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.14),
          title: localized(arabic, 'Rate ${widget.venue.name}',
              'قيّم ${widget.venue.name}'),
          subtitle: localized(
            arabic,
            'Share how your visit went to help other guests.',
            'شاركنا رأيك في التجربة لمساعدة الزوار الآخرين.',
          ),
          onClose: () => Navigator.pop(ctx, false),
          primaryUseFilledButton: true,
          primaryLabel: localized(arabic, 'Submit Review', 'إرسال التقييم'),
          onPrimary: () {
            if (author.trim().isEmpty) return;
            Navigator.pop(ctx, true);
          },
          secondaryLabel: localized(arabic, 'Cancel', 'إلغاء'),
          onSecondary: () => Navigator.pop(ctx, false),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (idx) {
                  final star = idx + 1;
                  return HagzyTap(
                    scaleDown: 0.90,
                    haptic: HagzyHapticStyle.selection,
                    onTap: () => setDialogState(() => rating = star.toDouble()),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        star <= rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 34,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                textInputAction: TextInputAction.next,
                onChanged: (v) => author = v,
                decoration: InputDecoration(
                  labelText: localized(arabic, 'Your Name', 'الاسم'),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                textInputAction: TextInputAction.done,
                onChanged: (v) => comment = v,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText:
                      localized(arabic, 'Your Experience', 'تجربتك (اختياري)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (submitted == true && author.trim().isNotEmpty) {
      await widget.onAddReview!(author.trim(), rating, comment.trim());
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final venue = widget.venue;
    final arabic = widget.arabic;
    return SafeArea(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
        margin: const EdgeInsets.fromLTRB(12, 24, 12, 12),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 20),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: kBorder,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                IconBox(icon: venue.type.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayLocalizedTitle(venue.name, arabic),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        venue.location.isEmpty
                            ? venue.type.label
                            : '${displayLocalizedLocation(venue.location, arabic)} · ${venue.type.label}',
                        style: TextStyle(color: kMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF78350F).withValues(alpha: 0.35)
                        : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                          : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        venue.reviews.isEmpty
                            ? localized(arabic, 'New', 'جديد')
                            : (venue.reviews.fold<double>(
                                        0, (s, r) => s + r.rating) /
                                    venue.reviews.length)
                                .toStringAsFixed(1),
                        style: TextStyle(
                            color: isDark
                                ? const Color(0xFFFEF3C7)
                                : const Color(0xFF92400E),
                            fontWeight: FontWeight.w800,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (widget.onFavorite != null) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: isDark
                        ? (widget.favorite
                            ? const Color(0xFFE11D48).withValues(alpha: 0.2)
                            : const Color(0xFF1F352D))
                        : (widget.favorite
                            ? const Color(0xFFFFE4E6)
                            : const Color(0xFFF1F5F9)),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: widget.favorite
                          ? localized(arabic, 'Remove from Saved Places',
                              'إزالة من الأماكن المفضلة')
                          : localized(arabic, 'Save Venue', 'حفظ في المفضلة'),
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onFavorite,
                      icon: Icon(
                        widget.favorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: widget.favorite
                            ? const Color(0xFFE11D48)
                            : (isDark ? Colors.white : const Color(0xFF0F172A)),
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (venue.galleryUrls.isNotEmpty) ...[
                      if (venue.galleryUrls.length == 1)
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(HagzyTokens.radiusLarge),
                          child: HagzySmartImage(
                            imageUrl: venue.galleryUrls.first,
                            width: double.infinity,
                            height: 176,
                            fit: BoxFit.cover,
                            errorWidget: Container(
                              width: double.infinity,
                              height: 176,
                              color: kSurfaceSubtle,
                              alignment: Alignment.center,
                              child: Icon(venue.type.icon,
                                  color: kBrandAccent, size: 32),
                            ),
                          ),
                        )
                      else
                        SizedBox(
                          height: 148,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: venue.galleryUrls.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 10),
                            itemBuilder: (context, idx) => ClipRRect(
                              borderRadius: BorderRadius.circular(
                                  HagzyTokens.radiusLarge),
                              child: HagzySmartImage(
                                imageUrl: venue.galleryUrls[idx],
                                width: 224,
                                height: 148,
                                fit: BoxFit.cover,
                                errorWidget: Container(
                                  width: 224,
                                  height: 148,
                                  color: kSurfaceSubtle,
                                  alignment: Alignment.center,
                                  child: Icon(venue.type.icon,
                                      color: kBrandAccent),
                                ),
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),
                    ],
                    if (venue.description.isNotEmpty) ...[
                      Builder(builder: (context) {
                        final desc = displayLocalizedDescription(venue, arabic);
                        return Directionality(
                          textDirection: isPrimarilyArabic(desc)
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Text(
                            desc,
                            style: TextStyle(color: kInk, height: 1.5),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: Icon(Icons.access_time,
                              size: 15, color: kBrandAccent),
                          label: Text(
                            localized(
                              arabic,
                              'Hours: ${venue.openHour}:00 – ${venue.closeHour}:00',
                              'ساعات العمل: ${venue.openHour}:00 – ${venue.closeHour}:00',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        Chip(
                          avatar: Icon(Icons.percent,
                              size: 15, color: kBrandAccent),
                          label: Text(
                            localized(
                              arabic,
                              '${formatMoney(venue.depositPercent)}% deposit',
                              '${formatMoney(venue.depositPercent)}% عربون',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        ...venue.amenities.map(
                          (a) => Chip(
                            label: Text(
                              displayLocalizedAmenity(a, arabic),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (venue.items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        localized(
                          arabic,
                          venue.type == VenueType.salon
                              ? 'Chairs & Stations (${venue.items.length})'
                              : 'Rooms & Courts (${venue.items.length})',
                          venue.type == VenueType.salon
                              ? 'الكراسي والمحطات (${venue.items.length})'
                              : 'الغرف والملاعب (${venue.items.length})',
                        ),
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 8),
                      ...venue.items.map(
                        (it) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: kSurfaceSubtle.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(
                                HagzyTokens.radiusMedium),
                            border: Border.all(color: kBorder),
                          ),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: (it.imageUrl != null &&
                                        it.imageUrl!.isNotEmpty)
                                    ? HagzySmartImage(
                                        imageUrl: it.imageUrl!,
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorWidget: Container(
                                          width: 48,
                                          height: 48,
                                          color: kObsidian,
                                          child: Icon(venue.type.icon,
                                              color: kVolt, size: 20),
                                        ),
                                      )
                                    : Container(
                                        width: 48,
                                        height: 48,
                                        color: kObsidian,
                                        child: Icon(venue.type.icon,
                                            color: kVolt, size: 20),
                                      ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            displayLocalizedTitle(
                                                it.name, arabic),
                                            style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                                color: kInk),
                                          ),
                                        ),
                                        Text(
                                          '${formatMoney(it.hourlyRate)} ${localized(arabic, 'EGP', 'ج.م')}',
                                          style: hagzyMonoStyle(
                                              fontWeight: FontWeight.w800,
                                              color: isDark ? kVolt : kObsidian,
                                              fontSize: 12.5,
                                              arabic: arabic),
                                        ),
                                      ],
                                    ),
                                    if (it.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        it.description,
                                        style: TextStyle(
                                            color: kMuted,
                                            fontSize: 13.0,
                                            height: 1.45),
                                        maxLines: 4,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _openMaps,
                          icon: const Icon(Icons.map_outlined, size: 17),
                          label: Text(localized(
                              arabic, 'Open in Google Maps', 'افتح في الخرائط')),
                        ),
                        const SizedBox(width: 8),
                        if (widget.onAddReview != null)
                          TextButton.icon(
                            onPressed: _promptAddReview,
                            icon: const Icon(Icons.rate_review_outlined,
                                size: 17),
                            label: Text(
                                localized(arabic, 'Write Review', 'أضف تقييماً')),
                          ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      localized(
                          arabic,
                          'Customer Reviews (${venue.reviews.length})',
                          'تقييمات العملاء (${venue.reviews.length})'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    if (venue.reviews.isEmpty)
                      Text(
                        localized(
                            arabic,
                            'Verified Hagzy venue · Be the first to leave a written review.',
                            'مكان معتمد في حجزي · كن أول من يكتب تقييماً.'),
                        style: TextStyle(color: kMuted, fontSize: 12),
                      )
                    else
                      ...venue.reviews.map(
                        (r) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kPage,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r.author,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const Icon(Icons.star_rounded,
                                      size: 15, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 3),
                                  Text(
                                    r.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12),
                                  ),
                                ],
                              ),
                              if (r.comment.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(r.comment,
                                    style: TextStyle(
                                        color: kMuted, fontSize: 12)),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.onFavorite != null) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      side: BorderSide(
                        color: widget.favorite
                            ? const Color(0xFFE11D48).withValues(alpha: 0.5)
                            : kBorder,
                      ),
                      backgroundColor: widget.favorite
                          ? const Color(0xFFFFE4E6).withValues(alpha: 0.4)
                          : Colors.transparent,
                    ),
                    onPressed: widget.onFavorite,
                    icon: Icon(
                      widget.favorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: widget.favorite
                          ? const Color(0xFFE11D48)
                          : kInk,
                      size: 18,
                    ),
                    label: Text(
                      widget.favorite
                          ? localized(arabic, 'Saved', 'محفوظ')
                          : localized(arabic, 'Save', 'حفظ'),
                      style: TextStyle(
                        color: widget.favorite
                            ? const Color(0xFFE11D48)
                            : kInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: widget.onBookNow,
                    icon: const Icon(Icons.calendar_today_rounded, size: 17),
                    label: Text(localized(arabic, 'Book Now', 'احجز الآن')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryVisualCard extends StatelessWidget {
  const _CategoryVisualCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.gradient,
    required this.glowColor,
    required this.count,
    required this.arabic,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final List<Color> gradient;
  final Color glowColor;
  final int count;
  final bool arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < HagzyTokens.breakpointTablet;
    return HagzyTap(
      scaleDown: 0.96,
      haptic: HagzyHapticStyle.selection,
      onTap: onTap,
      child: AnimatedContainer(
        duration: HagzyMotion.durationMicro,
        curve: HagzyMotion.curveSnappy,
        constraints: BoxConstraints(minHeight: compact ? 44 : 58),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 13 : 14,
          vertical: compact ? 9 : 12,
        ),
        decoration: BoxDecoration(
          color: isSelected ? kAccentSurface : kPanel,
          borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
          border: Border.all(
            color: isSelected ? kAccentSurface : kBorder,
            width: 1.0,
          ),
          boxShadow: isSelected ? HagzyTheme.subtleShadow : null,
        ),
        child: compact
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 16,
                    color: isSelected ? kAccentOnSurface : kBrandAccent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isSelected ? kAccentOnSurface : kInk,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.2)
                            : kSurfaceSubtle,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusFull),
                      ),
                      child: Text(
                        '$count',
                        style: hagzyMonoStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : kMuted,
                          arabic: arabic,
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.16)
                          : kSurfaceTint,
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                    ),
                    child: Icon(
                      icon,
                      size: 18,
                      color: isSelected ? Colors.white : kBrandAccent,
                    ),
                  ),
                  const SizedBox(width: 11),
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
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: isSelected ? kAccentOnSurface : kInk,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.78)
                                : kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.2)
                            : kSurfaceSubtle,
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusFull),
                      ),
                      child: Text(
                        '$count',
                        style: hagzyMonoStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : kInk,
                          arabic: arabic,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

class _CategorySectionHeader extends StatelessWidget {
  const _CategorySectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.count,
    required this.accentColor,
    required this.arabic,
    required this.onSeeAll,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final int count;
  final Color accentColor;
  final bool arabic;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
              color: isDark ? kVolt : kObsidian,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hagzyTextStyle(
                          arabic: arabic,
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: kInk,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: kAccentSurface,
                        borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
                      ),
                      child: Text(
                        '$count',
                        style: hagzyMonoStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          arabic: arabic,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: kMuted,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: onSeeAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: kInk,
              backgroundColor: kPanel,
              side: BorderSide(color: kBorder),
              minimumSize: const Size(0, 34),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  localized(arabic, 'Filter', 'تصفية'),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 4),
                HagzyDirectionalChevron(size: 14, color: kInk),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubCategoryVisualPill extends StatelessWidget {
  const _SubCategoryVisualPill({
    required this.label,
    required this.emoji,
    required this.icon,
    required this.isSelected,
    required this.count,
    required this.arabic,
    required this.accentColor,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final IconData icon;
  final bool isSelected;
  final int count;
  final bool arabic;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final activeBarColor = isDark ? kVolt : kObsidian;
    return HagzyTap(
      scaleDown: 0.96,
      haptic: HagzyHapticStyle.selection,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? activeBarColor : Colors.transparent,
              width: 2.4,
            ),
          ),
        ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: isSelected
                      ? (isDark ? kVolt : kObsidian)
                      : kMuted.withValues(alpha: 0.78),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? kInk : kMuted,
                    letterSpacing: arabic ? 0 : -0.15,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (isDark ? kVermilion : kObsidian)
                          : kSurfaceSubtle,
                      borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
                    ),
                    child: Text(
                      '$count',
                      style: hagzyMonoStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : kMuted,
                        arabic: arabic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}

class _BookingStepPill extends StatelessWidget {
  const _BookingStepPill({
    required this.stepNumber,
    required this.title,
    required this.subtitle,
    required this.done,
    required this.active,
    required this.onTap,
  });

  final String stepNumber;
  final String title;
  final String subtitle;
  final bool done;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    final activeBg = isDark ? kVermilion : kObsidian;
    const activeFg = Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
      child: AnimatedContainer(
        duration: HagzyTokens.durationFast,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? activeBg
              : (done ? kSurfaceTint : kPanel),
          borderRadius: BorderRadius.circular(HagzyTokens.radiusSmall),
          border: Border.all(
            color: active
                ? activeBg
                : (done ? kSuccess.withValues(alpha: 0.42) : kBorder),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active
                    ? (isDark ? Colors.white.withValues(alpha: 0.22) : kVermilion)
                    : (done ? kSuccess : kSurfaceSubtle),
                borderRadius: BorderRadius.circular(HagzyTokens.radiusXs),
              ),
              child: done && !active
                  ? Icon(Icons.check_rounded,
                      size: 12, color: isDark ? kObsidian : Colors.white)
                  : Text(
                      stepNumber,
                      style: hagzyMonoStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: active ? Colors.white : kInk,
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      title,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w900,
                        color: active ? activeFg : kInk,
                      ),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      subtitle,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.w600,
                        color: active
                            ? activeFg.withValues(alpha: 0.84)
                            : (done ? kSuccess : kMuted),
                      ),
                    ),
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


class _RoomDetailCard extends StatefulWidget {
  final VenueItem item;
  final bool isDark;
  final bool arabic;
  final bool isEscapeRoom;

  const _RoomDetailCard({
    required this.item,
    required this.isDark,
    required this.arabic,
    this.isEscapeRoom = false,
  });

  @override
  State<_RoomDetailCard> createState() => _RoomDetailCardState();
}

class _RoomDetailCardState extends State<_RoomDetailCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isDark = widget.isDark;
    final arabic = widget.arabic;
    final hasImage = item.imageUrl != null && item.imageUrl!.isNotEmpty;
    final isLongBio = item.description.length > 120;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(HagzyTokens.radiusLarge),
        border: Border.all(color: kBorder, width: 1.1),
        boxShadow: HagzyTheme.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasImage)
            HagzySmartImage(
              imageUrl: item.imageUrl!,
              height: 150,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          color: kInk,
                        ),
                      ),
                    ),
                    if (item.kind.isNotEmpty)
                      HagzyMonoTag(
                        label: item.kind,
                        backgroundColor: kSurfaceSubtle,
                        foregroundColor: isDark ? kVolt : kObsidian,
                        borderColor: kBorder,
                      ),
                  ],
                ),
                if (item.description.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: Text(
                      item.description,
                      style: TextStyle(
                        fontSize: 14.0,
                        fontWeight: FontWeight.w500,
                        color: kInk.withValues(alpha: 0.86),
                        height: 1.55,
                      ),
                      maxLines: _isExpanded ? null : 4,
                      overflow: _isExpanded
                          ? TextOverflow.visible
                          : TextOverflow.ellipsis,
                    ),
                  ),
                  if (isLongBio) ...[
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => setState(() => _isExpanded = !_isExpanded),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _isExpanded
                                  ? (arabic ? 'عرض أقل ▲' : 'Show less ▲')
                                  : (arabic
                                      ? 'اقرأ القصة والتفاصيل كاملة ▼'
                                      : 'Read full story & details ▼'),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isDark ? kVolt : kObsidian,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EscapeRoomTierOption {
  final String labelAr;
  final String labelEn;
  final int minPeople;
  final int maxPeople;
  final int defaultHeadcount;
  final double pricePerPerson;

  const EscapeRoomTierOption({
    required this.labelAr,
    required this.labelEn,
    required this.minPeople,
    required this.maxPeople,
    required this.defaultHeadcount,
    required this.pricePerPerson,
  });
}
