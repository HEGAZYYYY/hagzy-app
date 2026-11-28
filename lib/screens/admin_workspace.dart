import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../theme/hagzy_theme.dart';
import '../widgets/common_widgets.dart';
import '../core/models/models_v2.dart';
import '../features/merchant_portal/merchant_portal.dart';

String _t(String en, String ar) => localized(isArabicMode, en, ar);

Venue venueFromHagzyVenue(HagzyVenue v) {
  VenueType type = VenueType.sports;
  if (v.categories.contains('barber') || v.categories.contains('grooming')) {
    type = VenueType.salon;
  } else if (v.categories.contains('playstation') ||
      v.categories.contains('billiards') ||
      v.categories.contains('entertainment')) {
    type = VenueType.lounge;
  }

  return Venue(
    id: v.id,
    name: v.name,
    location: (v.address != null && v.address!.isNotEmpty) ? v.address! : v.city,
    type: type,
    ownerId: v.ownerId,
    ownerPhone: v.walletNumber ?? v.phone ?? '',
    depositPercent: 25.0,
    instaPayAddress: v.instapayAddress ?? '',
    vodafoneCashNumber: v.walletNumber ?? '',
    items: v.units
        .map((u) => VenueItem(
              id: u.id,
              name: u.unitName,
              kind: u.category,
              hourlyRate: u.basePriceEgp,
            ))
        .toList(),
  );
}

class AdminManageWorkspace extends StatefulWidget {
  const AdminManageWorkspace({
    super.key,
    required this.venues,
    required this.bookings,
    this.ownerId,
    this.isSingularPartner = false,
    this.partnerRequests = const [],
    this.onApprovePartnerRequest,
    this.onRejectPartnerRequest,
    this.onRefreshPartnerRequests,
    this.apiConfigured = false,
    this.localPreview = true,
    this.onLoadGatewayStatus,
    this.onLoadReviewQueue,
    this.onAttachReviewItem,
    this.adminNotifications = const [],
    this.onMarkNotificationRead,
    this.onVerifyBookingQr,
    this.onCheckInBooking,
    required this.onAddVenue,
    this.onAddVenueModel,
    required this.onEditVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onRemoveService,
    required this.onDelete,
    required this.onRemoveItem,
    required this.onWalkIn,
    this.onBlockSlot,
    this.onSyncFirebase,
    this.onLoadUsers,
    required this.onCancel,
    required this.onConfirm,
    this.archivedVenues = const [],
    this.onRestoreVenue,
    this.onPermanentDeleteVenue,
  });

  final List<Venue> venues;
  final List<Venue> archivedVenues;
  final ValueChanged<Venue>? onRestoreVenue;
  final ValueChanged<Venue>? onPermanentDeleteVenue;
  final List<Booking> bookings;
  final String? ownerId;
  final bool isSingularPartner;
  final List<Map<String, dynamic>> partnerRequests;
  final Future<void> Function(String requestId)? onApprovePartnerRequest;
  final Future<void> Function(String requestId)? onRejectPartnerRequest;
  final VoidCallback? onRefreshPartnerRequests;
  final bool apiConfigured;
  final bool localPreview;
  final Future<Map<String, dynamic>> Function()? onLoadGatewayStatus;
  final Future<List<Map<String, dynamic>>> Function()? onLoadReviewQueue;
  final Future<void> Function(String itemId, String bookingId)?
      onAttachReviewItem;
  final List<Map<String, dynamic>> adminNotifications;
  final Future<void> Function(String notificationId)? onMarkNotificationRead;
  final Future<Map<String, dynamic>> Function(String bookingId, String? sig)?
      onVerifyBookingQr;
  final Future<void> Function(String bookingId, String? sig)? onCheckInBooking;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue>? onAddVenueModel;
  final ValueChanged<Venue> onEditVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final void Function(Venue venue, SalonService service) onRemoveService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final void Function(Venue venue, VenueItem item, DateTime start, int duration, String reason)? onBlockSlot;
  final VoidCallback? onSyncFirebase;
  final Future<List<Map<String, dynamic>>> Function()? onLoadUsers;
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
    final confirmedCount =
        widget.bookings.where((b) => !b.cancelled && !b.isPendingPayment).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              _AdminKpiTile(
                label: _t('Bookings', 'الحجوزات'),
                value: '${widget.bookings.length}',
                accent: kInk,
              ),
              const SizedBox(width: 8),
              _AdminKpiTile(
                label: _t('Confirmed', 'المؤكدة'),
                value: '$confirmedCount',
                accent: kGreenDark,
              ),
              const SizedBox(width: 8),
              _AdminKpiTile(
                label: _t('Pending', 'قيد الانتظار'),
                value: '$pendingCount',
                accent: pendingCount > 0 ? const Color(0xFFD97706) : kMuted,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              CustomPill(
                label: _t('Manage venues', 'إدارة الأماكن'),
                icon: Icons.storefront_outlined,
                selected: _section == 0,
                onTap: () => setState(() => _section = 0),
              ),
              CustomPill(
                label: _t('POS timeline', 'المواعيد ونقاط البيع'),
                icon: Icons.view_timeline_outlined,
                selected: _section == 1,
                onTap: () => setState(() => _section = 1),
              ),
              CustomPill(
                label: pendingCount > 0
                    ? _t('Analytics ($pendingCount pending)', 'التقارير ($pendingCount معلق)')
                    : _t('Analytics', 'الأرباح والتقارير'),
                icon: Icons.insights_rounded,
                selected: _section == 2,
                onTap: () => setState(() => _section = 2),
              ),
              CustomPill(
                label: _t('Users & CRM', 'العملاء وإدارة الحسابات'),
                icon: Icons.people_alt_rounded,
                selected: _section == 3,
                onTap: () => setState(() => _section = 3),
              ),
              CustomPill(
                label: _t('Gateway & Queue', 'بوابة الدفع والمراجعة'),
                icon: Icons.bolt_rounded,
                selected: _section == 4,
                onTap: () => setState(() => _section = 4),
              ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.025),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: switch (_section) {
              0 => ManageTab(
                  key: const ValueKey('admin_manage'),
                  venues: widget.venues,
                  archivedVenues: widget.archivedVenues,
                  onRestoreVenue: widget.onRestoreVenue,
                  onPermanentDeleteVenue: widget.onPermanentDeleteVenue,
                  ownerId: widget.ownerId,
                  isSingularPartner: widget.isSingularPartner,
                  partnerRequests: widget.partnerRequests,
                  onApprovePartnerRequest: widget.onApprovePartnerRequest,
                  onRejectPartnerRequest: widget.onRejectPartnerRequest,
                  onRefreshPartnerRequests: widget.onRefreshPartnerRequests,
                  onAddVenue: widget.onAddVenue,
                  onAddVenueModel: widget.onAddVenueModel,
                  onEditVenue: widget.onEditVenue,
                  onAddItem: widget.onAddItem,
                  onAddService: widget.onAddService,
                  onRemoveService: widget.onRemoveService,
                  onDelete: widget.onDelete,
                  onRemoveItem: widget.onRemoveItem,
                  onSyncFirebase: widget.onSyncFirebase,
                ),
              1 => PosTab(
                  key: const ValueKey('admin_pos'),
                  venues: widget.venues,
                  bookings: widget.bookings,
                  adminNotifications: widget.adminNotifications,
                  onMarkNotificationRead: widget.onMarkNotificationRead,
                  onVerifyBookingQr: widget.onVerifyBookingQr,
                  onCheckInBooking: widget.onCheckInBooking,
                  onWalkIn: widget.onWalkIn,
                  onBlockSlot: widget.onBlockSlot,
                  onCancel: widget.onCancel,
                  onConfirm: widget.onConfirm,
                ),
              2 => AnalyticsTab(
                  key: const ValueKey('admin_analytics'),
                  venues: widget.venues,
                  bookings: widget.bookings,
                ),
              4 => PaymentTab(
                  key: const ValueKey('admin_payment_gateway'),
                  apiConfigured: widget.apiConfigured,
                  localPreview: widget.localPreview,
                  bookings: widget.bookings,
                  onLoadGatewayStatus: widget.onLoadGatewayStatus,
                  onLoadReviewQueue: widget.onLoadReviewQueue,
                  onAttachReviewItem: widget.onAttachReviewItem,
                ),
              _ => UsersCrmTab(
                  key: const ValueKey('admin_users_crm'),
                  venues: widget.venues,
                  bookings: widget.bookings,
                  onLoadUsers: widget.onLoadUsers,
                  onConfirm: widget.onConfirm,
                  onCancel: widget.onCancel,
                ),
            },
          ),
        ),
      ],
    );
  }
}

