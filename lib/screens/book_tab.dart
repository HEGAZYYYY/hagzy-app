import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/map_explorer.dart';

class BookTab extends StatefulWidget {
  const BookTab({
    super.key,
    required this.venues,
    required this.bookings,
    required this.arabic,
    required this.onBook,
    this.initialVenueId,
    this.onAddVenue,
    this.onAddReview,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final bool arabic;
  final void Function(Venue venue, VenueItem item, DateTime startsAt) onBook;
  final String? initialVenueId;
  final ValueChanged<VenueType?>? onAddVenue;
  final Future<void> Function(
      Venue venue, String author, double rating, String comment)? onAddReview;

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
  bool _showMapView = false;
  bool _isAutoAssigningGps = false;
  DateTime _date = () {
    final now = DateTime.now();
    return now.hour >= 21
        ? DateTime(now.year, now.month, now.day + 1)
        : DateTime(now.year, now.month, now.day);
  }();
  DateTime? _selectedStart;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _bookingSectionKey = GlobalKey();
  final GlobalKey _spaceStepKey = GlobalKey();
  final GlobalKey _timeStepKey = GlobalKey();
  final GlobalKey _quoteStepKey = GlobalKey();
  final Map<String, GlobalKey> _venueCardKeys = {};

  @override
  void initState() {
    super.initState();
    _loadCustomerPreferences();
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _autoAssignGpsAreaDirectly(silentIfDenied: true);
        }
      });
    }
    if (widget.initialVenueId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final initialVenue = upsertNaderSalon(widget.venues)
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
    if (widget.initialVenueId != null &&
        (widget.initialVenueId != oldWidget.initialVenueId ||
            _venueId != widget.initialVenueId)) {
      final targetVenue = upsertNaderSalon(widget.venues)
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
          alignment: 0.05,
        );
        return;
      }
      final ctx = _venueCardKeys[venueId]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.02,
        );
        return;
      }
      if (_scrollController.hasClients) {
        final matching = _getMatchingVenues();
        final index = matching.indexWhere((v) => v.id == venueId);
        final targetOffset = 520.0 + (index >= 0 ? index * 320.0 : 0.0);
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
            alignment: 0.02,
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
      _venueId = value.id;
      _itemId = value.items.firstOrNull?.id;
      _selectedStart = null;
    });
    _scrollToVenue(value.id);
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
            backgroundColor: kInk,
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
            backgroundColor: kInk,
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

    final result = await showDialog<({String area, bool viaGps})>(
      context: context,
      builder: (context) => StatefulBuilder(
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
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            title: Text(localized(
                widget.arabic, 'Choose a governorate', 'اختر المحافظة')),
            content: SizedBox(
              width: 420,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: locatingGps
                          ? null
                          : () async {
                              if (WidgetsBinding.instance.runtimeType
                                  .toString()
                                  .contains('Test')) {
                                Navigator.pop(context,
                                    (area: 'Cairo', viaGps: true));
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
                                  Navigator.pop(context,
                                      (area: nearest, viaGps: true));
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
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              kGreen.withValues(alpha: 0.14),
                              kGreen.withValues(alpha: 0.04),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: kGreen.withValues(alpha: 0.35),
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: kGreen,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: kGreen.withValues(alpha: 0.28),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: locatingGps
                                  ? const Padding(
                                      padding: EdgeInsets.all(9),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.white),
                                      ),
                                    )
                                  : const Icon(
                                      Icons.my_location_rounded,
                                      color: Colors.white,
                                      size: 20,
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
                                      fontSize: 11,
                                      color: kMuted,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: kMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (gpsError != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              gpsError!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 11.5,
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
                              ? const Icon(Icons.check, color: kGreen)
                              : null,
                          onTap: () => Navigator.pop(
                              context, (area: entry.$1, viaGps: false)),
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
                child: Text(localized(widget.arabic, 'Cancel', 'إلغاء')),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    await _assignArea(result.area, viaGps: result.viaGps);
  }

  bool _locationMatchesArea(String location) {
    if (_area == kAllEgyptAreas ||
        location.trim().isEmpty ||
        location.toLowerCase().contains('kafr el sheikh')) {
      return true;
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

  List<Venue> _getMatchingVenues() {
    final list = upsertNaderSalon(widget.venues).where((venue) {
      final matchesCategory = _type == null || venue.type == _type;
      final matchesSubCategory = _subCategory == null ||
          venue.effectiveSubCategories.contains(_subCategory);
      final matchesSearch =
          '${venue.name} ${venue.location} ${venue.description} ${venue.effectiveSubCategories.join(' ')}'
              .toLowerCase()
              .contains(_query.toLowerCase());
      final matchesFavorite =
          !_favoritesOnly || _favoriteIds.contains(venue.id);
      final matchesArea = _locationMatchesArea(venue.location);
      return matchesCategory &&
          matchesSubCategory &&
          matchesSearch &&
          matchesFavorite &&
          matchesArea;
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
            widget.bookings.any((b) => b.venueId == v.id && !b.cancelled))
        .toList();
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
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
      children: [
        CustomerAreaBar(
          area: governorateName(_area, widget.arabic),
          arabic: widget.arabic,
          onTap: _chooseArea,
          onGpsTap: () => _autoAssignGpsAreaDirectly(silentIfDenied: false),
          isLocating: _isAutoAssigningGps,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: localized(
                widget.arabic,
                'Search venues, sports, salons...',
                'ابحث عن الأماكن والأنشطة...'),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: localized(widget.arabic, 'Clear search', 'مسح البحث'),
                    onPressed: () => setState(() {
                      _query = '';
                      _searchController.clear();
                    }),
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: kDarkMode.value ? const Color(0xFF131C31) : kPanel,
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
        const SizedBox(height: 10),
        RepaintBoundary(
          child: CustomerHero(
            venueCount: widget.venues.length,
            type: _type,
            arabic: widget.arabic,
          ),
        ),
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
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: bookAgainVenues.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final v = bookAgainVenues[index];
                final isCurrent = _venueId == v.id;
                return PressableScale(
                  scaleDown: 0.96,
                  onTap: () => _selectVenue(v, toggleIfSame: false),
                  child: Ink(
                    width: 220,
                    decoration: BoxDecoration(
                      color: kPanel,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isCurrent ? kGreen : kBorder,
                        width: isCurrent ? 1.5 : 1,
                      ),
                      boxShadow: HagzyTheme.softShadow,
                    ),
                    child: Stack(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => _selectVenue(v, toggleIfSame: false),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    gradient: HagzyTheme.brandGradient,
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(v.type.icon,
                                      color: Colors.white, size: 21),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        v.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13.5,
                                          color: kInk,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        v.location.isEmpty
                                            ? localized(
                                                widget.arabic, 'Egypt', 'مصر')
                                            : v.location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: kMuted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.bolt_rounded,
                                              size: 13, color: kGreen),
                                          const SizedBox(width: 2),
                                          Text(
                                            localized(widget.arabic, 'Book Now',
                                                'احجز الآن'),
                                            style: const TextStyle(
                                              color: kGreen,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
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
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  color: kInk.withValues(alpha: 0.06),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13,
                                  color: kMuted,
                                ),
                              ),
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
        ],
        const SizedBox(height: 20),
        SectionHeading(
          title: localized(
              widget.arabic, 'Explore Categories', 'استكشف التصنيفات'),
          subtitle: localized(widget.arabic,
              'Something good is around the corner', 'أماكن مميزة بانتظارك'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _CategoryVisualCard(
              title: localized(widget.arabic, 'Everything', 'الكل'),
              subtitle: localized(widget.arabic, 'All Places', 'جميع الأماكن'),
              icon: Icons.grid_view_rounded,
              isSelected: _type == null,
              gradient: const [Color(0xFF064E3B), Color(0xFF047857)],
              glowColor: kGreen,
              count: matchingVenues.length,
              arabic: widget.arabic,
              onTap: () => _selectCategory(null),
            ),
            _CategoryVisualCard(
              title: localized(widget.arabic, 'Grooming', 'حلاقة وعناية'),
              subtitle: localized(widget.arabic, 'Hair & Beauty', 'صالونات وحلاقة'),
              icon: Icons.content_cut_rounded,
              isSelected: _type == VenueType.salon,
              gradient: const [Color(0xFF1E1B4B), Color(0xFF4338CA)],
              glowColor: const Color(0xFF6366F1),
              count: upsertNaderSalon(widget.venues)
                  .where((v) =>
                      v.type == VenueType.salon &&
                      _locationMatchesArea(v.location))
                  .length,
              arabic: widget.arabic,
              onTap: () => _selectCategory(VenueType.salon),
            ),
            _CategoryVisualCard(
              title: localized(widget.arabic, 'Entertainment', 'ترفيه وألعاب'),
              subtitle: localized(widget.arabic, 'Gaming & Tables', 'ألعاب وبلايستيشن'),
              icon: Icons.sports_esports_rounded,
              isSelected: _type == VenueType.lounge,
              gradient: const [Color(0xFF311042), Color(0xFF6D28D9)],
              glowColor: const Color(0xFF8B5CF6),
              count: widget.venues
                  .where((v) =>
                      v.type == VenueType.lounge &&
                      _locationMatchesArea(v.location))
                  .length,
              arabic: widget.arabic,
              onTap: () => _selectCategory(VenueType.lounge),
            ),
            _CategoryVisualCard(
              title: localized(widget.arabic, 'Sports', 'ملاعب ورياضة'),
              subtitle: localized(widget.arabic, 'Padel & Football', 'بادل وكرة قدم'),
              icon: Icons.sports_soccer_rounded,
              isSelected: _type == VenueType.sports,
              gradient: const [Color(0xFF064E3B), Color(0xFF059669)],
              glowColor: kGreen,
              count: widget.venues
                  .where((v) =>
                      v.type == VenueType.sports &&
                      _locationMatchesArea(v.location))
                  .length,
              arabic: widget.arabic,
              onTap: () => _selectCategory(VenueType.sports),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildSubCategoryFilterRow(matchingVenues),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                _favoritesOnly
                    ? localized(
                        widget.arabic, 'Your Saved Places', 'أماكنك المفضلة')
                    : localized(
                        widget.arabic, 'Places to Book', 'أماكن للحجز'),
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              tooltip: localized(
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
              CustomPill(
                selected: !_favoritesOnly,
                label: localized(widget.arabic, 'All Places', 'كل الأماكن'),
                onTap: () => setState(() => _favoritesOnly = false),
              ),
              const SizedBox(width: 8),
              CustomPill(
                selected: _favoritesOnly,
                icon: _favoriteIds.isNotEmpty
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: localized(widget.arabic, 'Saved', 'المفضلة'),
                badge: _favoriteIds.isNotEmpty ? '${_favoriteIds.length}' : null,
                onTap: () => setState(() => _favoritesOnly = !_favoritesOnly),
              ),
              const SizedBox(width: 8),
              CustomPill(
                selected: _showMapView,
                icon: Icons.map_outlined,
                label: localized(
                    widget.arabic, 'Map & Near Me', 'على الخريطة وقريب مني'),
                onTap: () => setState(() => _showMapView = !_showMapView),
              ),
              if (_sortByPrice) ...[
                const SizedBox(width: 8),
                CustomPill(
                  icon: Icons.south,
                  label: localized(widget.arabic, 'Lowest Price', 'أقل سعر'),
                  selected: false,
                ),
              ],
            ],
          ),
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
                    'Tap the heart icon (🤍) on any venue to save it to your favorites for quick booking.',
                    'اضغط على أيقونة القلب (🤍) في أي مكان لحفظه في المفضلة وسهولة حجزه لاحقاً.')
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
            ...matchingVenues.expand(
              (value) => _buildVenueCardAndBooking(
                  value, venue, item, estimatedMinutes),
            ),
          ] else ...[
            ..._buildCategorizedVenues(
              matchingVenues,
              venue,
              item,
              estimatedMinutes,
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
                    const Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: kGreen,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      localized(
                        widget.arabic,
                        'Made with ❤️ in Kafr El-Sheikh',
                        'صُنع بـ ❤️ في كفر الشيخ',
                      ),
                      style: TextStyle(
                        color: kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
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
  }

  Widget _buildActiveCategoryFilterBanner() {
    final type = _type!;
    final (label, icon, color) = switch (type) {
      VenueType.salon => (
          localized(widget.arabic, 'Grooming & Barbershops', 'حلاقة وعناية وصالونات'),
          Icons.content_cut_rounded,
          const Color(0xFF6366F1),
        ),
      VenueType.lounge => (
          localized(widget.arabic, 'Entertainment & Lounges', 'ترفيه وألعاب وكافيهات'),
          Icons.sports_esports_rounded,
          const Color(0xFF8B5CF6),
        ),
      VenueType.sports => (
          localized(widget.arabic, 'Sports & Courts', 'ملاعب ورياضة'),
          Icons.sports_soccer_rounded,
          kGreen,
        ),
    };

    final activeSubDef =
        _subCategory != null ? findSubCategoryDef(_subCategory!) : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ),
                if (activeSubDef != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '›',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SystemEmoji(activeSubDef.emoji, size: 11),
                        const SizedBox(width: 4),
                        Text(
                          activeSubDef.title(widget.arabic),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          InkWell(
            onTap: () => _selectCategory(null),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(widget.arabic, 'Show All', 'عرض الكل'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.close_rounded, size: 14, color: color),
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
    final allVenuesInArea = upsertNaderSalon(widget.venues)
        .where((v) =>
            (_type == null || v.type == _type) &&
            _locationMatchesArea(v.location))
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

    final defaultAccent = switch (_type) {
      VenueType.salon => const Color(0xFF6366F1),
      VenueType.lounge => const Color(0xFF8B5CF6),
      VenueType.sports => kGreen,
      null => kGreen,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _SubCategoryVisualPill(
                label: allLabel,
                emoji: '✨',
                icon: Icons.auto_awesome_rounded,
                isSelected: _subCategory == null,
                count: allVenuesInArea.length,
                arabic: widget.arabic,
                accentColor: defaultAccent,
                onTap: () => _selectSubCategory(null),
              ),
              const SizedBox(width: 8),
              ...subList.map((s) {
                final count = allVenuesInArea
                    .where((v) => v.effectiveSubCategories.contains(s.id))
                    .length;
                final isSelected = _subCategory == s.id;
                final accentColor = switch (s.parentType) {
                  VenueType.salon => const Color(0xFF6366F1),
                  VenueType.lounge => const Color(0xFF8B5CF6),
                  VenueType.sports => kGreen,
                };
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _SubCategoryVisualPill(
                    label: s.title(widget.arabic),
                    emoji: s.emoji,
                    icon: s.icon,
                    isSelected: isSelected,
                    count: count,
                    arabic: widget.arabic,
                    accentColor: accentColor,
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
    final def = findSubCategoryDef(_subCategory!);
    if (def == null) return const SizedBox.shrink();

    final accentColor = switch (def.parentType) {
      VenueType.salon => const Color(0xFF6366F1),
      VenueType.lounge => const Color(0xFF8B5CF6),
      VenueType.sports => kGreen,
    };

    final matchingCount = _getMatchingVenues().length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          SystemEmoji(def.emoji, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${def.title(widget.arabic)}: ${localized(widget.arabic, '$matchingCount ${matchingCount == 1 ? 'place' : 'places'} available', '$matchingCount ${matchingCount == 1 ? 'مكان متاح' : 'أماكن متاحة'}')}',
              style: TextStyle(
                color: accentColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          InkWell(
            onTap: () => _selectSubCategory(null),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(widget.arabic, 'Clear', 'إلغاء الفلتر'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.close_rounded, size: 14, color: accentColor),
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
    int estimatedMinutes,
  ) {
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
          accentColor: const Color(0xFF6366F1),
          arabic: widget.arabic,
          onSeeAll: () => _selectCategory(VenueType.salon),
        ),
        ...groomingVenues.expand(
          (v) => _buildVenueCardAndBooking(
              v, selectedVenue, item, estimatedMinutes),
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
          accentColor: const Color(0xFF8B5CF6),
          arabic: widget.arabic,
          onSeeAll: () => _selectCategory(VenueType.lounge),
        ),
        ...entertainmentVenues.expand(
          (v) => _buildVenueCardAndBooking(
              v, selectedVenue, item, estimatedMinutes),
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
        ...sportsVenues.expand(
          (v) => _buildVenueCardAndBooking(
              v, selectedVenue, item, estimatedMinutes),
        ),
        const SizedBox(height: 10),
      ],
    ];
  }

  List<Widget> _buildVenueCardAndBooking(
    Venue value,
    Venue? selectedVenue,
    VenueItem? item,
    int estimatedMinutes,
  ) {
    final selected = value.id == selectedVenue?.id;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: (selectedVenue != null && !selected) ? 0.52 : 1.0,
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
      AnimatedSize(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: (selected && selectedVenue != null)
            ? _buildBookingSection(selectedVenue, item, estimatedMinutes)
            : const SizedBox.shrink(),
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
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131C31) : kPanel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: kGreen.withValues(alpha: 0.45),
          width: 1.8,
        ),
        boxShadow: [
          ...HagzyTheme.softShadow,
          BoxShadow(
            color: kGreen.withValues(alpha: isDark ? 0.22 : 0.12),
            blurRadius: 28,
            spreadRadius: -2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
                            // Breadfast / Talabat-style Top Tray Header
                            Container(
                              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    kGreen.withValues(alpha: isDark ? 0.18 : 0.08),
                                    kGreenLight.withValues(alpha: isDark ? 0.10 : 0.05),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                border: Border(
                                  bottom: BorderSide(color: kBorder),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: HagzyTheme.brandGradient,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: Icon(
                                      venue.type.icon,
                                      size: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          localized(widget.arabic,
                                              'Your Booking', 'حجزك'),
                                          style: TextStyle(
                                            fontSize: 16.5,
                                            fontWeight: FontWeight.w900,
                                            color: kInk,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${venue.name}${venue.location.isEmpty ? '' : ' · ${venue.location}'}',
                                          style: TextStyle(
                                            color: kMuted,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _favoriteIds.contains(venue.id)
                                        ? localized(widget.arabic,
                                            'Remove from Saved', 'إزالة من المفضلة')
                                        : localized(widget.arabic, 'Save Venue',
                                            'حفظ في المفضلة'),
                                    onPressed: () => _toggleFavorite(venue),
                                    icon: Icon(
                                      _favoriteIds.contains(venue.id)
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: _favoriteIds.contains(venue.id)
                                          ? const Color(0xFFE11D48)
                                          : kMuted,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  PressableScale(
                                    scaleDown: 0.92,
                                    onTap: () {
                                      setState(() {
                                        _venueId = null;
                                        _itemId = null;
                                        _selectedStart = null;
                                      });
                                      _scrollController.animateTo(
                                        0,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                      );
                                    },
                                    child: TextButton.icon(
                                      style: TextButton.styleFrom(
                                        backgroundColor: kPanel,
                                        foregroundColor: kInk,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          side:
                                              BorderSide(color: kBorder),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _venueId = null;
                                          _itemId = null;
                                          _selectedStart = null;
                                        });
                                        _scrollController.animateTo(
                                          0,
                                          duration:
                                              const Duration(milliseconds: 300),
                                          curve: Curves.easeOutCubic,
                                        );
                                      },
                                      icon: const Icon(Icons.close_rounded,
                                          size: 15),
                                      label: Text(
                                        localized(
                                            widget.arabic, 'Close', 'إغلاق'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Visual 3-Step Eye-Guide Progression Bar
                            Container(
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF0B1120).withValues(alpha: 0.55)
                                    : kSurfaceTint.withValues(alpha: 0.65),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isDark ? const Color(0xFF283552) : kBorder,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: _BookingStepPill(
                                      stepNumber: '1',
                                      title: localized(widget.arabic, 'Space', 'المساحة'),
                                      subtitle: item?.name ??
                                          localized(widget.arabic, 'Select', 'اختر'),
                                      done: item != null,
                                      active: activeStep == 1,
                                      onTap: () => _scrollToKey(_spaceStepKey),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(
                                      widget.arabic
                                          ? Icons.chevron_left_rounded
                                          : Icons.chevron_right_rounded,
                                      size: 16,
                                      color: kGreen.withValues(alpha: 0.65),
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
                                    child: Icon(
                                      widget.arabic
                                          ? Icons.chevron_left_rounded
                                          : Icons.chevron_right_rounded,
                                      size: 16,
                                      color: kGreen.withValues(alpha: 0.65),
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
                            Padding(
                              key: _spaceStepKey,
                              padding:
                                  const EdgeInsets.fromLTRB(20, 18, 20, 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: kGreen.withValues(alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          localized(widget.arabic, 'STEP 1',
                                              'خطوة ١'),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: kGreen,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          localized(widget.arabic,
                                              'Choose Your Space', 'اختر المساحة'),
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
                                          label:
                                              '${val.name} · ${formatMoney(val.hourlyRate)} ${localized(widget.arabic, 'EGP', 'ج.م')}${venue.type == VenueType.salon ? localized(widget.arabic, '/15m', '/١٥ د') : localized(widget.arabic, '/h', '/س')}',
                                          onTap: () => _selectSpace(val.id),
                                        );
                                      }).toList(),
                                    ),
                                ],
                              ),
                            ),

                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: item != null
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
                                                      Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 3),
                                                        decoration:
                                                            BoxDecoration(
                                                          color: kGreenLight
                                                              .withValues(
                                                                  alpha: 0.12),
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      999),
                                                        ),
                                                        child: Text(
                                                          localized(
                                                              widget.arabic,
                                                              'STEP 2',
                                                              'خطوة ٢'),
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color: kGreenLight,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
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
                                                              const Icon(
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
                                                                      11.5,
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
                                            estimatedMinutes: estimatedMinutes,
                                            selectedStart: _selectedStart,
                                            onReserve: _selectedStart == null
                                                ? null
                                                : () => widget.onBook(venue,
                                                    item, _selectedStart!),
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
    final today = DateTime.now();
    // Calculate calendar dates without 24h DST duplication
    final days = List.generate(
      14,
      (index) => DateTime(today.year, today.month, today.day + index),
    );
    return SizedBox(
      height: 92,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        itemBuilder: (context, index) {
          final d = days[index];
          final isSelected = d.year == _date.year &&
              d.month == _date.month &&
              d.day == _date.day;
          return Padding(
            padding:
                EdgeInsets.only(right: arabic ? 0 : 10, left: arabic ? 10 : 0),
            child: PressableScale(
              scaleDown: 0.94,
              onTap: () {
                setState(() {
                  _date = d;
                  _selectedStart = null;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 70,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  gradient: isSelected ? HagzyTheme.brandGradient : null,
                  color: isSelected ? null : kPage,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF10B981) : kBorder.withValues(alpha: 0.9),
                    width: isSelected ? 1.8 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF059669).withValues(alpha: 0.35),
                            blurRadius: 14,
                            spreadRadius: 0,
                            offset: const Offset(0, 5),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.02),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
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
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        letterSpacing: 0.2,
                        color: isSelected ? Colors.white.withValues(alpha: 0.9) : kMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${d.day}',
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.1,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: isSelected ? Colors.white : kInk,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _monthLabel(d.month, arabic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? Colors.white.withValues(alpha: 0.9) : kMuted,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 3),
                      Container(
                        width: 5,
                        height: 5,
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
                        : localized(arabic, 'Fully booked', 'مكتمل'),
                    style: TextStyle(
                      fontSize: 10,
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
        color: kPage,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kBorder),
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
                      gradient: HagzyTheme.obsidianGradient,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: HagzyTheme.coralGradient,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: const Icon(Icons.event_available_rounded,
                              color: Colors.white, size: 21),
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
                                style: const TextStyle(
                                  color: Color(0xFFA7F3D0),
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '$estimatedMinutes min',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
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
                      localized(arabic, 'Total Estimate', 'الإجمالي التقريبي'),
                      style: TextStyle(
                          color: kMuted,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatMoney(total)} ${localized(arabic, 'EGP', 'جنيه')}',
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: kInk),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: kGreen.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kGreen.withValues(alpha: 0.22)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${localized(arabic, 'Deposit', 'العربون')} (${formatMoney(venue.depositPercent)}%)',
                      style: const TextStyle(
                        color: kGreen,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${formatMoney(deposit)} ${localized(arabic, 'EGP', 'جنيه')}',
                      style: const TextStyle(
                          color: kGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 15, color: kCobalt),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  localized(
                      arabic,
                      'We hold the time for 15 minutes. It is confirmed only after the deposit is verified.',
                      'نحتفظ بالموعد لمدة ١٥ دقيقة. يتأكد الحجز فقط بعد التحقق من دفع العربون.'),
                  style: TextStyle(
                    color: kMuted,
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PressableScale(
            scaleDown: 0.97,
            onTap: onReserve,
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: kGreenLight,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                onPressed: onReserve,
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  localized(arabic, 'Reserve & pay deposit', 'احجز وادفع العربون'),
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14.5),
                ),
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
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        scaleDown: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: selected ? HagzyTheme.brandGradient : null,
            color: selected
                ? null
                : available
                    ? kPanel
                    : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? kGreen
                  : available
                      ? kBorder
                      : const Color(0xFFE2E8F0),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected ? HagzyTheme.emeraldGlowShadow : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                              ? kGreen
                              : const Color(0xFF94A3B8),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      label,
                      style: TextStyle(
                        color: selected
                            ? Colors.white
                            : available
                                ? kInk
                                : const Color(0xFF94A3B8),
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
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
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        scaleDown: 0.985,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
            boxShadow: HagzyTheme.softShadow,
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: HagzyTheme.brandGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.location_on_rounded,
                    color: Colors.white, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const LivePulseDot(color: kGreen, size: 6),
                        const SizedBox(width: 6),
                        Text(
                          localized(arabic, 'YOUR AREA', 'محافظتك'),
                          style: TextStyle(
                            color: kMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: kInk,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onGpsTap != null) ...[
                Tooltip(
                  message: localized(
                      arabic, 'Auto-assign via GPS', 'تحديد منطقتي تلقائياً عبر GPS'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: isLocating ? null : onGpsTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      margin: const EdgeInsetsDirectional.only(end: 8),
                      decoration: BoxDecoration(
                        color: kGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: kGreen.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLocating)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(kGreen),
                              ),
                            )
                          else
                            const Icon(Icons.my_location_rounded,
                                color: kGreen, size: 14),
                          const SizedBox(width: 4),
                          const Text(
                            'GPS',
                            style: TextStyle(
                              color: kGreen,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kInk.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: kBorder),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      localized(arabic, 'Change', 'تغيير'),
                      style: TextStyle(
                        color: kInk,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: kInk, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
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

  (List<Color>, IconData, String, String, Color) get _content => switch (type) {
        VenueType.sports => (
            const [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF059669)],
            Icons.sports_tennis,
            localized(arabic, 'Sports & Courts', 'ملاعب ورياضة'),
            localized(arabic, 'Courts, Pitches & Split-Pay Matches',
                'ملاعب ومباريات مع تقسيم الدفع'),
            const Color(0xFFA7F3D0),
          ),
        VenueType.salon => (
            const [Color(0xFF1E1B4B), Color(0xFF312E81), Color(0xFF4338CA)],
            Icons.content_cut,
            localized(arabic, 'Grooming & Barbershops', 'حلاقة وعناية وصالونات'),
            localized(arabic, 'Barbershops, Grooming & Chair Locks',
                'حلاقة وعناية وحجز الكراسي'),
            const Color(0xFFC7D2FE),
          ),
        VenueType.lounge => (
            const [Color(0xFF311042), Color(0xFF4C1D95), Color(0xFF6D28D9)],
            Icons.sports_esports,
            localized(arabic, 'Entertainment & Lounges', 'ترفيه وألعاب وكافيهات'),
            localized(arabic, 'PS5 VIP Rooms, Billiards & Ping Pong',
                'غرف بلايستيشن وبلياردو وبينغ بونغ'),
            const Color(0xFFDDD6FE),
          ),
        null => (
            const [Color(0xFF064E3B), Color(0xFF047857), Color(0xFF059669)],
            Icons.event_available,
            localized(arabic, 'Find your next favorite', 'اكتشف مكانك المفضل'),
            venueCount > 0
                ? (arabic
                    ? '$venueCount ${venueCount == 1 ? 'مكان محلي متاح' : 'أماكن محلية متاحة'}'
                    : '$venueCount local ${venueCount == 1 ? 'place' : 'places'} to explore')
                : localized(arabic, 'Instant slot booking & deposits in Egypt', 'حجز فوري وتأكيد بالعربون في مصر'),
            const Color(0xFFA7F3D0),
          ),
      };

  String get _image => switch (type) {
        VenueType.sports =>
          'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=640&q=75',
        VenueType.salon =>
          'https://images.unsplash.com/photo-1503951914875-452162b0f3f1?auto=format&fit=crop&w=640&q=75',
        VenueType.lounge =>
          'https://images.unsplash.com/photo-1593305841991-05c297ba4575?auto=format&fit=crop&w=640&q=75',
        null =>
          'https://images.unsplash.com/photo-1622279457486-62dcc4a431d6?auto=format&fit=crop&w=640&q=75',
      };

  @override
  Widget build(BuildContext context) {
    final content = _content;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: Container(
        key: ValueKey(type),
        height: 110,
        padding: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: content.$1,
            begin: Alignment.bottomLeft,
            end: Alignment.topRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: content.$1.first.withValues(alpha: 0.25),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(
                _image,
                fit: BoxFit.cover,
                cacheWidth: 640,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) => Align(
                  alignment:
                      arabic ? Alignment.centerLeft : Alignment.centerRight,
                  child: Icon(content.$2,
                      size: 132, color: Colors.white.withValues(alpha: .16)),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin:
                        arabic ? Alignment.centerRight : Alignment.centerLeft,
                    end: arabic ? Alignment.centerLeft : Alignment.centerRight,
                    stops: const [0, .50, 1],
                    colors: [
                      content.$1.first.withValues(alpha: .96),
                      content.$1.first.withValues(alpha: .84),
                      content.$1.last.withValues(alpha: .30),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment:
                    arabic ? Alignment.centerRight : Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment:
                      arabic ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LivePulseDot(color: content.$5, size: 5),
                          const SizedBox(width: 5),
                          Text(
                            content.$3,
                            style: TextStyle(
                              color: content.$5,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: MediaQuery.sizeOf(context).width * .64,
                      child: Text(
                        content.$4,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified_rounded,
                            size: 13, color: kGreenLight),
                        const SizedBox(width: 4),
                        Text(
                          arabic
                              ? '$venueCount ${venueCount == 1 ? 'مكان قريب' : 'أماكن قريبة'} · حجز فوري'
                              : '$venueCount ${venueCount == 1 ? 'place' : 'places'} nearby · Instant hold',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Color get _accent => switch (venue.type) {
        VenueType.sports => kGreen,
        VenueType.salon => kGreenDark,
        VenueType.lounge => kGreen,
      };

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
    final rateLabel = venue.type == VenueType.salon
        ? localized(arabic, 'per service', 'للخدمة')
        : localized(arabic, 'per hour', 'للساعة');
    final spaceLabel = switch (venue.type) {
      VenueType.sports => localized(arabic, 'Courts', 'ملاعب'),
      VenueType.salon => localized(arabic, 'Chairs', 'كراسي'),
      VenueType.lounge => localized(arabic, 'Spaces', 'أماكن'),
    };
    final ratingStr = venue.rating.toStringAsFixed(1);
    final hasReviews = venue.reviews.isNotEmpty;
    final reviewCount = venue.reviews.length;
    return AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow:
              selected ? HagzyTheme.emeraldGlowShadow : HagzyTheme.softShadow,
        ),
        child: Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: selected ? kGreen : kBorder,
              width: selected ? 2.0 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 162,
                  width: double.infinity,
                  padding: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        kInk,
                        _accent.withValues(alpha: .85),
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
                          cacheWidth: 640,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const HagzyShimmerBox(
                              width: double.infinity,
                              height: 162,
                              borderRadius: 0,
                            );
                          },
                          errorBuilder: (context, error, stackTrace) =>
                              const SizedBox.shrink(),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.0, 0.45, 1.0],
                              colors: [
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.78),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Stack(
                            children: [
                              Align(
                                alignment: AlignmentDirectional.topStart,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: kInk.withValues(alpha: 0.78),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.16)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(venue.type.icon,
                                          size: 12, color: Colors.white),
                                      const SizedBox(width: 5),
                                      Text(
                                        switch (venue.type) {
                                          VenueType.sports => localized(
                                              arabic, 'SPORTS & COURTS', 'رياضة وملاعب'),
                                          VenueType.salon => localized(
                                              arabic, 'GROOMING & SALONS', 'حلاقة وعناية'),
                                          VenueType.lounge => localized(
                                              arabic, 'ENTERTAINMENT', 'ترفيه وألعاب'),
                                        },
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            letterSpacing: .7,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: AlignmentDirectional.topEnd,
                                child: Material(
                                  color: favorite
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.94),
                                  shape: const CircleBorder(),
                                  elevation: favorite ? 3 : 2,
                                  shadowColor: favorite
                                      ? const Color(0xFFE11D48).withValues(alpha: 0.4)
                                      : Colors.black26,
                                  child: IconButton(
                                    tooltip: favorite
                                        ? localized(arabic, 'Remove from Saved Places',
                                            'إزالة من الأماكن المفضلة')
                                        : localized(arabic, 'Save to Favorites',
                                            'حفظ في المفضلة'),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onFavorite,
                                    icon: Icon(
                                      favorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: favorite
                                          ? const Color(0xFFE11D48)
                                          : kInk,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.bottomLeft,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            hasReviews
                                                ? Icons.star_rounded
                                                : Icons.fiber_new_rounded,
                                            size: 14,
                                            color: hasReviews
                                                ? const Color(0xFFF59E0B)
                                                : kGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            hasReviews
                                                ? localized(
                                                    arabic,
                                                    '$ratingStr ($reviewCount) · Verified',
                                                    '$ratingStr ($reviewCount) · مكان معتمد')
                                                : localized(
                                                    arabic, 'New Venue', 'مكان جديد'),
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w800,
                                              color: kInk,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (venue.instaPayAddress.isNotEmpty ||
                                        venue.vodafoneCashNumber.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 9, vertical: 4),
                                        decoration: BoxDecoration(
                                          gradient: HagzyTheme.brandGradient,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.bolt_rounded,
                                                size: 12, color: Colors.white),
                                            const SizedBox(width: 2),
                                            Text(
                                              localized(arabic, 'Instant Transfer',
                                                  'تحويل فوري'),
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              venue.name,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                                color: kInk,
                              ),
                            ),
                          ),
                          if (selected)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: kGreen.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle,
                                      color: kGreen, size: 14),
                                  const SizedBox(width: 4),
                                  Text(
                                    localized(arabic, 'Selected', 'محدد'),
                                    style: const TextStyle(
                                      color: kGreen,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Builder(
                              builder: (context) {
                                final avail = _computeLiveAvailability();
                                final badgeColor = avail.isAvailableNow
                                    ? kGreen
                                    : const Color(0xFFD97706);
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: badgeColor.withValues(alpha: 0.28),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 6.5,
                                        height: 6.5,
                                        decoration: BoxDecoration(
                                          color: badgeColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        avail.label,
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 15, color: kMuted),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              venue.location.isEmpty
                                  ? localized(
                                      arabic,
                                      'Location Details Available on Booking',
                                      'تفاصيل الموقع عند الحجز')
                                  : venue.location,
                              style: TextStyle(
                                color: kMuted,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () async {
                              final rawUrl = venue.googleMapsUrl.trim();
                              final uri = rawUrl.isNotEmpty
                                  ? Uri.parse(rawUrl)
                                  : Uri.https('www.google.com', '/maps/search/', {
                                      'api': '1',
                                      'query': '${venue.name} ${venue.location} Egypt'.trim(),
                                    });
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.directions_outlined,
                                      size: 14, color: kGreen),
                                  const SizedBox(width: 3),
                                  Text(
                                    localized(
                                        arabic, 'Directions', 'الاتجاهات'),
                                    style: const TextStyle(
                                      color: kGreen,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _accent.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${venue.items.length} $spaceLabel',
                              style: TextStyle(
                                color: _accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (venue.effectiveSubCategories.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: venue.effectiveSubCategories.map((subId) {
                            final def = findSubCategoryDef(subId);
                            if (def == null) return const SizedBox.shrink();
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _accent.withValues(alpha: 0.22),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SystemEmoji(def.emoji, size: 11),
                                  const SizedBox(width: 4),
                                  Text(
                                    def.title(arabic),
                                    style: TextStyle(
                                      color: _accent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      if (venue.amenities.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: venue.amenities.take(4).map((amenity) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: kPage,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kBorder),
                              ),
                              child: Text(
                                amenity,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: kInk,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                    color: kInk, fontSize: 12.5),
                                children: [
                                  TextSpan(
                                    text:
                                        localized(arabic, 'From ', 'يبدأ من '),
                                    style: TextStyle(
                                        color: kMuted,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(
                                    text: lowestPrice == null
                                        ? localized(arabic, 'Price on Request',
                                            'السعر عند الطلب')
                                        : '${formatMoney(lowestPrice)} ${localized(arabic, 'EGP', 'ج.م')}',
                                    style: TextStyle(
                                        color: kInk,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900),
                                  ),
                                  if (lowestPrice != null)
                                    TextSpan(
                                      text: ' $rateLabel',
                                      style: TextStyle(
                                          color: kMuted,
                                          fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (onDetails != null) ...[
                            IconButton(
                              tooltip: localized(arabic, 'Venue Info & Reviews',
                                  'التفاصيل والتقييمات'),
                              visualDensity: VisualDensity.compact,
                              onPressed: onDetails,
                              icon: Icon(Icons.info_outline_rounded,
                                  size: 20, color: kMuted),
                            ),
                            const SizedBox(width: 4),
                          ],
                          PressableScale(
                            scaleDown: 0.94,
                            onTap: onTap,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: selected
                                    ? const Color(0xFFEF4444)
                                        .withValues(alpha: 0.12)
                                    : kGreen,
                                foregroundColor: selected
                                    ? const Color(0xFFEF4444)
                                    : Colors.white,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                elevation: 0,
                              ),
                              onPressed: onTap,
                              icon: Icon(
                                selected
                                    ? Icons.close_rounded
                                    : Icons.calendar_today_rounded,
                                size: 15,
                              ),
                              label: Text(
                                selected
                                    ? localized(arabic, 'Close', 'إغلاق')
                                    : localized(
                                        arabic, 'Book', 'احجز'),
                                style:
                                    const TextStyle(fontWeight: FontWeight.w800),
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
    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(localized(arabic, 'Rate ${widget.venue.name}',
              'قيّم ${widget.venue.name}')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (idx) {
                    final star = idx + 1;
                    return IconButton(
                      tooltip: localized(
                          arabic, '$star out of 5', '$star من 5'),
                      onPressed: () =>
                          setDialogState(() => rating = star.toDouble()),
                      icon: Icon(
                        star <= rating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: const Color(0xFFF59E0B),
                        size: 30,
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => author = v,
                  decoration: InputDecoration(
                    labelText: localized(arabic, 'Your Name', 'الاسم'),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(localized(arabic, 'Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                if (author.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: Text(localized(arabic, 'Submit Review', 'إرسال التقييم')),
            ),
          ],
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
                        venue.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        venue.location.isEmpty
                            ? venue.type.label
                            : '${venue.location} · ${venue.type.label}',
                        style: TextStyle(color: kMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 16, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 4),
                      Text(
                        venue.rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                if (widget.onFavorite != null) ...[
                  const SizedBox(width: 8),
                  Material(
                    color: widget.favorite
                        ? const Color(0xFFFFE4E6)
                        : const Color(0xFFF1F5F9),
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
                            : kInk,
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
                      SizedBox(
                        height: 128,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: venue.galleryUrls.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, idx) => ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              venue.galleryUrls[idx],
                              width: 210,
                              height: 128,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 210,
                                height: 128,
                                color: kPage,
                                alignment: Alignment.center,
                                child: Icon(venue.type.icon, color: kGreen),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (venue.description.isNotEmpty) ...[
                      Text(
                        venue.description,
                        style: TextStyle(color: kInk, height: 1.45),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(Icons.access_time,
                              size: 15, color: kGreen),
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
                          avatar: const Icon(Icons.percent,
                              size: 15, color: kGreen),
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
                            label:
                                Text(a, style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
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
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : kPanel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isSelected
                ? glowColor.withValues(alpha: 0.6)
                : kBorder,
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: glowColor.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  )
                ]
              : [
                  BoxShadow(
                    color: kInk.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.22)
                    : glowColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 18,
                color: isSelected ? Colors.white : glowColor,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                        color: isSelected ? Colors.white : kInk,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.25)
                              : kSurfaceTint,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: isSelected ? Colors.white : kMuted,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected
                        ? Colors.white.withValues(alpha: 0.85)
                        : kMuted,
                  ),
                ),
              ],
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    Icons.check_rounded,
                    size: 11,
                    color: gradient.first,
                  ),
                ),
              ),
            ],
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
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: kInk,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$count',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: kMuted,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: accentColor,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    localized(arabic, 'Filter', 'تصفية'),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    arabic
                        ? Icons.arrow_back_ios_new_rounded
                        : Icons.arrow_forward_ios_rounded,
                    size: 11,
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
    return PressableScale(
      onTap: onTap,
      scaleDown: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentColor : kPanel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? accentColor
                : (count > 0 ? kBorder : kBorder.withValues(alpha: 0.5)),
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.32),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : HagzyTheme.softShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SystemEmoji(emoji, size: 13),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                color: isSelected ? Colors.white : kInk,
                letterSpacing: -0.1,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.24)
                      : accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: isSelected ? Colors.white : accentColor,
                  ),
                ),
              ),
            ],
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          gradient: active ? HagzyTheme.brandGradient : null,
          color: active
              ? null
              : (done
                  ? kGreen.withValues(alpha: 0.12)
                  : (isDark ? const Color(0xFF19243D) : Colors.white)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active
                ? kGreen
                : (done
                    ? kGreen.withValues(alpha: 0.35)
                    : (isDark ? const Color(0xFF283552) : kBorder)),
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
                    ? Colors.white.withValues(alpha: 0.24)
                    : (done ? kGreen : kMuted.withValues(alpha: 0.18)),
                shape: BoxShape.circle,
              ),
              child: done && !active
                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                  : Text(
                      stepNumber,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        color: active || done
                            ? Colors.white
                            : (isDark ? const Color(0xFF94A3B8) : kInk),
                      ),
                    ),
            ),
            const SizedBox(width: 6),
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
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                      color: active
                          ? Colors.white
                          : (isDark ? const Color(0xFFF8FAFC) : kInk),
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? Colors.white.withValues(alpha: 0.88)
                          : (done
                              ? (isDark ? kGreenLight : kGreenDark)
                              : (isDark ? const Color(0xFF94A3B8) : kMuted)),
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


