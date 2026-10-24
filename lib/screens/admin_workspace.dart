import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';

class AdminManageWorkspace extends StatefulWidget {
  const AdminManageWorkspace({
    super.key,
    required this.venues,
    required this.bookings,
    required this.onAddVenue,
    required this.onEditVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onRemoveService,
    required this.onDelete,
    required this.onRemoveItem,
    required this.onWalkIn,
    this.onBlockSlot,
    required this.onCancel,
    required this.onConfirm,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue> onEditVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final void Function(Venue venue, SalonService service) onRemoveService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final void Function(Venue venue, VenueItem item, DateTime start, int duration, String reason)? onBlockSlot;
  final ValueChanged<Booking> onCancel;
  final ValueChanged<Booking> onConfirm;

  @override
  State<AdminManageWorkspace> createState() => _AdminManageWorkspaceState();
}

class _AdminManageWorkspaceState extends State<AdminManageWorkspace> {
  int _section = 0;

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        widget.bookings.where((b) => b.isPendingPayment).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              CustomPill(
                label: 'Manage venues',
                icon: Icons.storefront_outlined,
                selected: _section == 0,
                onTap: () => setState(() => _section = 0),
              ),
              CustomPill(
                label: 'POS timeline',
                icon: Icons.view_timeline_outlined,
                selected: _section == 1,
                onTap: () => setState(() => _section = 1),
              ),
              CustomPill(
                label: pendingCount > 0
                    ? 'Analytics ($pendingCount pending)'
                    : 'Analytics',
                icon: Icons.insights_rounded,
                selected: _section == 2,
                onTap: () => setState(() => _section = 2),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (_section) {
            0 => ManageTab(
                venues: widget.venues,
                onAddVenue: widget.onAddVenue,
                onEditVenue: widget.onEditVenue,
                onAddItem: widget.onAddItem,
                onAddService: widget.onAddService,
                onRemoveService: widget.onRemoveService,
                onDelete: widget.onDelete,
                onRemoveItem: widget.onRemoveItem,
              ),
            1 => PosTab(
                venues: widget.venues,
                bookings: widget.bookings,
                onWalkIn: widget.onWalkIn,
                onBlockSlot: widget.onBlockSlot,
                onCancel: widget.onCancel,
                onConfirm: widget.onConfirm,
              ),
            _ => AnalyticsTab(
                venues: widget.venues,
                bookings: widget.bookings,
              ),
          },
        ),
      ],
    );
  }
}

class ManageTab extends StatelessWidget {
  const ManageTab({
    super.key,
    required this.venues,
    required this.onAddVenue,
    required this.onEditVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onRemoveService,
    required this.onDelete,
    required this.onRemoveItem,
  });