class ManageTab extends StatefulWidget {
  const ManageTab({
    super.key,
    required this.venues,
    this.archivedVenues = const [],
    this.onRestoreVenue,
    this.onPermanentDeleteVenue,
    this.ownerId,
    this.isSingularPartner = false,
    this.partnerRequests = const [],
    this.onApprovePartnerRequest,
    this.onRejectPartnerRequest,
    this.onRefreshPartnerRequests,
    required this.onAddVenue,
    this.onAddVenueModel,
    required this.onEditVenue,
    required this.onAddItem,
    required this.onAddService,
    required this.onRemoveService,
    required this.onDelete,
    required this.onRemoveItem,
    this.onSyncFirebase,
    this.onExploreCustomerApp,
  });

  final List<Venue> venues;
  final List<Venue> archivedVenues;
  final ValueChanged<Venue>? onRestoreVenue;
  final ValueChanged<Venue>? onPermanentDeleteVenue;
  final String? ownerId;
  final bool isSingularPartner;
  final List<Map<String, dynamic>> partnerRequests;
  final Future<void> Function(String requestId)? onApprovePartnerRequest;
  final Future<void> Function(String requestId)? onRejectPartnerRequest;
  final VoidCallback? onRefreshPartnerRequests;
  final VoidCallback onAddVenue;
  final ValueChanged<Venue>? onAddVenueModel;
  final ValueChanged<Venue> onEditVenue;
  final ValueChanged<Venue> onAddItem;
  final ValueChanged<Venue> onAddService;
  final void Function(Venue venue, SalonService service) onRemoveService;
  final ValueChanged<Venue> onDelete;
  final void Function(Venue venue, VenueItem item) onRemoveItem;
  final VoidCallback? onSyncFirebase;
  final VoidCallback? onExploreCustomerApp;

  @override
  State<ManageTab> createState() => _ManageTabState();
}

