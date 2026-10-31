import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';

/// Polymorphic Booking Bottom Sheet (Rule #1 & Principle 2)
/// Dynamically switches UI between:
/// 1. Hourly Rooms/Tables (PS5/Billiards/Courts)
/// 2. Day Passes (Workspaces)
/// 3. Tiered Headcount (Escape Rooms)
/// 4. Service Checklists (Barbershops)
class UniversalBookingBottomSheet extends StatefulWidget {
  final BookableUnit unit;
  final HagzyVenue venue;
  final DateTime initialStartTime;
  final ValueChanged<HagzyBooking> onLockSlotAndProceed;
  final bool isArabic;

  const UniversalBookingBottomSheet({
    super.key,
    required this.unit,
    required this.venue,
    required this.initialStartTime,
    required this.onLockSlotAndProceed,
    this.isArabic = false,
  });

  static Future<void> show({
    required BuildContext context,
    required BookableUnit unit,
    required HagzyVenue venue,
    DateTime? initialStartTime,
    required ValueChanged<HagzyBooking> onLockSlotAndProceed,
    bool isArabic = false,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => UniversalBookingBottomSheet(
        unit: unit,
        venue: venue,
        initialStartTime: initialStartTime ?? DateTime.now().add(const Duration(hours: 1)),
        onLockSlotAndProceed: onLockSlotAndProceed,
        isArabic: isArabic,
      ),
    );
  }

  @override
  State<UniversalBookingBottomSheet> createState() =>
      _UniversalBookingBottomSheetState();
}