  final List<Venue> venues;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue> onEditVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final void Function(Venue venue, SalonService service) onRemoveService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          IntroCard(
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
            const EmptyCard(
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
                          IconBox(icon: venue.type.icon),
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
                                    style: const TextStyle(color: kMuted)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit venue',
                            onPressed: () => onEditVenue(venue),
                            icon: const Icon(Icons.edit_outlined, color: kGreen),
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
                              style: const TextStyle(color: kMuted)),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Owner phone: ${venue.ownerPhone.isEmpty ? 'Not provided' : venue.ownerPhone} · '
                          'Deposit policy: ${formatMoney(venue.depositPercent)}% · '
                          'Hours: ${venue.openHour}:00–${venue.closeHour}:00',
                          style: const TextStyle(color: kMuted, fontSize: 12.5),
                        ),
                      ),
                      if (venue.instaPayAddress.isNotEmpty ||
                          venue.vodafoneCashNumber.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            [
                              if (venue.instaPayAddress.isNotEmpty)
                                'InstaPay: ${venue.instaPayAddress}',
                              if (venue.vodafoneCashNumber.isNotEmpty)
                                'Vodafone Cash: ${venue.vodafoneCashNumber}',
                            ].join(' · '),
                            style: const TextStyle(
                              color: kGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
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
                                '${formatMoney(item.hourlyRate)} EGP${item.multiRate > 0 ? ' / ${formatMoney(item.multiRate)} multi' : ''}'),
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
                              leading: const Icon(Icons.content_cut, size: 18),
                              title: Text(service.name),
                              subtitle: Text(
                                  '${service.minutes} minutes · ${formatMoney(service.price)} EGP'),
                              trailing: IconButton(
                                tooltip: 'Remove service',
                                icon: const Icon(Icons.remove_circle_outline,
                                    size: 18),
                                onPressed: () =>
                                    onRemoveService(venue, service),
                              ),
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

class PosTab extends StatefulWidget {
  const PosTab({
    super.key,
    required this.venues,
    required this.bookings,
    required this.onWalkIn,
    this.onBlockSlot,
    required this.onCancel,
    required this.onConfirm,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final void Function(Venue venue, VenueItem item, DateTime start, int duration, String reason)? onBlockSlot;
  final ValueChanged<Booking> onCancel;
  final ValueChanged<Booking> onConfirm;

  @override
  State<PosTab> createState() => _PosTabState();
}

class _PosTabState extends State<PosTab> {
  String _filter = 'all'; // 'all', 'pending', 'confirmed'

  Future<void> _messageCustomer(Booking booking) async {
    final digits = booking.phone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final phone = digits.startsWith('0') ? '2$digits' : digits;
    final uri = Uri.https('wa.me', '/$phone', {
      'text':
          'Hello ${booking.customer}, regarding your Hagzy reservation on ${formatDateTime(booking.startsAt)}.',
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openBlockSlotDialog(Venue venue, VenueItem item) async {
    const reasons = [
      'Maintenance / صيانة دورية',
      'Private Tournament / بطولة خاصة',
      'Walk-in Customer / حجز مباشر أو تليفوني',
      'VIP Closure / مغلق لحجز خاص',
    ];
    var chosenReason = reasons.first;
    var duration = 60;
    var date = DateTime.now();
    var time = TimeOfDay.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock_clock_outlined, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Block Slot · ${item.name}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Prevent online customers from reserving this time slot:',
                    style: TextStyle(fontSize: 12, color: kMuted)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: chosenReason,
                  decoration: const InputDecoration(
                    labelText: 'Block Reason / سبب الإغلاق',
                    filled: true,
                    fillColor: kPage,
                  ),
                  items: reasons
                      .map((r) => DropdownMenuItem(
                          value: r,
                          child:
                              Text(r, style: const TextStyle(fontSize: 12.5))))
                      .toList(),
                  onChanged: (v) =>
                      setDlgState(() => chosenReason = v ?? reasons.first),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event, color: kGreen),
                  title: Text(
                    '${date.day}/${date.month}/${date.year} · ${time.format(ctx)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      final chosenD = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 1)),
                        lastDate: DateTime.now().add(const Duration(days: 90)),
                      );
                      if (chosenD != null) {
                        setDlgState(() => date = chosenD);
                        if (!ctx.mounted) return;
                        final chosenT = await showTimePicker(
                            context: ctx, initialTime: time);
                        if (chosenT != null) setDlgState(() => time = chosenT);
                      }
                    },
                    child: const Text('Change'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Duration:',
                    style: TextStyle(fontSize: 12, color: kMuted)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [60, 90, 120, 180, 240].map((d) {
                    final label = d < 60 ? '${d}m' : '${d ~/ 60}h';
                    return ChoiceChip(
                      label: Text(label),
                      selected: duration == d,
                      onSelected: (_) => setDlgState(() => duration = d),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD97706),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Lock Slot'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && widget.onBlockSlot != null) {
      final start =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
      widget.onBlockSlot!(venue, item, start, duration, chosenReason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allActive = widget.bookings
        .where((booking) =>
            booking.blocksAvailability &&
            booking.endsAt.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    final active = allActive.where((b) {
      if (_filter == 'pending') return b.isPendingPayment;
      if (_filter == 'confirmed') return b.isConfirmed;
      return true;
    }).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        IntroCard(
          title: 'POS timeline',
          subtitle: 'Confirmed bookings and temporary unpaid holds.',
          icon: Icons.view_timeline_outlined,
          action: allActive.isEmpty
              ? null
              : Text('${allActive.length} active',
                  style: const TextStyle(
                      color: kGreen, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 14),
        if (widget.venues.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Walk-in & Slot Blocker',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...widget.venues.expand((venue) => venue.items.map(
                        (item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${venue.name} · ${item.name}'),
                          subtitle: Text(item.kind),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.outlined(
                                tooltip: 'Block slot / تقفيل موعد',
                                onPressed: () =>
                                    _openBlockSlotDialog(venue, item),
                                icon: const Icon(Icons.lock_clock_outlined,
                                    size: 18, color: Color(0xFFD97706)),
                              ),
                              const SizedBox(width: 6),
                              IconButton.filledTonal(
                                tooltip: 'Add walk-in',
                                onPressed: () => widget.onWalkIn(venue, item),
                                icon: const Icon(Icons.person_add_alt_1),
                              ),
                            ],
                          ),
                        ),
                      )),
                  if (widget.venues.every((venue) => venue.items.isEmpty))
                    const Text('Add bookable spaces in Manage venues.'),
                ],
              ),
            ),
          ),
        if (allActive.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              CustomPill(
                label: 'All (${allActive.length})',
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              CustomPill(
                label:
                    'Pending Deposit (${allActive.where((b) => b.isPendingPayment).length})',
                selected: _filter == 'pending',
                onTap: () => setState(() => _filter = 'pending'),
              ),
              CustomPill(
                label:
                    'Confirmed (${allActive.where((b) => b.isConfirmed).length})',
                selected: _filter == 'confirmed',
                onTap: () => setState(() => _filter = 'confirmed'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (active.isEmpty)
          const EmptyCard(
            icon: Icons.event_note_outlined,
            title: 'No active bookings',
            body: 'New customer and walk-in bookings appear here.',
          ),
        ...active.map((booking) {
          final venue =
              widget.venues.where((value) => value.id == booking.venueId);
          final item = venue.isEmpty
              ? null
              : venue.first.items
                  .where((value) => value.id == booking.itemId)
                  .firstOrNull;
          final proofInfo = booking.paymentReference.isNotEmpty
              ? '\nPayment Proof (${booking.paymentMethod.toUpperCase()}): ${booking.paymentReference}'
              : '';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (booking.isBlocked)
                    Container(
                      margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 15, color: Color(0xFFB45309)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'LOCKED / موعد مغلق: ${booking.blockReason.isNotEmpty ? booking.blockReason : booking.customer}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFB45309),
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () => widget.onCancel(booking),
                            child: const Text('Unblock / فتح الموعد',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFFB45309))),
                          ),
                        ],
                      ),
                    ),
                  ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: const IconBox(icon: Icons.event_available),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(booking.customer,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (booking.phone.isNotEmpty)
                          Text(
                            booking.phone,
                            style: const TextStyle(fontSize: 12, color: kMuted),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      '${venue.isEmpty ? 'Venue' : venue.first.name} · ${item?.name ?? 'Resource'}\n'
                      '${formatDateTime(booking.startsAt)} – ${TimeOfDay.fromDateTime(booking.endsAt).format(context)} · '
                      '${booking.durationMinutes} min'
                      '${booking.serviceNames.isEmpty ? '' : '\n${booking.serviceNames.join(' + ')}'}'
                      '${booking.splitCount > 1 ? '\n${booking.splitCount}-way · ${formatMoney(booking.price / booking.splitCount)} EGP each' : ''}'
                      '$proofInfo'
                      '${booking.isPendingPayment ? '\nAwaiting deposit · not confirmed' : '\nConfirmed by venue'}',
                    ),
                    isThreeLine: true,
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${formatMoney(booking.price)} EGP',
                            style: const TextStyle(
                                color: kGreen, fontWeight: FontWeight.bold)),
                        IconButton(
                          tooltip: 'Cancel booking',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => widget.onCancel(booking),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                  if (booking.isPendingPayment || booking.phone.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          if (booking.isPendingPayment)
                            FilledButton.tonalIcon(
                              onPressed: () => widget.onConfirm(booking),
                              icon: const Icon(Icons.check_circle_outline,
                                  size: 16),
                              label: Text(
                                booking.paymentReference.isNotEmpty
                                    ? 'Verify & Confirm Deposit'
                                    : 'Confirm Deposit (${formatMoney(booking.dueNow ?? 0)} EGP)',
                              ),
                            ),
                          if (booking.phone.isNotEmpty)
                            OutlinedButton.icon(
                              onPressed: () => _messageCustomer(booking),
                              icon: const Icon(Icons.chat_outlined, size: 16),
                              label: const Text('WhatsApp Customer'),
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
    );
  }
}

class AnalyticsTab extends StatelessWidget {
  const AnalyticsTab({
    super.key,
    required this.venues,
    required this.bookings,
  });

  final List<Venue> venues;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final activeBookings = bookings.where((b) => !b.cancelled).toList();
    final confirmedBookings =
        activeBookings.where((b) => b.isConfirmed).toList();
    final pendingBookings =
        activeBookings.where((b) => b.isPendingPayment).toList();

    final confirmedRevenue =
        confirmedBookings.fold<double>(0, (sum, b) => sum + b.price);
    final depositsCollected = confirmedBookings.fold<double>(
        0, (sum, b) => sum + (b.dueNow ?? b.price));
    final pendingPipeline =
        pendingBookings.fold<double>(0, (sum, b) => sum + b.price);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const IntroCard(
          title: 'Revenue & Analytics',
          subtitle:
              'Real-time performance across your venues, spaces, and deposits.',
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              title: 'Confirmed Revenue',
              value: '${formatMoney(confirmedRevenue)} EGP',
              subtitle: '${confirmedBookings.length} confirmed bookings',
              icon: Icons.payments_outlined,
              color: kGreen,
            ),
            _MetricCard(
              title: 'Deposits Verified',
              value: '${formatMoney(depositsCollected)} EGP',
              subtitle: 'Collected upfront',
              icon: Icons.verified_outlined,
              color: const Color(0xFF0284C7),
            ),
            _MetricCard(
              title: 'Pending Holds',
              value: '${pendingBookings.length}',
              subtitle: '${formatMoney(pendingPipeline)} EGP pipeline',
              icon: Icons.hourglass_top_rounded,
              color: const Color(0xFFD97706),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const Text(
          'Performance by Venue',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (venues.isEmpty)
          const EmptyCard(
            icon: Icons.storefront_outlined,
            title: 'No Venues Yet',
            body: 'Add a venue to track bookings and revenue.',
          )
        else
          ...venues.map((v) {
            final vBookings =
                activeBookings.where((b) => b.venueId == v.id).toList();
            final vConfirmed = vBookings.where((b) => b.isConfirmed).toList();
            final vRev =
                vConfirmed.fold<double>(0, (sum, b) => sum + b.price);
            final share = confirmedRevenue > 0
                ? (vRev / confirmedRevenue).clamp(0.08, 1.0)
                : 0.12;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    ListTile(
                      leading: IconBox(icon: v.type.icon),
                      title: Text(v.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, color: kInk)),
                      subtitle: Text(
                        '${vConfirmed.length} confirmed · ${vBookings.where((b) => b.isPendingPayment).length} pending holds',
                      ),
                      trailing: Text(
                        '${formatMoney(vRev)} EGP',
                        style: const TextStyle(
                          color: kGreen,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 6,
                          backgroundColor: kPage,
                          color: kGreen,
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 224,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: kPanel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: kBorder),
          boxShadow: HagzyTheme.softShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 21,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                color: kMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class PaymentTab extends StatelessWidget {
  const PaymentTab({
    super.key,
    required this.apiConfigured,
    required this.localPreview,
  });

  final bool apiConfigured;
  final bool localPreview;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          const IntroCard(
            title: 'Payments & deposits',
            subtitle:
                'Payment credentials belong on the trusted Hagzy server, never in this app.',
            icon: Icons.lock_outline,
          ),
          const SizedBox(height: 12),
          if (!apiConfigured || localPreview) const LocalPreviewNotice(),
          if (apiConfigured && !localPreview)
            const Card(
              child: ListTile(
                leading: Icon(Icons.cloud_done_outlined, color: kGreen),
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
                      style: TextStyle(color: kMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('InstaPay & Vodafone Cash',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text(
                      'InstaPay and Vodafone Cash transfers require manual instructions and verification. Configure your venue InstaPay address or Vodafone Cash wallet in Manage Venues; customers can submit their transfer reference, and you can verify and confirm their deposit in the POS timeline.',
                      style: TextStyle(color: kMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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
                      style: TextStyle(color: kMuted)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
              'Reservations remain unpaid/pending until a trusted provider confirmation or venue owner verification updates their status.',
              style: TextStyle(color: kMuted, fontSize: 12)),
        ],
      );
}