class _ManageTabState extends State<ManageTab> {
  VenueType? _filterType;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final activeList = _filterType == null
        ? widget.venues
        : widget.venues.where((v) => v.type == _filterType).toList();
    final archivedList = _filterType == null
        ? widget.archivedVenues
        : widget.archivedVenues.where((v) => v.type == _filterType).toList();
    final filteredVenues = _showArchived ? archivedList : activeList;
    final pendingRequests = widget.partnerRequests
        .where((r) => (r['status'] ?? 'pending') == 'pending')
        .toList();

    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 8,
        isWide ? 24 : 16,
        36,
      ),
      children: [
        if (!widget.isSingularPartner &&
            (pendingRequests.isNotEmpty || widget.onRefreshPartnerRequests != null)) ...[
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_user_outlined, color: kGreen),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Partner Requests (${pendingRequests.length} pending)',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (widget.onRefreshPartnerRequests != null)
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          tooltip: 'Refresh partner requests',
                          onPressed: widget.onRefreshPartnerRequests,
                        ),
                    ],
                  ),
                  if (pendingRequests.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'No pending venue owner verification requests.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    )
                  else
                    ...pendingRequests.map((req) {
                      final reqId = (req['id'] ?? '').toString();
                      final venueName = (req['venueName'] ?? 'Venue').toString();
                      final ownerName = (req['ownerName'] ?? '').toString();
                      final contact = [
                        (req['email'] ?? '').toString(),
                        (req['phone'] ?? '').toString(),
                      ].where((s) => s.isNotEmpty).join(' · ');
                      final city = (req['city'] ?? '').toString();
                      final venueType = (req['venueType'] ?? '').toString();
                      return Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kSurfaceTint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              venueName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if (ownerName.isNotEmpty) ownerName,
                                if (venueType.isNotEmpty) venueType,
                                if (city.isNotEmpty) city,
                              ].join(' • '),
                              style: TextStyle(fontSize: 12.5, color: kMuted),
                            ),
                            if (contact.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                contact,
                                style: TextStyle(fontSize: 12, color: kMuted),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (widget.onApprovePartnerRequest != null)
                                  FilledButton.icon(
                                    onPressed: () =>
                                        widget.onApprovePartnerRequest!(reqId),
                                    icon: const Icon(Icons.check_rounded, size: 16),
                                    label: const Text('Approve'),
                                  ),
                                const SizedBox(width: 8),
                                if (widget.onRejectPartnerRequest != null)
                                  OutlinedButton(
                                    onPressed: () =>
                                        widget.onRejectPartnerRequest!(reqId),
                                    child: const Text('Reject'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
        HagzySegmentedTabBar(
          selectedIndex: _showArchived ? 1 : 0,
          onChanged: (idx) => setState(() => _showArchived = idx == 1),
          items: [
            (
              label: _t('Active Places (${widget.venues.length})',
                  'الأماكن النشطة (${widget.venues.length})'),
              icon: Icons.storefront_rounded,
              count: null,
            ),
            (
              label: _t('Trash / Archived (${widget.archivedVenues.length})',
                  'الأرشيف (${widget.archivedVenues.length})'),
              icon: Icons.delete_outline_rounded,
              count: null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_showArchived)
          const IntroCard(
            title: 'Trash / Archived Venues',
            subtitle: 'Venues in trash are completely hidden from customer search and booking tabs. You can restore them anytime or permanently delete them.',
            icon: Icons.delete_sweep_outlined,
          )
        else
          IntroCard(
            title: widget.isSingularPartner
                ? 'My Venue Dashboard'
                : 'Your self-service builder',
            subtitle: widget.isSingularPartner
                ? 'Manage your venue details, bookable spaces, services, and pricing.'
                : 'Add a venue after contacting its owner, then list bookable spaces and services.',
            icon: Icons.add_business_outlined,
            action: widget.isSingularPartner
                ? null
                : FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccentSurface,
                      foregroundColor: kAccentOnSurface,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusSmall + 2),
                      ),
                    ),
                    onPressed: widget.onAddVenue,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add venue',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
          ),
        if (!widget.isSingularPartner && (_showArchived ? widget.archivedVenues.length : widget.venues.length) > 1) ...[
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                CustomPill(
                  label: 'All (${_showArchived ? widget.archivedVenues.length : widget.venues.length})',
                  selected: _filterType == null,
                  onTap: () => setState(() => _filterType = null),
                ),
                const SizedBox(width: 6),
                ...VenueType.values.map((t) {
                  final src = _showArchived ? widget.archivedVenues : widget.venues;
                  final count = src.where((v) => v.type == t).length;
                  if (count == 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: CustomPill(
                      label: '${t.label} ($count)',
                      icon: t.icon,
                      selected: _filterType == t,
                      onTap: () => setState(() =>
                          _filterType = _filterType == t ? null : t),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (filteredVenues.isEmpty) ...[
          EmptyCard(
            icon: _showArchived ? Icons.delete_sweep_outlined : Icons.add_business_outlined,
            title: _showArchived
                ? 'Trash is empty'
                : (widget.isSingularPartner ? 'No venue assigned yet' : 'Build your first venue'),
            body: _showArchived
                ? 'No venues currently in trash. When you delete a venue, it is moved here safely so you can restore it anytime.'
                : (widget.isSingularPartner
                    ? 'Your approved venue will appear here automatically. Contact platform support if you need assistance.'
                    : 'Choose a venue type, add spaces or chairs, then set prices.'),
          ),
          if (!_showArchived && !widget.isSingularPartner) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: kAccentSurface,
                      foregroundColor: kAccentOnSurface,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(HagzyTokens.radiusMedium),
                      ),
                    ),
                    onPressed: widget.onAddVenue,
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: const Text('Add Your Venue',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    hagzyPageRoute(
                      builder: (ctx) => GoalGradientOnboardingScreen(
                        ownerId: widget.ownerId ?? 'owner',
                        onVenueCreated: (newHagzyVenue) {
                          Navigator.pop(ctx);
                          final created = venueFromHagzyVenue(newHagzyVenue);
                          if (widget.onAddVenueModel != null) {
                            widget.onAddVenueModel!(created);
                          } else {
                            widget.onAddVenue();
                          }
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.add_business_rounded, size: 16),
                label: const Text('Step-by-Step Venue Setup'),
              ),
            ),
            if (widget.onExploreCustomerApp != null) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: widget.onExploreCustomerApp,
                  icon: const Icon(Icons.explore_rounded, size: 18),
                  label: const Text('Browse Places as Customer (تصفح كعميل)', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ],
        ],
        ...filteredVenues.map((venue) => HagzySurfaceCard(
              margin: const EdgeInsets.only(bottom: 12),
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
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17,
                                      color: kInk)),
                              Text(venue.type.label,
                                  style: TextStyle(color: kMuted)),
                              if (_showArchived) ...[
                                const SizedBox(height: 4),
                                const HagzyStatusBadge(
                                  label: 'In Trash · Hidden from Customers',
                                  tone: HagzyStatusTone.warning,
                                  icon: Icons.archive_outlined,
                                  compact: true,
                                ),
                              ],
                              if (!widget.isSingularPartner &&
                                  (venue.ownerEmail.isNotEmpty ||
                                      venue.ownerPhone.isNotEmpty))
                                Text(
                                  'Owner: ${[
                                    if (venue.ownerEmail.isNotEmpty)
                                      venue.ownerEmail,
                                    if (venue.ownerPhone.isNotEmpty)
                                      venue.ownerPhone,
                                  ].join(' · ')}',
                                  style: TextStyle(
                                      fontSize: 12, color: kMuted),
                                ),
                            ],
                          ),
                        ),
                        if (_showArchived) ...[
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: kAccentSurface,
                              foregroundColor: kAccentOnSurface,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                widget.onRestoreVenue?.call(venue),
                            icon: const Icon(Icons.restore_from_trash_rounded,
                                size: 15),
                            label: const Text('Restore',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 12)),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            tooltip: 'Delete Forever',
                            onPressed: () {
                              showHagzyAdaptiveModal<void>(
                                context: context,
                                builder: (ctx, isSheet) => HagzyModalCard(
                                  isSheet: isSheet,
                                  centerHeader: true,
                                  destructive: true,
                                  icon: Icons.delete_forever_rounded,
                                  title: 'Delete Permanently?',
                                  subtitle:
                                      'Are you sure you want to permanently delete "${venue.name}"? This cannot be undone and will purge all data.',
                                  onClose: () => Navigator.pop(ctx),
                                  primaryUseFilledButton: true,
                                  primaryLabel: 'Delete Forever',
                                  onPrimary: () {
                                    Navigator.pop(ctx);
                                    widget.onPermanentDeleteVenue?.call(venue);
                                  },
                                  secondaryLabel: 'Cancel',
                                  onSecondary: () => Navigator.pop(ctx),
                                ),
                              );
                            },
                            icon: const Icon(Icons.delete_forever_rounded,
                                color: Colors.red),
                          ),
                        ] else ...[
                          IconButton(
                            tooltip: 'Print Table QR Standee',
                            onPressed: () {
                              Navigator.push(
                                context,
                                hagzyPageRoute(
                                  builder: (ctx) => QrStandeeGenerator(
                                    venue: HagzyVenue(
                                      id: venue.id,
                                      ownerId: venue.ownerPhone.isNotEmpty
                                          ? venue.ownerPhone
                                          : 'owner',
                                      name: venue.name,
                                      city: venue.location,
                                      categories: [venue.type.name],
                                      createdAt: DateTime.now(),
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: Icon(Icons.qr_code_rounded,
                                color: kGold),
                          ),
                          IconButton(
                            tooltip: 'Edit venue',
                            onPressed: () => widget.onEditVenue(venue),
                            icon: Icon(Icons.edit_outlined,
                                color: kDarkMode.value ? kVolt : kObsidian),
                          ),
                          IconButton(
                            tooltip: 'Move to Trash',
                            onPressed: () {
                              showHagzyAdaptiveModal<void>(
                                context: context,
                                builder: (ctx, isSheet) => HagzyModalCard(
                                  isSheet: isSheet,
                                  centerHeader: true,
                                  icon: Icons.archive_outlined,
                                  iconColor: Colors.amber.shade800,
                                  iconBackgroundColor: Colors.amber.shade800
                                      .withValues(alpha: 0.14),
                                  title: 'Move Venue to Trash?',
                                  subtitle:
                                      'Are you sure you want to move "${venue.name}" to Trash? It will be hidden from customer search and booking tabs immediately. You can restore it anytime from the Trash tab.',
                                  onClose: () => Navigator.pop(ctx),
                                  primaryUseFilledButton: true,
                                  primaryLabel: 'Move to Trash',
                                  onPrimary: () {
                                    Navigator.pop(ctx);
                                    widget.onDelete(venue);
                                  },
                                  secondaryLabel: 'Cancel',
                                  onSecondary: () => Navigator.pop(ctx),
                                ),
                              );
                            },
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                          ),
                        ],
                      ],
                    ),
                    if (venue.location.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(venue.location,
                            style: TextStyle(color: kMuted)),
                      ),
                    if (venue.description.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          venue.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: kMuted, fontSize: 12),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Owner phone: ${venue.ownerPhone.isEmpty ? 'Not provided' : venue.ownerPhone} · '
                        'Deposit policy: ${formatMoney(venue.depositPercent)}% · '
                        'Hours: ${venue.openHour}:00–${venue.closeHour}:00',
                        style: TextStyle(color: kMuted, fontSize: 12.5),
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
                          style: hagzyMonoStyle(
                            color: kDarkMode.value ? kVolt : kObsidian,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (venue.amenities.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: venue.amenities
                              .map((a) => HagzyMonoTag(
                                    label: a,
                                    backgroundColor: kSurfaceSubtle,
                                    foregroundColor: kInk,
                                    borderColor: kBorder,
                                  ))
                              .toList(),
                        ),
                      ),
                    const Divider(height: 24),
                    Text(
                      '${venue.items.length} bookable spaces · ${venue.services.length} services',
                      style: hagzyMonoStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: kMuted,
                      ),
                    ),
                    ...venue.items.map((item) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${item.name} · ${item.kind}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, color: kInk)),
                          subtitle: Text(
                              '${formatMoney(item.hourlyRate)} EGP${item.multiRate > 0 ? ' / ${formatMoney(item.multiRate)} multi' : ''}',
                              style: hagzyMonoStyle(
                                  fontSize: 12, color: kMuted)),
                          trailing: IconButton(
                            tooltip: 'Remove space',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () => widget.onRemoveItem(venue, item),
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
                                  widget.onRemoveService(venue, service),
                            ),
                          )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => widget.onAddItem(venue),
                          icon: const Icon(Icons.add_box_outlined),
                          label: Text(venue.type == VenueType.salon
                              ? 'Add chair'
                              : 'Add court / table'),
                        ),
                        if (venue.type == VenueType.salon)
                          OutlinedButton.icon(
                            onPressed: () => widget.onAddService(venue),
                            icon: const Icon(Icons.content_cut),
                            label: const Text('Add service'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => widget.onEditVenue(venue),
                          icon: const Icon(Icons.auto_fix_high_rounded,
                              size: 18),
                          label: const Text('Renovate / Edit'),
                        ),
                      ],
                    ),
                  ],
                ),
            )),
        if (filteredVenues.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  hagzyPageRoute(
                    builder: (ctx) => GoalGradientOnboardingScreen(
                      ownerId: widget.ownerId ?? 'owner',
                      onVenueCreated: (newHagzyVenue) {
                        Navigator.pop(ctx);
                        final created = venueFromHagzyVenue(newHagzyVenue);
                        if (widget.onAddVenueModel != null) {
                          widget.onAddVenueModel!(created);
                        } else {
                          widget.onAddVenue();
                        }
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.add_business_rounded, size: 16),
              label: const Text('Step-by-Step Venue Setup'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: kObsidian,
            borderRadius: BorderRadius.circular(HagzyTokens.radiusMedium),
            border: Border.all(color: kVolt.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              LivePulseDot(color: kVolt, size: 8),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Supabase Cloud Sync Active · ${widget.venues.length} venues online',
                  style: hagzyMonoStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                  ),
                ),
              ),
              if (widget.onSyncFirebase != null)
                InkWell(
                  onTap: widget.onSyncFirebase,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.cloud_sync_rounded, size: 15, color: kVolt),
                        const SizedBox(width: 4),
                        Text(
                          'Sync Supabase',
                          style: TextStyle(
                            color: kVolt,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminKpiTile extends StatelessWidget {
  const _AdminKpiTile({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: HagzySurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        radius: HagzyTokens.radiusMedium,
        elevated: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: accent,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PosTab extends StatefulWidget {
  const PosTab({
    super.key,
    required this.venues,
    required this.bookings,
    this.adminNotifications = const [],
    this.onMarkNotificationRead,
    this.onVerifyBookingQr,
    this.onCheckInBooking,
    required this.onWalkIn,
    this.onBlockSlot,
    required this.onCancel,
    required this.onConfirm,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final List<Map<String, dynamic>> adminNotifications;
  final Future<void> Function(String notificationId)? onMarkNotificationRead;
  final Future<Map<String, dynamic>> Function(String bookingId, String? sig)?
      onVerifyBookingQr;
  final Future<void> Function(String bookingId, String? sig)? onCheckInBooking;
  final void Function(Venue venue, VenueItem item) onWalkIn;
  final void Function(Venue venue, VenueItem item, DateTime start, int duration, String reason)? onBlockSlot;
  final ValueChanged<Booking> onCancel;
  final ValueChanged<Booking> onConfirm;

  @override
  State<PosTab> createState() => _PosTabState();
}

class _PosTabState extends State<PosTab> {
  String _filter = 'all'; // 'all', 'pending', 'confirmed'

  Future<void> _openQrVerifyDialog() async {
    final ctrl = TextEditingController();
    Map<String, dynamic>? loaded;
    String? errorMsg;
    var loading = false;
    var checkedInNow = false;
    String? lastSig;

    (String bookingId, String? sig) parseInput(String raw) {
      final clean = raw.trim();
      final uri = Uri.tryParse(clean);
      if (uri != null && uri.queryParameters.containsKey('scanBooking')) {
        return (
          uri.queryParameters['scanBooking']!.trim(),
          uri.queryParameters['sig']?.trim(),
        );
      }
      return (clean, null);
    }

    Future<void> runLookup(StateSetter setDlgState) async {
      final (bookingId, sig) = parseInput(ctrl.text);
      if (bookingId.isEmpty) {
        setDlgState(() => errorMsg = 'Enter a Booking ID or paste QR link.');
        return;
      }
      setDlgState(() {
        loading = true;
        errorMsg = null;
        lastSig = sig;
      });
      try {
        Map<String, dynamic> details;
        if (widget.onVerifyBookingQr != null) {
          details = await widget.onVerifyBookingQr!(bookingId, sig);
        } else {
          final found =
              widget.bookings.where((b) => b.id == bookingId).firstOrNull;
          if (found == null) throw Exception('Booking not found locally.');
          final paid = found.actualPaidAmount ??
              (found.isConfirmed ? (found.dueNow ?? 0) : 0.0);
          details = {
            'signatureVerified': false,
            'booking': found.toJson(),
            'financialSummary': {
              'totalPrice': found.price,
              'paidAmount': paid,
              'remainingDue': (found.price - paid).clamp(0.0, found.price),
            },
          };
        }
        setDlgState(() {
          loaded = details;
          loading = false;
          final bJson = details['booking'] as Map<String, dynamic>?;
          checkedInNow = bJson?['checkedIn'] == true ||
              bJson?['status'] == 'checked_in';
        });
      } catch (e) {
        setDlgState(() {
          loading = false;
          errorMsg = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }

    await showHagzyAdaptiveModal<void>(
      context: context,
      maxWidth: 460,
      builder: (ctx, isSheet) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          final bJson = loaded?['booking'] as Map<String, dynamic>?;
          final fin = loaded?['financialSummary'] as Map<String, dynamic>?;
          final sigVerified = loaded?['signatureVerified'] == true;
          return HagzyModalCard(
            isSheet: isSheet,
            maxWidth: 460,
            icon: Icons.qr_code_scanner_rounded,
            title: _t('Verify / Scan Booking QR', 'فحص وتأكيد كود الحجز QR'),
            subtitle: _t(
              'Paste the scanned QR link from your camera app or enter a Booking ID to verify entry & remaining balance:',
              'الصق رابط الـ QR الممسوح من الكاميرا أو أدخل كود الحجز للتحقق وتسجيل الحضور:',
            ),
            onClose: () => Navigator.pop(ctx),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    labelText: _t('QR URL or Booking ID', 'رابط QR أو كود الحجز'),
                    hintText: 'https://hagzy.shop/partner?scanBooking=...',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search_rounded),
                      onPressed: loading ? null : () => runLookup(setDlgState),
                    ),
                  ),
                  onSubmitted: (_) => runLookup(setDlgState),
                ),
                if (loading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                ],
                if (errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Text(errorMsg!,
                      style: TextStyle(
                          color: kError,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ],
                if (bJson != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: kSurfaceSubtle,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              sigVerified
                                  ? Icons.verified_rounded
                                  : Icons.confirmation_number_outlined,
                              color: sigVerified ? kSuccess : kGold,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sigVerified
                                  ? _t('Signed QR Verified ✓', 'كود QR موثق ومؤكد ✓')
                                  : _t('Booking Details', 'تفاصيل الحجز'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: sigVerified ? kSuccess : kInk,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 14),
                        Text('${_t('Guest', 'العميل')}: ${bJson['customer'] ?? bJson['customerName'] ?? ''}'),
                        if ((bJson['phone'] ?? '').toString().isNotEmpty)
                          Text('${_t('Phone', 'الهاتف')}: ${bJson['phone']}'),
                        Text('${_t('Venue/Unit', 'المكان / الوحدة')}: ${bJson['venueName'] ?? bJson['venueId']} · ${bJson['unitName'] ?? bJson['itemId'] ?? ''}'),
                        Text('${_t('Status', 'الحالة')}: ${checkedInNow ? _t('CHECKED IN ✓', 'تم الحضور ✓') : bJson['status']}'),
                        const SizedBox(height: 6),
                        if (fin != null)
                          Text(
                            _t('Paid: ${fin['paidAmount']} EGP · Due at Venue: ${fin['remainingDue']} EGP', 'المدفوع: ${fin['paidAmount']} ج.م · المتبقي عند الحضور: ${fin['remainingDue']} ج.م'),
                            style: TextStyle(
                                fontWeight: FontWeight.w800, color: kInk),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            customActions: Row(
              children: [
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: kSurfaceSubtle,
                      foregroundColor: kInk,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(_t('Close', 'إغلاق')),
                  ),
                ),
                if (bJson == null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: loading ? null : () => runLookup(setDlgState),
                      child: Text(_t('Lookup', 'بحث')),
                    ),
                  ),
                ],
                if (bJson != null && !checkedInNow && widget.onCheckInBooking != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: loading
                          ? null
                          : () async {
                              final id = (bJson['id'] ?? '').toString();
                              setDlgState(() => loading = true);
                              try {
                                await widget.onCheckInBooking!(id, lastSig);
                                setDlgState(() {
                                  loading = false;
                                  checkedInNow = true;
                                });
                              } catch (e) {
                                setDlgState(() {
                                  loading = false;
                                  errorMsg = e.toString().replaceFirst('Exception: ', '');
                                });
                              }
                            },
                      icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                      label: Text(_t('Check In Guest', 'تسجيل حضور العميل')),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
    ctrl.dispose();
  }

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

    final confirmed = await showHagzyAdaptiveModal<bool>(
      context: context,
      builder: (ctx, isSheet) => StatefulBuilder(
        builder: (ctx, setDlgState) => HagzyModalCard(
          isSheet: isSheet,
          icon: Icons.lock_clock_outlined,
          iconColor: kGold,
          iconBackgroundColor: kGold.withValues(alpha: 0.14),
          title: '${_t('Block Slot', 'إغلاق موعد')} · ${item.name}',
          subtitle: _t(
            'Prevent online customers from reserving this time slot:',
            'منع الحجز أونلاين في هذه الفترة:',
          ),
          onClose: () => Navigator.pop(ctx, false),
          primaryUseFilledButton: true,
          primaryLabel: _t('Lock Slot', 'تأكيد الإغلاق'),
          onPrimary: () => Navigator.pop(ctx, true),
          secondaryLabel: _t('Cancel', 'إلغاء'),
          onSecondary: () => Navigator.pop(ctx, false),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: chosenReason,
                decoration: InputDecoration(
                  labelText: _t('Block Reason / سبب الإغلاق', 'سبب الإغلاق'),
                ),
                items: reasons
                    .map((r) => DropdownMenuItem(
                        value: r,
                        child: Text(r, style: const TextStyle(fontSize: 12.5))))
                    .toList(),
                onChanged: (v) =>
                    setDlgState(() => chosenReason = v ?? reasons.first),
              ),
              const SizedBox(height: 12),
              HagzyGroupedRow(
                icon: Icons.event_rounded,
                title:
                    '${date.day}/${date.month}/${date.year} · ${time.format(ctx)}',
                trailing: Text(
                  _t('Change', 'تغيير'),
                  style: TextStyle(
                    color: kBrandAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                onTap: () async {
                  final chosenD = await showDatePicker(
                    context: ctx,
                    initialDate: date,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 90)),
                  );
                  if (chosenD != null) {
                    setDlgState(() => date = chosenD);
                    if (!ctx.mounted) return;
                    final chosenT =
                        await showTimePicker(context: ctx, initialTime: time);
                    if (chosenT != null) setDlgState(() => time = chosenT);
                  }
                },
              ),
              const SizedBox(height: 10),
              Text(_t('Duration:', 'المدة:'),
                  style: TextStyle(fontSize: 12, color: kMuted)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
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

    final unreadNotifs = widget.adminNotifications
        .where((n) => n['read'] != true)
        .toList();

    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 8,
        isWide ? 24 : 16,
        36,
      ),
      children: [
        IntroCard(
          title: _t('POS timeline', 'جدول مواعيد الحجوزات'),
          subtitle: _t('Confirmed bookings, QR check-in, and temporary unpaid holds.', 'الحجوزات المؤكدة، فحص كود الـ QR، والمواعيد المعلقة.'),
          icon: Icons.view_timeline_outlined,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.tonalIcon(
                onPressed: _openQrVerifyDialog,
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 17),
                label: Text(_t('Scan QR Pass', 'فحص كود QR')),
              ),
              if (allActive.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(_t('${allActive.length} active', '${allActive.length} حجز نشط'),
                    style: TextStyle(
                        color: kGreen, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
        ),
        if (unreadNotifs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final isDark =
                  Theme.of(context).brightness == Brightness.dark || kDarkMode.value;
              return Card(
                color: isDark ? const Color(0xFF132A22) : const Color(0xFFF0FDF4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF1F352D) : const Color(0xFFBBF7D0),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.notifications_active_rounded,
                              color: kGreen, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            _t('New Booking Alerts (${unreadNotifs.length})', 'تنبيهات حجوزات جديدة (${unreadNotifs.length})'),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: isDark ? kGreenLight : kGreenDark,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ...unreadNotifs.take(4).map((n) {
                        final nId = (n['id'] ?? '').toString();
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            (n['title'] ?? 'New Alert').toString(),
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          subtitle: Text(
                            (n['body'] ?? '').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF334155),
                            ),
                          ),
                          trailing: widget.onMarkNotificationRead != null &&
                                  nId.isNotEmpty
                              ? TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: isDark ? kGreenLight : kGreenDark,
                                  ),
                                  onPressed: () =>
                                      widget.onMarkNotificationRead!(nId),
                                  child: Text(_t('Dismiss', 'تخطي')),
                                )
                              : null,
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
        const SizedBox(height: 14),
        if (widget.venues.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('Walk-in & Slot Blocker', 'حجز مباشر وتقفيل المواعيد'),
                      style: const TextStyle(fontWeight: FontWeight.bold)),
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
                    Text(_t('Add bookable spaces in Manage venues.', 'أضف ملاعب أو وحدات قابلة للحجز من إدارة الأماكن.')),
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
                label: _t('All (${allActive.length})', 'الكل (${allActive.length})'),
                selected: _filter == 'all',
                onTap: () => setState(() => _filter = 'all'),
              ),
              CustomPill(
                label: _t(
                    'Pending Deposit (${allActive.where((b) => b.isPendingPayment).length})',
                    'في انتظار العربون (${allActive.where((b) => b.isPendingPayment).length})'),
                selected: _filter == 'pending',
                onTap: () => setState(() => _filter = 'pending'),
              ),
              CustomPill(
                label: _t(
                    'Confirmed (${allActive.where((b) => b.isConfirmed).length})',
                    'مؤكد (${allActive.where((b) => b.isConfirmed).length})'),
                selected: _filter == 'confirmed',
                onTap: () => setState(() => _filter = 'confirmed'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        if (active.isEmpty)
          EmptyCard(
            icon: Icons.event_note_outlined,
            title: _t('No active bookings', 'لا توجد حجوزات نشطة'),
            body: _t('New customer and walk-in bookings appear here.', 'ستظهر هنا حجوزات العملاء الجديدة وحجوزات الملعب المباشرة.'),
          ),
        ...active.map((booking) {
          final venue =
              widget.venues.where((value) => value.id == booking.venueId);
          final item = venue.isEmpty
              ? null
              : venue.first.items
                  .where((value) => value.id == booking.itemId)
                  .firstOrNull;
          final statusTone = booking.isBlocked
              ? HagzyStatusTone.warning
              : (booking.checkedIn
                  ? HagzyStatusTone.info
                  : (booking.isConfirmed
                      ? HagzyStatusTone.success
                      : HagzyStatusTone.warning));
          final statusBadgeLabel = booking.isBlocked
              ? _t('Locked', 'مغلق')
              : (booking.checkedIn
                  ? _t('Checked In ✓', 'تم الحضور ✓')
                  : (booking.isPendingPayment
                      ? _t('Pending Deposit', 'بانتظار العربون')
                      : _t('Confirmed', 'مؤكد')));
          final statusDetailText = booking.checkedIn
              ? _t('Checked In ✓', 'تم تسجيل الحضور ✓')
              : (booking.isPendingPayment
                  ? _t('Awaiting deposit · not confirmed',
                      'بانتظار العربون · غير مؤكد بعد')
                  : _t('Confirmed by venue', 'مؤكد من إدارة المكان'));

          return HagzySurfaceCard(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (booking.isBlocked)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: kGold.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(HagzyTokens.radiusSmall),
                      border: Border.all(color: kGold.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 15, color: kGold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'LOCKED / موعد مغلق: ${booking.blockReason.isNotEmpty ? booking.blockReason : booking.customer}',
                            style: const TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => widget.onCancel(booking),
                          child: const Text(
                            'Unblock / فتح الموعد',
                            style: TextStyle(
                              fontSize: 12.0,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBox(
                      icon: booking.isBlocked
                          ? Icons.lock_clock_rounded
                          : Icons.event_available_rounded,
                      color: booking.isConfirmed ? kGreenDark : kGold,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                booking.customer,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15.5,
                                  color: kInk,
                                ),
                              ),
                              HagzyStatusBadge(
                                label: statusBadgeLabel,
                                tone: statusTone,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${venue.isEmpty ? 'Venue' : venue.first.name} · ${item?.name ?? 'Resource'}'
                            '${booking.phone.isNotEmpty ? ' · ${booking.phone}' : ''}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: kMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${formatMoney(booking.price)} EGP',
                          style: TextStyle(
                            color: kDarkMode.value ? kGreenLight : kGreenDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 2),
                        IconButton(
                          tooltip: _t('Cancel booking', 'إلغاء الحجز'),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => widget.onCancel(booking),
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: kMuted),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: kSurfaceSubtle,
                    borderRadius:
                        BorderRadius.circular(HagzyTokens.radiusSmall),
                    border: Border.all(color: kBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded,
                              size: 15,
                              color: kDarkMode.value ? kGreenLight : kGreenDark),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${formatDateTime(booking.startsAt)} – ${TimeOfDay.fromDateTime(booking.endsAt).format(context)} · ${booking.durationMinutes} min',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: kInk,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (booking.serviceNames.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          booking.serviceNames.join(' + '),
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                      ],
                      if (booking.splitCount > 1) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${booking.splitCount}-way · ${formatMoney(booking.price / booking.splitCount)} EGP each',
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                      ],
                      if (booking.paymentReference.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Payment Proof (${booking.paymentMethod.toUpperCase()}): ${booking.paymentReference}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kDarkMode.value ? kGreenLight : kGreenDark,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        statusDetailText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: booking.isPendingPayment ? kGold : kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (booking.isPendingPayment ||
                    booking.phone.isNotEmpty ||
                    booking.isConfirmed) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (booking.isPendingPayment)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          onPressed: () => widget.onConfirm(booking),
                          icon: const Icon(Icons.check_circle_outline,
                              size: 16),
                          label: Text(
                            booking.paymentReference.isNotEmpty
                                ? _t('Verify & Confirm Deposit',
                                    'فحص وتأكيد العربون')
                                : _t(
                                    'Confirm Deposit (${formatMoney(booking.dueNow ?? 0)} EGP)',
                                    'تأكيد العربون (${formatMoney(booking.dueNow ?? 0)} ج.م)'),
                          ),
                        ),
                      if (booking.isConfirmed &&
                          !booking.checkedIn &&
                          widget.onCheckInBooking != null)
                        FilledButton.tonalIcon(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          onPressed: () => widget.onCheckInBooking!(
                            booking.id,
                            booking.qrSignature.isNotEmpty
                                ? booking.qrSignature
                                : null,
                          ),
                          icon: const Icon(Icons.how_to_reg_rounded, size: 16),
                          label: Text(_t('Check In', 'تسجيل الحضور')),
                        ),
                      if (booking.phone.isNotEmpty)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                          ),
                          onPressed: () => _messageCustomer(booking),
                          icon: const Icon(Icons.chat_outlined, size: 16),
                          label: Text(_t('WhatsApp Customer', 'واتساب العميل')),
                        ),
                    ],
                  ),
                ],
              ],
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
    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    final arabic = isArabicMode;
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
    final cancelledOrExpired = bookings
        .where(
            (b) => b.cancelled || b.status == 'expired' || b.status == 'cancelled')
        .toList();
    final realLostRevenue =
        cancelledOrExpired.fold<double>(0.0, (acc, b) => acc + b.price);
    final conversionRate = activeBookings.isEmpty
        ? 0
        : ((confirmedBookings.length / activeBookings.length) * 100).round();

    final venueChartEntries = venues.map((v) {
      final vRev = confirmedBookings
          .where((b) => b.venueId == v.id)
          .fold<double>(0, (sum, b) => sum + b.price);
      return (label: v.name, value: vRev, color: kGreen as Color?);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final kpiCards = [
      HagzyKpiCard(
        title: _t('Confirmed Revenue', 'الإيرادات المؤكدة'),
        value: '${formatMoney(confirmedRevenue)} ${_t('EGP', 'ج.م')}',
        subtitle: _t('${confirmedBookings.length} confirmed bookings',
            '${confirmedBookings.length} حجز مؤكد'),
        icon: Icons.payments_outlined,
        accent: kGreen,
      ),
      HagzyKpiCard(
        title: _t('Deposits Verified', 'العربون المؤكد'),
        value: '${formatMoney(depositsCollected)} ${_t('EGP', 'ج.م')}',
        subtitle: _t('Collected upfront', 'محصّل مقدماً'),
        icon: Icons.verified_outlined,
        accent: kInfoBlue,
      ),
      HagzyKpiCard(
        title: _t('Pending Holds', 'حجوزات معلقة'),
        value: '${pendingBookings.length}',
        subtitle: _t('${formatMoney(pendingPipeline)} EGP pipeline',
            '${formatMoney(pendingPipeline)} ج.م قيد التأكيد'),
        icon: Icons.hourglass_top_rounded,
        accent: kGold,
      ),
      HagzyKpiCard(
        title: _t('Confirmation Rate', 'نسبة التأكيد'),
        value: '$conversionRate%',
        subtitle: _t('${venues.length} active venues',
            '${venues.length} مكان نشط'),
        icon: Icons.trending_up_rounded,
        accent: kCobalt,
      ),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 8,
        isWide ? 24 : 16,
        36,
      ),
      children: [
        IntroCard(
          title: _t('Revenue & Analytics', 'الأرباح والتقارير'),
          subtitle: _t(
            'Real-time performance across your venues, spaces, and deposits.',
            'أداء فوري للأماكن والملاعب والمبالغ المحصّلة.',
          ),
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = constraints.maxWidth >= 920
                ? 4
                : (constraints.maxWidth >= 520 ? 2 : 1);
            const spacing = 12.0;
            final cardWidth =
                (constraints.maxWidth - (spacing * (cols - 1))) / cols;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: kpiCards
                  .map((c) => SizedBox(width: cardWidth, child: c))
                  .toList(),
            );
          },
        ),
        if (cancelledOrExpired.isNotEmpty) ...[
          const SizedBox(height: 16),
          MerchantLossAversionBanner(
            estimatedLostRevenueEgp: realLostRevenue,
            noShowCount: cancelledOrExpired.length,
            onUpgradePro: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: kSnackBarBg,
                  content: Text(_t(
                    'Automated deposit protection is enabled on paid slots.',
                    'حماية العربون التلقائية مفعّلة على جميع المواعيد المدفوعة.',
                  )),
                ),
              );
            },
            onDismissAbsorbLosses: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_t('Notice dismissed.', 'تم إخفاء التنبيه.')),
                ),
              );
            },
          ),
        ],
        if (venues.isNotEmpty) ...[
          const SizedBox(height: 18),
          HagzySurfaceCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(
                  title: _t('Revenue Distribution', 'توزيع الإيرادات'),
                  subtitle: _t('Confirmed revenue share across your venues',
                      'حصة الإيرادات المؤكدة لكل مكان'),
                ),
                const SizedBox(height: 16),
                HagzyRevenueBarChart(
                  entries: venueChartEntries.take(6).toList(),
                  unitLabel: _t('EGP', 'ج.م'),
                  arabic: arabic,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        SectionHeading(
          title: _t('Performance by Venue', 'الأداء حسب المكان'),
          subtitle: _t('Detailed bookings and verified revenue per location',
              'تفاصيل الحجوزات والإيرادات المؤكدة لكل فرع'),
        ),
        const SizedBox(height: 12),
        if (venues.isEmpty)
          EmptyCard(
            icon: Icons.storefront_outlined,
            title: _t('No Venues Yet', 'لا توجد أماكن بعد'),
            body: _t('Add a venue to track bookings and revenue.',
                'أضف مكاناً لبدء متابعة الحجوزات والإيرادات.'),
          )
        else
          ...venues.map((v) {
            final vBookings =
                activeBookings.where((b) => b.venueId == v.id).toList();
            final vConfirmed = vBookings.where((b) => b.isConfirmed).toList();
            final vPending =
                vBookings.where((b) => b.isPendingPayment).length;
            final vRev =
                vConfirmed.fold<double>(0, (sum, b) => sum + b.price);
            final share = confirmedRevenue > 0
                ? (vRev / confirmedRevenue).clamp(0.06, 1.0)
                : 0.08;
            return HagzySurfaceCard(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconBox(icon: v.type.icon),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15.5,
                                color: kInk,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              _t(
                                '${vConfirmed.length} confirmed · $vPending pending holds',
                                '${vConfirmed.length} مؤكد · $vPending في انتظار العربون',
                              ),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: kMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${formatMoney(vRev)} ${_t('EGP', 'ج.م')}',
                        style: TextStyle(
                          color: kDarkMode.value ? kGreenLight : kGreenDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 7,
                      backgroundColor: kSurfaceSubtle,
                      color: kGreen,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class PaymentTab extends StatefulWidget {
  const PaymentTab({
    super.key,
    required this.apiConfigured,
    required this.localPreview,
    this.bookings = const [],
    this.onLoadGatewayStatus,
    this.onLoadReviewQueue,
    this.onAttachReviewItem,
  });

  final bool apiConfigured;
  final bool localPreview;
  final List<Booking> bookings;
  final Future<Map<String, dynamic>> Function()? onLoadGatewayStatus;
  final Future<List<Map<String, dynamic>>> Function()? onLoadReviewQueue;
  final Future<void> Function(String itemId, String bookingId)?
      onAttachReviewItem;

  @override
  State<PaymentTab> createState() => _PaymentTabState();
}

class _PaymentTabState extends State<PaymentTab> {
  bool _loading = false;
  Map<String, dynamic>? _gatewayStatus;
  List<Map<String, dynamic>> _reviewQueue = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.apiConfigured &&
        !widget.localPreview &&
        (widget.onLoadGatewayStatus != null ||
            widget.onLoadReviewQueue != null)) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      Map<String, dynamic>? status;
      List<Map<String, dynamic>> queue = _reviewQueue;
      if (widget.onLoadGatewayStatus != null) {
        status = await widget.onLoadGatewayStatus!();
      }
      if (widget.onLoadReviewQueue != null) {
        queue = await widget.onLoadReviewQueue!();
      }
      if (!mounted) return;
      setState(() {
        _gatewayStatus = status ?? _gatewayStatus;
        _reviewQueue = queue;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openAttachDialog(Map<String, dynamic> item) async {
    if (widget.onAttachReviewItem == null) return;
    final itemId = (item['id'] ?? '').toString();
    final pendingBookings = widget.bookings
        .where((b) => !b.cancelled && !b.isConfirmed)
        .toList();
    final idCtrl = TextEditingController(
      text: pendingBookings.isNotEmpty ? pendingBookings.first.id : '',
    );
    var selectedId = idCtrl.text;

    final confirmed = await showHagzyAdaptiveModal<bool>(
      context: context,
      builder: (ctx, isSheet) => StatefulBuilder(
        builder: (ctx, setDlgState) => HagzyModalCard(
          isSheet: isSheet,
          icon: Icons.link_rounded,
          title: 'Attach Transfer to Booking',
          subtitle:
              'Amount: ${item['amount']} EGP · Sender: ${item['sender_identifier'] ?? item['senderIdentifier'] ?? 'unknown'}',
          onClose: () => Navigator.pop(ctx, false),
          primaryUseFilledButton: true,
          primaryLabel: 'Attach & Confirm',
          onPrimary: () => Navigator.pop(ctx, true),
          secondaryLabel: 'Cancel',
          onSecondary: () => Navigator.pop(ctx, false),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pendingBookings.isNotEmpty)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: pendingBookings.any((b) => b.id == selectedId)
                      ? selectedId
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Select Pending Booking'),
                  items: pendingBookings
                      .map((b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              '${b.customer} · ${formatMoney(b.dueNow ?? b.price)} EGP (${b.id.substring(0, b.id.length > 10 ? 10 : b.id.length)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setDlgState(() {
                      selectedId = v ?? '';
                      idCtrl.text = selectedId;
                    });
                  },
                ),
              const SizedBox(height: 10),
              TextField(
                controller: idCtrl,
                decoration:
                    const InputDecoration(labelText: 'Or enter Booking ID'),
              ),
            ],
          ),
        ),
      ),
    );
    final targetBookingId = idCtrl.text.trim();
    idCtrl.dispose();
    if (confirmed == true && targetBookingId.isNotEmpty && itemId.isNotEmpty) {
      await widget.onAttachReviewItem!(itemId, targetBookingId);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isListenerActive = _gatewayStatus?['isListenerActive'] == true;
    final lastHeartbeatAt = _gatewayStatus?['lastHeartbeatAt']?.toString();
    final recentLogs = (_gatewayStatus?['recentLogs'] as List<dynamic>?) ?? const [];
    final unresolved = _reviewQueue
        .where((i) => (i['status'] ?? '').toString() != 'RESOLVED')
        .toList();

    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 8,
        isWide ? 24 : 16,
        36,
      ),
      children: [
        IntroCard(
          title: _t('Payments, Gateway & Review Queue',
              'المدفوعات وبوابة التحقق والمراجعة'),
          subtitle: _t(
            'Monitor automatic wallet transfers and match any unmatched payments.',
            'راقب التحويلات التلقائية وطابق أي تحويلات غير مربوطة بضغطة واحدة.',
          ),
          icon: Icons.lock_outline,
        ),
        const SizedBox(height: 12),
        if (!widget.apiConfigured || widget.localPreview) const LocalPreviewNotice(),
        if (widget.apiConfigured && !widget.localPreview) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isListenerActive
                            ? Icons.sensors_rounded
                            : Icons.sensors_off_rounded,
                        color: isListenerActive ? kGreen : const Color(0xFFD97706),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isListenerActive
                              ? 'Payment Gateway: Active'
                              : 'Payment Gateway: Waiting for Heartbeat',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh gateway & queue',
                        onPressed: _loading ? null : _refresh,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (lastHeartbeatAt != null && lastHeartbeatAt.isNotEmpty)
                    Text('Last Heartbeat: $lastHeartbeatAt',
                        style: TextStyle(fontSize: 12, color: kMuted)),
                  if (_error != null) ...[
                    const SizedBox(height: 6),
                    Text(_error!,
                        style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                  ],
                  if (recentLogs.isNotEmpty) ...[
                    const Divider(height: 18),
                    const Text('Recent Gateway Transfers',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...recentLogs.take(5).map((log) {
                      final m = Map<String, dynamic>.from(log as Map);
                      final matched = m['matched'] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• ${m['amount'] ?? 0} EGP — ${matched ? 'Matched (${m['bookingId'] ?? ''})' : (m['parseStatus'] ?? 'Queued')} at ${m['at'] ?? ''}',
                          style: TextStyle(
                            fontSize: 12,
                            color: matched ? kGreenDark : const Color(0xFFB45309),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.rate_review_outlined,
                          color: Color(0xFFD97706)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Review Queue (${unresolved.length} open)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (unresolved.isEmpty)
                    Text(
                      'All incoming InstaPay and Vodafone Cash transfers have matched automatically.',
                      style: TextStyle(color: kMuted, fontSize: 12.5),
                    ),
                  ...unresolved.map((item) {
                    final sender = item['sender_identifier'] ??
                        item['senderIdentifier'] ??
                        'unknown';
                    final method = item['payment_method'] ??
                        item['paymentMethod'] ??
                        'TRANSFER';
                    final raw =
                        (item['raw_text'] ?? item['rawText'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(top: 8),
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
                                  '${item['amount']} EGP · $method · ${item['status']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800, fontSize: 13),
                                ),
                              ),
                              if (widget.onAttachReviewItem != null)
                                FilledButton.tonal(
                                  onPressed: () => _openAttachDialog(item),
                                  child: const Text('Attach'),
                                ),
                            ],
                          ),
                          Text('Sender: $sender',
                              style: TextStyle(fontSize: 12, color: kMuted)),
                          if ((item['reason'] ?? '').toString().isNotEmpty)
                            Text('${item['reason']}',
                                style: const TextStyle(
                                    fontSize: 11.5, color: Color(0xFFB45309))),
                          if (raw.isNotEmpty)
                            Text(raw,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: kMuted)),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('InstaPay & Vodafone Cash (Automatic Verification)',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    'All customer deposits arrive into the central Hagzy wallet and are matched automatically by (Sender + Amount). Any ambiguous or unparsed transfers appear above in the Review Queue for 1-tap resolution.',
                    style: TextStyle(color: kMuted)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class UsersCrmTab extends StatefulWidget {
  const UsersCrmTab({
    super.key,
    required this.venues,
    required this.bookings,
    this.onLoadUsers,
    required this.onConfirm,
    required this.onCancel,
  });

  final List<Venue> venues;
  final List<Booking> bookings;
  final Future<List<Map<String, dynamic>>> Function()? onLoadUsers;
  final ValueChanged<Booking> onConfirm;
  final ValueChanged<Booking> onCancel;

  @override
  State<UsersCrmTab> createState() => _UsersCrmTabState();
}

class _CrmUserEntry {
  _CrmUserEntry({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.walletBalance,
    required this.bookings,
  });

  final String id;
  String name;
  String phone;
  String email;
  double walletBalance;
  final List<Booking> bookings;
}

class _UsersCrmTabState extends State<UsersCrmTab> {
  String _searchQuery = '';
  String _filter = 'all'; // 'all' | 'pending' | 'vip'
  final Set<String> _expandedUserIds = {};
  List<Map<String, dynamic>> _supabaseUsers = [];

  @override
  void initState() {
    super.initState();
    _refreshUsers();
  }

  Future<void> _refreshUsers() async {
    final loader = widget.onLoadUsers;
    if (loader == null) return;
    try {
      final users = await loader();
      if (!mounted) return;
      setState(() {
        _supabaseUsers = users;
        if (_expandedUserIds.isEmpty && users.isNotEmpty) {
          _expandedUserIds.add(users.first['id']?.toString() ?? '');
        }
      });
    } catch (_) {}
  }

  static String _buildCleanId(String name, String email, String phone) {
    final rawName = name.trim().toLowerCase();
    final rawEmail = email.trim().toLowerCase();
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    var slug = rawName
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (slug.isEmpty || slug == 'hagzy_member' || slug == 'member') {
      if (rawEmail.contains('@')) {
        slug = rawEmail
            .split('@')
            .first
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'^_+|_+$'), '');
      } else if (digits.isNotEmpty) {
        final tail = digits.length > 6 ? digits.substring(digits.length - 6) : digits;
        slug = 'user_$tail';
      } else {
        slug = 'member';
      }
    }
    return 'usr_${slug.length > 28 ? slug.substring(0, 28) : slug}';
  }

  List<_CrmUserEntry> _buildUsers() {
    final byId = <String, _CrmUserEntry>{};

    // 1. Seed from Supabase users CRM view (public.v_user_overview)
    for (final fu in _supabaseUsers) {
      final id = (fu['id']?.toString() ?? '').trim();
      if (id.isEmpty) continue;
      final name = (fu['name']?.toString() ?? 'Hagzy Member').trim();
      final phone = (fu['phone']?.toString() ?? '').trim();
      final email = (fu['email']?.toString() ?? '').trim();
      final wallet = (fu['walletBalance'] as num?)?.toDouble() ?? 0.0;
      final parsedBookings = <Booking>[];
      final rawList = fu['bookings'];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is Map) {
            try {
              parsedBookings.add(Booking.fromJson(Map<String, dynamic>.from(item)));
            } catch (_) {}
          }
        }
      }
      byId[id] = _CrmUserEntry(
        id: id,
        name: name,
        phone: phone,
        email: email,
        walletBalance: wallet,
        bookings: parsedBookings,
      );
    }

    // 2. Merge live bookings from widget.bookings so local/new bookings are always reflected
    for (final b in widget.bookings) {
      if (b.isBlocked) continue;
      final uid = _buildCleanId(b.customer, b.email, b.phone);
      final existing = byId[uid];
      if (existing != null) {
        if (existing.phone.isEmpty && b.phone.isNotEmpty) existing.phone = b.phone;
        if (existing.email.isEmpty && b.email.isNotEmpty) existing.email = b.email;
        final idx = existing.bookings.indexWhere((x) => x.id == b.id);
        if (idx >= 0) {
          existing.bookings[idx] = b;
        } else {
          existing.bookings.add(b);
        }
      } else {
        byId[uid] = _CrmUserEntry(
          id: uid,
          name: b.customer.isEmpty ? 'Hagzy Member' : b.customer,
          phone: b.phone,
          email: b.email,
          walletBalance: 0,
          bookings: [b],
        );
      }
    }

    final list = byId.values.toList();
    for (final u in list) {
      u.bookings.sort((a, b) => b.startsAt.compareTo(a.startsAt));
    }
    list.sort((a, b) => b.bookings.length.compareTo(a.bookings.length));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = kDarkMode.value;
    final allUsers = _buildUsers();
    final filtered = allUsers.where((u) {
      if (_filter == 'pending' &&
          !u.bookings.any((b) => b.isPendingPayment && !b.cancelled)) {
        return false;
      }
      if (_filter == 'vip' && u.bookings.length < 2) {
        return false;
      }
      if (_searchQuery.trim().isEmpty) return true;
      final q = _searchQuery.trim().toLowerCase();
      return u.name.toLowerCase().contains(q) ||
          u.phone.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q) ||
          u.id.toLowerCase().contains(q);
    }).toList();

    final totalBookingsCount =
        allUsers.fold<int>(0, (sum, u) => sum + u.bookings.length);

    final isWide =
        MediaQuery.sizeOf(context).width >= HagzyTokens.breakpointTablet;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        isWide ? 24 : 16,
        isWide ? 16 : 8,
        isWide ? 24 : 16,
        36,
      ),
      children: [
        IntroCard(
          title: _t('Customer Directory & CRM', 'دليل العملاء والحجوزات'),
          subtitle: _t(
            'Inspect linked customer profiles, booking history, and moderate active reservations.',
            'استعرض ملفات العملاء وسجل حجوزاتهم وقم بإدارة الحجوزات النشطة.',
          ),
          icon: Icons.people_alt_rounded,
          action: HagzyStatusBadge(
            label: _t('${allUsers.length} Users · $totalBookingsCount Bookings',
                '${allUsers.length} عميل · $totalBookingsCount حجز'),
            tone: HagzyStatusTone.brand,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          onChanged: (v) => setState(() => _searchQuery = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search_rounded),
            hintText: _t(
              'Search by name, phone, email, or customer ID...',
              'ابحث بالاسم، رقم الموبايل، البريد الإلكتروني...',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            CustomPill(
              label: _t('All Users (${allUsers.length})',
                  'كل العملاء (${allUsers.length})'),
              selected: _filter == 'all',
              onTap: () => setState(() => _filter = 'all'),
            ),
            CustomPill(
              label: _t('Pending Deposit', 'في انتظار العربون'),
              icon: Icons.hourglass_top_rounded,
              selected: _filter == 'pending',
              onTap: () => setState(() => _filter = 'pending'),
            ),
            CustomPill(
              label: _t('Repeat / VIP (2+ bookings)', 'عملاء VIP (+٢ حجز)'),
              icon: Icons.workspace_premium_rounded,
              selected: _filter == 'vip',
              onTap: () => setState(() => _filter = 'vip'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          const EmptyCard(
            icon: Icons.person_search_rounded,
            title: 'No matching users found',
            body: 'Try clearing your search or filter to view all registered customers.',
          ),
        ...filtered.map((user) {
          final isExpanded = _expandedUserIds.contains(user.id);
          final confirmedCount = user.bookings
              .where((b) => b.isConfirmed && !b.cancelled)
              .length;
          final pendingCount = user.bookings
              .where((b) => b.isPendingPayment && !b.cancelled)
              .length;
          final totalSpend = user.bookings
              .where((b) => !b.cancelled)
              .fold<double>(0, (sum, b) => sum + b.price);

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: isExpanded ? kGreen : kBorder,
                width: isExpanded ? 1.6 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedUserIds.remove(user.id);
                      } else {
                        _expandedUserIds.add(user.id);
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 23,
                          backgroundColor: kGreen.withValues(alpha: 0.14),
                          child: Text(
                            user.name.isNotEmpty
                                ? user.name.trim()[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              color: kGreen,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    user.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: kInk,
                                    ),
                                  ),
                                  HagzyStatusBadge(
                                    label: user.id,
                                    tone: HagzyStatusTone.neutral,
                                    compact: true,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 12,
                                runSpacing: 4,
                                children: [
                                  if (user.phone.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.phone_iphone_rounded,
                                          size: 14,
                                          color: kMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          user.phone,
                                          style: TextStyle(
                                            color: kMuted,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (user.email.isNotEmpty)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.mail_outline_rounded,
                                          size: 14,
                                          color: kMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          user.email,
                                          style: TextStyle(
                                            color: kMuted,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _StatMiniChip(
                                    label: '${user.bookings.length} Bookings',
                                    color: kGreen,
                                  ),
                                  if (confirmedCount > 0)
                                    _StatMiniChip(
                                      label: '$confirmedCount Confirmed',
                                      color: const Color(0xFF059669),
                                    ),
                                  if (pendingCount > 0)
                                    _StatMiniChip(
                                      label: '$pendingCount Pending',
                                      color: const Color(0xFFD97706),
                                    ),
                                  _StatMiniChip(
                                    label: '${totalSpend.toStringAsFixed(0)} EGP Total',
                                    color: const Color(0xFF2563EB),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: kMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isExpanded) ...[
                  const Divider(height: 1),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    color: isDark
                        ? const Color(0xFF0F172A).withValues(alpha: 0.5)
                        : kSurfaceTint.withValues(alpha: 0.45),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(
                            'Linked Reservations (${user.bookings.length})',
                            'الحجوزات المرتبطة (${user.bookings.length})',
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: kMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (user.bookings.isEmpty)
                          Text(
                            'No bookings recorded for this user yet.',
                            style: TextStyle(color: kMuted, fontSize: 12.5),
                          ),
                        ...user.bookings.map((b) {
                          final venue = widget.venues
                              .where((v) => v.id == b.venueId)
                              .firstOrNull;
                          final venueName = venue?.name ?? b.venueId;
                          final item = venue?.items
                              .where((i) => i.id == b.itemId)
                              .firstOrNull;
                          final itemName = item?.name ?? b.itemId;
                          final statusColor = b.cancelled
                              ? Colors.red
                              : (b.isConfirmed
                                  ? kGreen
                                  : const Color(0xFFD97706));
                          final statusLabel = b.cancelled
                              ? 'Cancelled'
                              : (b.isConfirmed
                                  ? 'Confirmed'
                                  : 'Pending Deposit');

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF111B17) : kPanel,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: kBorder),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '$venueName · $itemName',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13.5,
                                                color: kInk,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: statusColor.withValues(
                                                  alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              statusLabel,
                                              style: TextStyle(
                                                fontSize: 12.0,
                                                fontWeight: FontWeight.w800,
                                                color: statusColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            size: 13,
                                            color: kMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              '${formatDateTime(b.startsAt)} (${b.durationMinutes} min)',
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: kMuted,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.payments_outlined,
                                            size: 14,
                                            color: kMuted,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${b.price.toStringAsFixed(0)} EGP',
                                            style: TextStyle(
                                              color: kMuted,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (b.paymentReference.isNotEmpty ||
                                          b.paymentMethod.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 3),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.account_balance_wallet_outlined,
                                                size: 13,
                                                color: kGreen,
                                              ),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  '${b.paymentMethod.isEmpty ? "Transfer" : b.paymentMethod.toUpperCase()}${b.paymentReference.isEmpty ? "" : " · Ref: ${b.paymentReference}"}',
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    color: kGreen,
                                                    fontSize: 12.0,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (!b.cancelled && b.isPendingPayment) ...[
                                  const SizedBox(width: 8),
                                  FilledButton.tonalIcon(
                                    onPressed: () => widget.onConfirm(b),
                                    icon: const Icon(Icons.verified_rounded,
                                        size: 15),
                                    label: const Text('Confirm'),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _StatMiniChip extends StatelessWidget {
  const _StatMiniChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.0,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}


