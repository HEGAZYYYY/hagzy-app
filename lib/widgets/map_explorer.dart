import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import 'common_widgets.dart';

class HagzyMapExplorer extends StatefulWidget {
  const HagzyMapExplorer({
    super.key,
    required this.venues,
    required this.arabic,
    required this.selectedArea,
    required this.onSelectVenue,
    required this.onBookVenue,
    this.selectedVenueId,
    this.onAreaDetected,
  });

  final List<Venue> venues;
  final bool arabic;
  final String selectedArea;
  final ValueChanged<Venue> onSelectVenue;
  final void Function(Venue venue) onBookVenue;
  final String? selectedVenueId;
  final ValueChanged<String>? onAreaDetected;

  @override
  State<HagzyMapExplorer> createState() => _HagzyMapExplorerState();
}

class _HagzyMapExplorerState extends State<HagzyMapExplorer> {
  late final MapController _mapController;
  String? _activeVenueId;
  double? _maxDistanceKm; // null = all distances, or 5, 15, 30, 50
  Position? _userGpsPosition;
  bool _locating = false;
  String? _gpsStatusMessage;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _activeVenueId = widget.selectedVenueId ?? widget.venues.firstOrNull?.id;
    // Auto-request GPS on device/browser (skip in automated test runner)
    if (!WidgetsBinding.instance.runtimeType.toString().contains('Test')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestGpsLocation();
      });
    }
  }

  Future<void> _requestGpsLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _gpsStatusMessage = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locating = false;
            _gpsStatusMessage = widget.arabic
                ? 'خدمات الموقع غير مفعلة'
                : 'Location services disabled';
          });
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
              _locating = false;
              _gpsStatusMessage = widget.arabic
                  ? 'تم رفض إذن الموقع'
                  : 'Location permission denied';
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locating = false;
            _gpsStatusMessage = widget.arabic
                ? 'إذن الموقع محظور في الإعدادات'
                : 'Location permanently denied';
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (mounted) {
        setState(() {
          _userGpsPosition = pos;
          _locating = false;
          _gpsStatusMessage =
              widget.arabic ? 'تم تحديد موقعك بدقة' : 'GPS location found';
        });

        // Center the functional map on the user's live position
        try {
          _mapController.move(ll.LatLng(pos.latitude, pos.longitude), 13.5);
        } catch (_) {}

        // Auto-assign nearest governorate in the app
        final nearestGov =
            findNearestGovernorate(pos.latitude, pos.longitude);
        if (widget.onAreaDetected != null) {
          widget.onAreaDetected!(nearestGov);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locating = false;
          _gpsStatusMessage =
              widget.arabic ? 'تعذر جلب GPS' : 'GPS unavailable';
        });
      }
    }
  }

  @override
  void didUpdateWidget(HagzyMapExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedVenueId != null &&
        widget.selectedVenueId != _activeVenueId) {
      setState(() => _activeVenueId = widget.selectedVenueId);
      final venue =
          widget.venues.where((v) => v.id == widget.selectedVenueId).firstOrNull;
      if (venue != null) {
        try {
          _mapController.move(
            ll.LatLng(venue.effectiveLatitude, venue.effectiveLongitude),
            14.5,
          );
        } catch (_) {}
      }
    }
  }

  (double, double) _getUserCenter() {
    if (_userGpsPosition != null) {
      return (_userGpsPosition!.latitude, _userGpsPosition!.longitude);
    }
    return kEgyptGovernorateCoordinates[widget.selectedArea] ??
        kEgyptGovernorateCoordinates['Cairo'] ??
        (30.0444, 31.2357);
  }

  double _getDistanceToVenue(Venue venue) {
    final userCenter = _getUserCenter();
    return calculateDistanceKm(
      userCenter.$1,
      userCenter.$2,
      venue.effectiveLatitude,
      venue.effectiveLongitude,
    );
  }

  List<Venue> _getFilteredAndSortedVenues() {
    final list = widget.venues.where((v) {
      if (_maxDistanceKm == null) return true;
      final dist = _getDistanceToVenue(v);
      return dist <= _maxDistanceKm!;
    }).toList()
      ..sort((a, b) =>
          _getDistanceToVenue(a).compareTo(_getDistanceToVenue(b)));
    return list;
  }

  Future<void> _openDirections(Venue venue) async {
    final url = venue.googleMapsUrl.isNotEmpty
        ? venue.googleMapsUrl
        : 'https://www.google.com/maps/search/?api=1&query=${venue.effectiveLatitude},${venue.effectiveLongitude}';
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onTapVenuePin(Venue v) {
    setState(() => _activeVenueId = v.id);
    widget.onSelectVenue(v);
    try {
      _mapController.move(
        ll.LatLng(v.effectiveLatitude, v.effectiveLongitude),
        15.0,
      );
    } catch (_) {}
  }

  Widget _buildUserLocationMarker(bool arabic) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3B82F6).withValues(alpha: 0.28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x662563EB),
                blurRadius: 12,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF2563EB),
              border: Border.all(color: Colors.white, width: 2.5),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: const Color(0xFF1E3A8A),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: Text(
            localized(arabic, 'You', 'أنت هنا'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVenueMarker(Venue v, bool isSelected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(isSelected ? 9 : 6),
          decoration: BoxDecoration(
            gradient: isSelected
                ? HagzyTheme.brandGradient
                : HagzyTheme.obsidianGradient,
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: isSelected ? 2.5 : 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? kGreen.withValues(alpha: 0.5)
                    : Colors.black.withValues(alpha: 0.35),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            v.type.icon,
            size: isSelected ? 18 : 13,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 78),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? kGreen : kBorder,
              width: isSelected ? 1.5 : 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            v.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 9,
              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
              color: isSelected ? kGreen : kInk,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Tooltip(
      message: tooltip,
      child: PressableScale(
        scaleDown: 0.92,
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: kPanel.withValues(alpha: 0.96),
            shape: BoxShape.circle,
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black12, blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: Icon(icon, size: 18, color: color ?? kInk),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    final sortedVenues = _getFilteredAndSortedVenues();
    final activeVenue =
        sortedVenues.where((v) => v.id == _activeVenueId).firstOrNull ??
            sortedVenues.firstOrNull;
    final center = _getUserCenter();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Filter bar for distance & area center
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kPanel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _userGpsPosition != null
                        ? Icons.gps_fixed_rounded
                        : Icons.my_location_rounded,
                    size: 16,
                    color: _userGpsPosition != null
                        ? const Color(0xFF2563EB)
                        : kGreen,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _userGpsPosition != null
                          ? localized(
                              arabic,
                              'Live GPS: Near You (${_userGpsPosition!.latitude.toStringAsFixed(2)}°, ${_userGpsPosition!.longitude.toStringAsFixed(2)}°)',
                              'موقعك المباشر: قريب منك (${_userGpsPosition!.latitude.toStringAsFixed(2)}°, ${_userGpsPosition!.longitude.toStringAsFixed(2)}°)',
                            )
                          : localized(
                              arabic,
                              'Current Center: ${widget.selectedArea}',
                              'مركز البحث: ${governorateName(widget.selectedArea, arabic)}',
                            ),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: _userGpsPosition != null
                            ? const Color(0xFF1D4ED8)
                            : kInk,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressableScale(
                    scaleDown: 0.95,
                    onTap: _locating ? null : _requestGpsLocation,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: _userGpsPosition != null
                            ? const Color(0xFFDBEAFE)
                            : kSurfaceTint,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _userGpsPosition != null
                              ? const Color(0xFF93C5FD)
                              : kGreen.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_locating) ...[
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 5),
                          ] else ...[
                            Icon(
                              _userGpsPosition != null
                                  ? Icons.refresh_rounded
                                  : Icons.gps_fixed_rounded,
                              size: 13,
                              color: _userGpsPosition != null
                                  ? const Color(0xFF1E40AF)
                                  : kGreen,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _locating
                                ? localized(
                                    arabic, 'Locating...', 'جاري التحديد...')
                                : _userGpsPosition != null
                                    ? localized(
                                        arabic, 'Update GPS', 'تحديث')
                                    : localized(
                                        arabic, 'Use GPS', 'موقعي (GPS)'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: _userGpsPosition != null
                                  ? const Color(0xFF1E40AF)
                                  : kGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${sortedVenues.length} ${localized(arabic, 'nearby', 'قريب')}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: kGreen,
                      ),
                    ),
                  ),
                ],
              ),
              if (_gpsStatusMessage != null && _userGpsPosition == null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 13, color: Color(0xFFDC2626)),
                    const SizedBox(width: 5),
                    Text(
                      _gpsStatusMessage!,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    CustomPill(
                      label: localized(arabic, 'All Distances', 'كل المسافات'),
                      selected: _maxDistanceKm == null,
                      onTap: () => setState(() => _maxDistanceKm = null),
                    ),
                    const SizedBox(width: 6),
                    CustomPill(
                      label: localized(arabic, '< 5 km', 'أقل من ٥ كم'),
                      selected: _maxDistanceKm == 5,
                      onTap: () => setState(() => _maxDistanceKm = 5),
                    ),
                    const SizedBox(width: 6),
                    CustomPill(
                      label: localized(arabic, '< 15 km', 'أقل من ١٥ كم'),
                      selected: _maxDistanceKm == 15,
                      onTap: () => setState(() => _maxDistanceKm = 15),
                    ),
                    const SizedBox(width: 6),
                    CustomPill(
                      label: localized(arabic, '< 50 km', 'أقل من ٥٠ كم'),
                      selected: _maxDistanceKm == 50,
                      onTap: () => setState(() => _maxDistanceKm = 50),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Real Functional Interactive Map (OpenStreetMap tile engine)
        Container(
          height: 330,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: kBorder, width: 1.5),
            boxShadow: HagzyTheme.softShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: ll.LatLng(center.$1, center.$2),
                  initialZoom: _userGpsPosition != null ? 13.5 : 12.0,
                  minZoom: 4.0,
                  maxZoom: 18.0,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'app.hagzy.customer',
                    maxZoom: 19,
                  ),
                  MarkerLayer(
                    markers: [
                      // User's exact live location marker
                      if (_userGpsPosition != null)
                        Marker(
                          point: ll.LatLng(
                            _userGpsPosition!.latitude,
                            _userGpsPosition!.longitude,
                          ),
                          width: 65,
                          height: 65,
                          alignment: Alignment.center,
                          child: _buildUserLocationMarker(arabic),
                        ),
                      // Real venue markers on actual streets
                      ...sortedVenues.map((v) {
                        final isSelected = v.id == activeVenue?.id;
                        return Marker(
                          point: ll.LatLng(
                            v.effectiveLatitude,
                            v.effectiveLongitude,
                          ),
                          width: isSelected ? 80 : 54,
                          height: isSelected ? 80 : 54,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            onTap: () => _onTapVenuePin(v),
                            child: _buildVenueMarker(v, isSelected),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),

              // Interactive Floating Map Controls (Zoom In, Zoom Out, Recenter)
              Positioned(
                top: 12,
                right: 12,
                child: Column(
                  children: [
                    _buildMapControlButton(
                      icon: Icons.add_rounded,
                      tooltip: localized(arabic, 'Zoom In', 'تكبير'),
                      onTap: () {
                        final current = _mapController.camera.zoom;
                        _mapController.move(
                          _mapController.camera.center,
                          (current + 1.0).clamp(4.0, 18.0),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildMapControlButton(
                      icon: Icons.remove_rounded,
                      tooltip: localized(arabic, 'Zoom Out', 'تصغير'),
                      onTap: () {
                        final current = _mapController.camera.zoom;
                        _mapController.move(
                          _mapController.camera.center,
                          (current - 1.0).clamp(4.0, 18.0),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    _buildMapControlButton(
                      icon: Icons.my_location_rounded,
                      tooltip: localized(
                          arabic, 'Center on my location', 'توسيط موقعي'),
                      color: _userGpsPosition != null
                          ? const Color(0xFF2563EB)
                          : kGreen,
                      onTap: () {
                        if (_userGpsPosition != null) {
                          _mapController.move(
                            ll.LatLng(
                              _userGpsPosition!.latitude,
                              _userGpsPosition!.longitude,
                            ),
                            14.5,
                          );
                        } else {
                          _requestGpsLocation();
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Attribution Watermark
              Positioned(
                bottom: 6,
                left: 10,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '© OpenStreetMap contributors',
                    style: TextStyle(
                      fontSize: 8.5,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Selected Venue Quick Card below Map
        if (activeVenue != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kPanel,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: kGreen.withValues(alpha: 0.3)),
              boxShadow: HagzyTheme.softShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: HagzyTheme.brandGradient,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(activeVenue.type.icon,
                          color: Colors.white, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  activeVenue.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16.5,
                                    color: kInk,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.star_rounded,
                                      size: 16, color: Color(0xFFF59E0B)),
                                  const SizedBox(width: 3),
                                  Text(
                                    activeVenue.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Icons.near_me_rounded,
                                  size: 13, color: kGreen),
                              const SizedBox(width: 4),
                              Text(
                                '${_getDistanceToVenue(activeVenue).toStringAsFixed(1)} ${localized(arabic, 'km away', 'كم عنك')} · ${activeVenue.location}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: kGreen,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => _openDirections(activeVenue),
                        icon: const Icon(Icons.directions_rounded,
                            size: 16, color: kGreen),
                        label: Text(
                            localized(arabic, 'Directions', 'الاتجاهات')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: kGreen,
                          foregroundColor: Colors.white,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () => widget.onBookVenue(activeVenue),
                        icon:
                            const Icon(Icons.calendar_today_rounded, size: 15),
                        label: Text(localized(arabic, 'Book Now', 'احجز الآن')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
