import 'package:flutter/material.dart';
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
  });

  final List<Venue> venues;
  final bool arabic;
  final String selectedArea;
  final ValueChanged<Venue> onSelectVenue;
  final void Function(Venue venue) onBookVenue;
  final String? selectedVenueId;

  @override
  State<HagzyMapExplorer> createState() => _HagzyMapExplorerState();
}

class _HagzyMapExplorerState extends State<HagzyMapExplorer> {
  String? _activeVenueId;
  double? _maxDistanceKm; // null = all distances, or 5, 15, 30, 50

  @override
  void initState() {
    super.initState();
    _activeVenueId = widget.selectedVenueId ?? widget.venues.firstOrNull?.id;
  }

  @override
  void didUpdateWidget(HagzyMapExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedVenueId != null &&
        widget.selectedVenueId != _activeVenueId) {
      setState(() => _activeVenueId = widget.selectedVenueId);
    }
  }

  (double, double) _getUserCenter() {
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
      ..sort((a, b) => _getDistanceToVenue(a).compareTo(_getDistanceToVenue(b)));
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

  @override
  Widget build(BuildContext context) {
    final arabic = widget.arabic;
    final sortedVenues = _getFilteredAndSortedVenues();
    final activeVenue = sortedVenues.where((v) => v.id == _activeVenueId).firstOrNull ??
        sortedVenues.firstOrNull;

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
                  const Icon(Icons.my_location_rounded, size: 16, color: kGreen),
                  const SizedBox(width: 8),
                  Text(
                    localized(
                      arabic,
                      'Current Center: ${widget.selectedArea}',
                      'مركز البحث: ${governorateName(widget.selectedArea, arabic)}',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: kInk,
                    ),
                  ),
                  const Spacer(),
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

        // Interactive Map Canvas
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFFE2EBE5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: kBorder),
              boxShadow: HagzyTheme.softShadow,
            ),
            child: Stack(
              children: [
                // Stylized map background pattern representing Nile delta & road grid
                Positioned.fill(
                  child: CustomPaint(
                    painter: _EgyptMapGridPainter(),
                  ),
                ),

                // Area / City label watermarks
                Positioned(
                  top: 18,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.explore_rounded,
                            size: 14, color: kGreen),
                        const SizedBox(width: 6),
                        Text(
                          localized(arabic, 'Egypt Interactive Map',
                              'خريطة مصر التفاعلية'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: kInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Venue Pins
                ...sortedVenues.map((v) {
                  final isSelected = v.id == activeVenue?.id;
                  // Normalized relative coordinate on map canvas
                  // Egypt Lat range: approx 27.0 to 31.5 -> height
                  // Egypt Lon range: approx 29.5 to 34.0 -> width
                  const minLat = 27.0;
                  const maxLat = 31.5;
                  const minLon = 29.5;
                  const maxLon = 34.0;

                  final relX = ((v.effectiveLongitude - minLon) / (maxLon - minLon))
                      .clamp(0.08, 0.92);
                  final relY = (1.0 -
                          ((v.effectiveLatitude - minLat) / (maxLat - minLat)))
                      .clamp(0.12, 0.88);

                  return Positioned(
                    left: relX * 320,
                    top: relY * 230,
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _activeVenueId = v.id);
                        widget.onSelectVenue(v);
                      },
                      child: Column(
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
                                      ? kGreen.withValues(alpha: 0.45)
                                      : Colors.black.withValues(alpha: 0.25),
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
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: Text(
                              v.name,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isSelected
                                    ? FontWeight.w900
                                    : FontWeight.w700,
                                color: isSelected ? kGreen : kInk,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
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
                                  style: const TextStyle(
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
                        label: Text(localized(arabic, 'Directions', 'الاتجاهات')),
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
                        icon: const Icon(Icons.calendar_today_rounded, size: 15),
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

class _EgyptMapGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final riverPaint = Paint()
      ..color = const Color(0xFF93C5FD).withValues(alpha: 0.5)
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final nilePath = Path()
      ..moveTo(size.width * 0.58, size.height)
      ..quadraticBezierTo(
        size.width * 0.54,
        size.height * 0.65,
        size.width * 0.52,
        size.height * 0.45,
      )
      ..quadraticBezierTo(
        size.width * 0.51,
        size.height * 0.35,
        size.width * 0.50,
        size.height * 0.22,
      );

    // Delta branches
    final deltaBranchWest = Path()
      ..moveTo(size.width * 0.50, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.44,
        size.height * 0.12,
        size.width * 0.38,
        0,
      );
    final deltaBranchEast = Path()
      ..moveTo(size.width * 0.50, size.height * 0.22)
      ..quadraticBezierTo(
        size.width * 0.54,
        size.height * 0.10,
        size.width * 0.60,
        0,
      );

    canvas.drawPath(nilePath, riverPaint);
    canvas.drawPath(deltaBranchWest, riverPaint);
    canvas.drawPath(deltaBranchEast, riverPaint);

    // Grid lines for modern radar / geo look
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    for (double x = 0; x < size.width; x += 35) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 35) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
