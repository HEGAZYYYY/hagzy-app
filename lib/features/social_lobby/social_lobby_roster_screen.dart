import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/models_v2.dart';

/// Screen displaying the full Social "El-Shilla" / Open Lobby roster,
/// per-person financial splits, needed positions/roles, and WhatsApp invite generation.
class SocialLobbyRosterScreen extends StatefulWidget {
  const SocialLobbyRosterScreen({
    super.key,
    required this.lobby,
    this.userProfile,
    this.isArabic = false,
    this.onSpotClaimed,
  });

  final HagzyBooking lobby;
  final UserProfile? userProfile;
  final bool isArabic;
  final void Function(HagzyBooking updatedLobby)? onSpotClaimed;

  @override
  State<SocialLobbyRosterScreen> createState() => _SocialLobbyRosterScreenState();
}

class _SocialLobbyRosterScreenState extends State<SocialLobbyRosterScreen> {
  late HagzyBooking _lobby;
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _lobby = widget.lobby;
  }

  void _shareToWhatsApp() async {
    final startTimeStr = '${_lobby.startTime.hour.toString().padLeft(2, '0')}:${_lobby.startTime.minute.toString().padLeft(2, '0')}';
    final shareText = widget.isArabic
        ? '🔥 شلة حجزي: ${_lobby.lobbyTitle ?? "تحدي مفتوح"}\n'
          '📍 المكان: ${_lobby.venueName ?? "Hagzy Venue"} (${_lobby.venueCity ?? "مصر"})\n'
          '🎮 المساحة: ${_lobby.unitName ?? "الغرفة / الطاولة"}\n'
          '⏰ الميعاد: $startTimeStr\n'
          '💰 نصيب الفرد: ${_lobby.perPersonShareEgp.toStringAsFixed(0)} ج.م فقط\n\n'
          'ادخل واحجز مكانك في الشلة الآن:\n${_lobby.deepLinkUrl}'
        : '🔥 Hagzy Hangout: ${_lobby.lobbyTitle ?? "Open Match"}\n'
          '📍 Venue: ${_lobby.venueName ?? "Hagzy Venue"} (${_lobby.venueCity ?? "Egypt"})\n'
          '🎮 Space: ${_lobby.unitName ?? "Room / Table"}\n'
          '⏰ Time: $startTimeStr\n'
          '💰 Share: ${_lobby.perPersonShareEgp.toStringAsFixed(0)} EGP per person\n\n'
          'Claim your spot in the squad here:\n${_lobby.deepLinkUrl}';

    final uri = Uri.parse('whatsapp://send?text=${Uri.encodeComponent(shareText)}');
    final fallbackUri = Uri.parse('https://api.whatsapp.com/send?text=${Uri.encodeComponent(shareText)}');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
    }
  }

  void _claimSpot() async {
    if (_lobby.filledSlots >= _lobby.totalSlots) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.isArabic ? 'الشلة مكتملة بالكامل!' : 'Lobby is already full!'),
        ),
      );
      return;
    }

    setState(() => _isClaiming = true);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final updated = _lobby.copyWith(
      filledSlots: _lobby.filledSlots + 1,
      participantIds: [..._lobby.participantIds, widget.userProfile?.id ?? 'guest_player'],
    );

    setState(() {
      _lobby = updated;
      _isClaiming = false;
    });

    widget.onSpotClaimed?.call(updated);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green,
        content: Text(
          widget.isArabic
              ? 'تم تأكيد حجز مكانك في الشلة بنجاح! 🚀'
              : 'Spot claimed in the squad successfully! 🚀',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = _lobby.filledSlots >= _lobby.totalSlots;
    final spotsRemaining = _lobby.totalSlots - _lobby.filledSlots;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isArabic ? 'غرفة الشلة والمنافسة' : 'Squad & Challenger Lobby'),
        actions: [
          IconButton(
            tooltip: widget.isArabic ? 'مشاركة عبر واتساب' : 'Share to WhatsApp',
            icon: const Icon(Icons.share_rounded, color: Colors.greenAccent),
            onPressed: _shareToWhatsApp,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Hero Match Card
          Container(
            padding: const EdgeInsets.all(18.0),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1B4B), Color(0xFF0F172A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.indigoAccent.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.flash_on_rounded, size: 14, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            widget.isArabic ? 'ماتش مفتوح / كمّل العدد' : 'Open Lobby / Match',
                            style: const TextStyle(
                              color: Colors.amber,
                              fontSize: 12.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isFull
                            ? Colors.red.withValues(alpha: 0.2)
                            : Colors.greenAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isFull
                            ? (widget.isArabic ? 'مكتمل' : 'Full')
                            : (widget.isArabic ? 'باقي $spotsRemaining مكان' : '$spotsRemaining spots left'),
                        style: TextStyle(
                          color: isFull ? Colors.redAccent : Colors.greenAccent,
                          fontSize: 12.0,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _lobby.lobbyTitle ?? (widget.isArabic ? 'تحدي الشلة' : 'Squad Match'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 15, color: Colors.indigoAccent),
                    const SizedBox(width: 4),
                    Text(
                      '${_lobby.venueName ?? "Hagzy Venue"} • ${_lobby.unitName ?? "Unit"} (${_lobby.venueCity ?? "Egypt"})',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.access_time_filled_rounded, size: 15, color: Colors.indigoAccent),
                    const SizedBox(width: 4),
                    Text(
                      '${_lobby.startTime.hour.toString().padLeft(2, '0')}:${_lobby.startTime.minute.toString().padLeft(2, '0')} - ${_lobby.endTime.hour.toString().padLeft(2, '0')}:${_lobby.endTime.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Per-Person Split Anchoring Card
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isArabic ? 'نصيب الفرد في الشلة' : 'Per-Person Share',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_lobby.perPersonShareEgp.toStringAsFixed(0)} EGP',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    widget.isArabic
                        ? 'الإجمالي: ${_lobby.totalPriceEgp.toStringAsFixed(0)} ج.م'
                        : 'Total: ${_lobby.totalPriceEgp.toStringAsFixed(0)} EGP',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Needed Roles Section
          if (_lobby.neededRoles.isNotEmpty) ...[
            Text(
              widget.isArabic ? 'الأدوار والمراكز المطلوبة' : 'Needed Roles / Positions',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _lobby.neededRoles.map((role) {
                final displayLabel = switch (role) {
                  '1v1_challenger' => widget.isArabic ? 'منافس 1v1 بلياردو/بينج' : '1v1 Challenger',
                  'GK' => widget.isArabic ? 'حارس مرمى (GK)' : 'Goalkeeper (GK)',
                  'DEF' => widget.isArabic ? 'مدافع (DEF)' : 'Defender (DEF)',
                  '2_players' => widget.isArabic ? 'لاعبين اثنين إضافيين' : '2 Additional Players',
                  _ => role,
                };
                return Chip(
                  avatar: const Icon(Icons.sports_esports_rounded, size: 16, color: Colors.amber),
                  backgroundColor: Colors.amber.withValues(alpha: 0.1),
                  side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
                  label: Text(
                    displayLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],

          // Squad Roster
          Text(
            widget.isArabic ? 'قائمة الحاضرين في الشلة' : 'Squad Roster',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          ...List.generate(_lobby.totalSlots, (index) {
            final isFilled = index < _lobby.filledSlots;
            final isHost = index == 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8.0),
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: isFilled
                    ? theme.colorScheme.surface
                    : theme.colorScheme.surface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isFilled
                      ? Colors.greenAccent.withValues(alpha: 0.3)
                      : theme.dividerColor.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: isFilled ? Colors.indigoAccent : Colors.grey.shade800,
                    child: Icon(
                      isFilled ? Icons.person_rounded : Icons.person_add_rounded,
                      size: 18,
                      color: isFilled ? Colors.white : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isFilled
                          ? (isHost
                              ? (widget.isArabic ? 'مؤسس الشلة (Host)' : 'Squad Host')
                              : (widget.isArabic ? 'لاعب رقم ${index + 1}' : 'Player #${index + 1}'))
                          : (widget.isArabic ? 'مكان مفتوح للحجز...' : 'Open Spot...'),
                      style: TextStyle(
                        fontWeight: isFilled ? FontWeight.bold : FontWeight.normal,
                        color: isFilled ? null : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (isHost)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        widget.isArabic ? 'الكابتن' : 'Host',
                        style: const TextStyle(color: Colors.amber, fontSize: 12.0, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: const BorderSide(color: Colors.greenAccent),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _shareToWhatsApp,
                icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.greenAccent),
                label: Text(
                  widget.isArabic ? 'دعوة شلتك عبر واتساب' : 'Invite Your Squad on WhatsApp',
                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: isFull ? Colors.grey : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: (isFull || _isClaiming) ? null : _claimSpot,
                child: _isClaiming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isFull
                            ? (widget.isArabic ? 'الشلة مكتملة' : 'Squad is Full')
                            : (widget.isArabic
                                ? 'ادخل الشلة وادفع نصيبك (${_lobby.perPersonShareEgp.toStringAsFixed(0)} ج.م)'
                                : 'Claim My Spot (${_lobby.perPersonShareEgp.toStringAsFixed(0)} EGP)'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