class _UniversalBookingBottomSheetState
    extends State<UniversalBookingBottomSheet> {
  late DateTime _selectedStart;
  double _durationHours = 1.0;
  int _headcount = 1;
  String _timePassType = 'hourly';
  final Set<String> _selectedServiceIds = {};
  final Set<String> _selectedAddonIds = {};

  @override
  void initState() {
    super.initState();
    _selectedStart = widget.initialStartTime;
    _headcount = widget.unit.minCapacity.clamp(1, 99);

    // Default select first service if serviceMenu
    if (widget.unit.pricingMode == PricingMode.serviceMenu &&
        widget.unit.serviceMenu.isNotEmpty) {
      _selectedServiceIds.add(widget.unit.serviceMenu.first.id);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  PricingCalculationResult get _currentPricing => widget.unit.calculatePricing(
        headcount: _headcount,
        durationHours: _durationHours,
        timePassType: _timePassType,
        selectedServiceIds: _selectedServiceIds.toList(),
        selectedAddonIds: _selectedAddonIds.toList(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAr = widget.isArabic;
    final pricing = _currentPricing;

    return Material(
      color: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.90,
        ),
        child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: theme.dividerColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.unit.unitName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.venue.name} • ${widget.venue.city}',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Scrollable polymorphic controls
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20.0),
              children: [
                // 1. Time / Slot Row
                _buildTimePickerRow(theme, isAr),
                const SizedBox(height: 20),

                // 2. Polymorphic Mode Body
                _buildModeSpecificControls(theme, isAr, pricing),
                const SizedBox(height: 20),

                // 3. Add-ons section (if available)
                if (widget.unit.addons.isNotEmpty) ...[
                  _buildAddonsSection(theme, isAr),
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),

          // Bottom Price Anchoring & Action Bar (Principle 4: Contrast Effect)
          _buildContrastAnchoredBottomBar(theme, isAr, pricing),
        ],
      ),
    ),
  );
}

  Widget _buildTimePickerRow(ThemeData theme, bool isAr) {
    final timeStr =
        '${_selectedStart.hour.toString().padLeft(2, '0')}:${_selectedStart.minute.toString().padLeft(2, '0')}';
    final dateStr = '${_selectedStart.day}/${_selectedStart.month}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.access_time_rounded,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isAr ? 'ميعاد الحجز' : 'Reservation Time',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '$dateStr • $timeStr',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          OutlinedButton(
            onPressed: _pickTime,
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isAr ? 'تعديل' : 'Change'),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSpecificControls(
      ThemeData theme, bool isAr, PricingCalculationResult pricing) {
    switch (widget.unit.pricingMode) {
      case PricingMode.hourlyFlat:
      case PricingMode.hourlyTieredCapacity:
        return _buildHourlyAndTieredControls(theme, isAr);

      case PricingMode.perPersonTiered:
        return _buildEscapeRoomTieredControls(theme, isAr, pricing);

      case PricingMode.timePass:
        return _buildWorkspacePassControls(theme, isAr);

      case PricingMode.serviceMenu:
        return _buildBarberServiceMenuControls(theme, isAr);
    }
  }

  // 1 & 2: Hourly and Tiered Capacity (PS5 / Billiards / Courts)
  Widget _buildHourlyAndTieredControls(ThemeData theme, bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Duration selector
        Text(
          isAr ? 'مدة اللعب / الحجز' : 'Duration',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [1.0, 1.5, 2.0, 3.0].map((hours) {
            final isSel = _durationHours == hours;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: ChoiceChip(
                  label: Text(
                    hours == 1.0
                        ? (isAr ? 'ساعة' : '1 hr')
                        : '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)} ${isAr ? "ساعة" : "hrs"}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel ? Colors.black : null,
                    ),
                  ),
                  selected: isSel,
                  selectedColor: theme.colorScheme.primary,
                  onSelected: (_) => setState(() => _durationHours = hours),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Headcount stepper / chips
        Text(
          isAr ? 'عدد اللاعبين / الشلة' : 'Number of Players (Shilla)',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _headcount > widget.unit.minCapacity
                  ? () => setState(() => _headcount--)
                  : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            const SizedBox(width: 16),
            Text(
              '$_headcount ${isAr ? "لاعبين" : "Players"}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              onPressed: (widget.unit.maxCapacity <= 0 ||
                      _headcount < widget.unit.maxCapacity)
                  ? () => setState(() => _headcount++)
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  // 3: Escape Rooms (Per Person Tiered — cost drops as group grows!)
  Widget _buildEscapeRoomTieredControls(
      ThemeData theme, bool isAr, PricingCalculationResult pricing) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              isAr ? 'حجم المجموعة (كل ما تزيدوا السعر يقل!)' : 'Group Size (More Friends = Cheaper!)',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${pricing.rateAppliedEgp.toStringAsFixed(0)} ${isAr ? "ج.م / فرد" : "EGP/ea"}',
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Stepper for squad
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _headcount > widget.unit.minCapacity
                  ? () => setState(() => _headcount--)
                  : null,
              icon: const Icon(Icons.remove, size: 18),
            ),
            const SizedBox(width: 16),
            Text(
              '$_headcount ${isAr ? "أفراد" : "People"}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              onPressed: _headcount < widget.unit.maxCapacity
                  ? () => setState(() => _headcount++)
                  : null,
              icon: const Icon(Icons.add, size: 18),
            ),
          ],
        ),

        // Visual tier ladder
        if (widget.unit.pricingTiers.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.unit.pricingTiers.entries.map((e) {
                final tierCap = int.tryParse(e.key) ?? 1;
                final isCurrentTier = _headcount == tierCap;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isCurrentTier
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrentTier
                          ? theme.colorScheme.primary
                          : theme.dividerColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '$tierCap ${isAr ? "أفراد" : "p"}: ${e.value} ${isAr ? "ج.م" : "EGP"}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isCurrentTier ? FontWeight.bold : FontWeight.normal,
                      color: isCurrentTier ? theme.colorScheme.primary : null,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // 4: Workspaces (Hourly vs Day Pass vs Weekly)
  Widget _buildWorkspacePassControls(ThemeData theme, bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr ? 'نوع التصريح / الباقة' : 'Pass Type',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                label: Text(isAr ? 'بالساعة' : 'Hourly'),
                selected: _timePassType == 'hourly',
                selectedColor: theme.colorScheme.primary,
                onSelected: (_) => setState(() => _timePassType = 'hourly'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ChoiceChip(
                label: Text(isAr ? 'يوم كامل (Day Pass)' : 'Day Pass'),
                selected: _timePassType == 'day_pass',
                selectedColor: theme.colorScheme.primary,
                onSelected: (_) => setState(() => _timePassType = 'day_pass'),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ChoiceChip(
                label: Text(isAr ? 'أسبوعي' : 'Weekly'),
                selected: _timePassType == 'weekly',
                selectedColor: theme.colorScheme.primary,
                onSelected: (_) => setState(() => _timePassType = 'weekly'),
              ),
            ),
          ],
        ),
        if (_timePassType == 'hourly') ...[
          const SizedBox(height: 12),
          Text(
            isAr ? 'عدد الساعات' : 'Number of Hours',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            children: [1.0, 2.0, 3.0, 4.0, 6.0].map((h) {
              final isSel = _durationHours == h;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: ChoiceChip(
                  label: Text('${h.toInt()}h'),
                  selected: isSel,
                  selectedColor: theme.colorScheme.primary,
                  onSelected: (_) => setState(() => _durationHours = h),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  // 5: Barbershop additive checklist
  Widget _buildBarberServiceMenuControls(ThemeData theme, bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr ? 'اختر الخدمات (قائمة تراكمية)' : 'Select Services',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        ...widget.unit.serviceMenu.map((service) {
          final isChecked = _selectedServiceIds.contains(service.id);
          return Material(
            color: Colors.transparent,
            child: CheckboxListTile(
              value: isChecked,
              dense: true,
              activeColor: theme.colorScheme.primary,
              title: Text(
                (isAr && service.nameAr != null) ? service.nameAr! : service.name,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
              ),
              subtitle: Text(
                '${service.durationMins} ${isAr ? "دقيقة" : "mins"}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              secondary: Text(
                '${service.price.toStringAsFixed(0)} ${isAr ? "ج.م" : "EGP"}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedServiceIds.add(service.id);
                  } else {
                    // Keep at least one service selected
                    if (_selectedServiceIds.length > 1) {
                      _selectedServiceIds.remove(service.id);
                    }
                  }
                });
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAddonsSection(ThemeData theme, bool isAr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isAr ? 'إضافات ومشروبات' : 'Add-ons & Equipment',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.unit.addons.map((addon) {
            final isChecked = _selectedAddonIds.contains(addon.id);
            return FilterChip(
              label: Text(
                '${(isAr && addon.nameAr != null) ? addon.nameAr! : addon.name} (+${addon.price.toStringAsFixed(0)} EGP)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isChecked ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isChecked,
              selectedColor: theme.colorScheme.primary.withValues(alpha: 0.3),
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedAddonIds.add(addon.id);
                  } else {
                    _selectedAddonIds.remove(addon.id);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  // Principle 4: The Contrast Effect (Price Anchoring)
  Widget _buildContrastAnchoredBottomBar(
      ThemeData theme, bool isAr, PricingCalculationResult pricing) {
    final total = pricing.totalPriceEgp.toStringAsFixed(0);
    final perPerson = pricing.perPersonShareEgp.toStringAsFixed(0);
    final deposit = pricing.depositRequiredEgp.toStringAsFixed(0);
    final remaining = pricing.remainingCashAtVenueEgp.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hero Anchor: Total Value + Per-Person Split
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isAr
                    ? 'إجمالي الحجز: $total ج.م ($_headcount أفراد • $perPerson ج.م/فرد)'
                    : 'Total Value: $total EGP ($_headcount Players • $perPerson EGP/ea)',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Deposit Hold Callout
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_clock_rounded,
                      size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(
                    isAr
                      ? 'تأكيد الحجز الآن: $deposit ج.م فقط'
                      : 'Lock Instant Hold Now: $deposit EGP only',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Text(
                isAr ? 'الباقي $remaining ج.م كاش بالمكان' : 'Remaining $remaining EGP at venue',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Dynamic Primary CTA (Principle 2: Reciprocity + IKEA Effect)
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: () => _handleLockAndProceed(pricing),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isAr
                    ? 'احجز مكانك وولّد لينك الشلة ←'
                    : 'Lock My Slot & Generate Invite Link →',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleLockAndProceed(PricingCalculationResult pricing) {
    final booking = HagzyBooking(
      id: 'bk_${DateTime.now().millisecondsSinceEpoch}',
      unitId: widget.unit.id,
      venueId: widget.venue.id,
      hostUserId: 'current_user',
      startTime: _selectedStart,
      endTime: _selectedStart.add(Duration(minutes: pricing.totalDurationMins)),
      headcount: _headcount,
      selectedServices: widget.unit.serviceMenu
          .where((s) => _selectedServiceIds.contains(s.id))
          .toList(),
      selectedAddons: widget.unit.addons
          .where((a) => _selectedAddonIds.contains(a.id))
          .toList(),
      isOpenLobby: false,
      totalSlots: _headcount,
      filledSlots: 1,
      neededRoles: const [],
      lobbyTitle: null,
      totalPriceEgp: pricing.totalPriceEgp,
      depositRequiredEgp: pricing.depositRequiredEgp,
      serviceFeeEgp: pricing.serviceFeeEgp,
      status: BookingStatus.pendingDeposit,
      createdAt: DateTime.now(),
      venueName: widget.venue.name,
      unitName: widget.unit.unitName,
      venueCity: widget.venue.city,
    );

    Navigator.of(context).pop();
    widget.onLockSlotAndProceed(booking);
  }

  Future<void> _pickTime() async {
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedStart),
    );
    if (pickedTime != null) {
      setState(() {
        _selectedStart = DateTime(
          _selectedStart.year,
          _selectedStart.month,
          _selectedStart.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      });
    }
  }
}
