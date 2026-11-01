import 'package:flutter/material.dart';
import '../../core/models/models_v2.dart';

/// Interactive Open Lobby / Challenger Feed Carousel ("كمّل العدد / مطلوب منافس")
class OpenLobbyFeedCarousel extends StatelessWidget {
  final List<HagzyBooking> activeLobbies;
  final ValueChanged<HagzyBooking> onJoinLobby;
  final VoidCallback? onCreateLobby;
  final bool isArabic;

  const OpenLobbyFeedCarousel({
    super.key,
    required this.activeLobbies,
    required this.onJoinLobby,
    this.onCreateLobby,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    if (activeLobbies.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.flash_on_rounded,
                      color: Colors.amber,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isArabic ? 'كمّل العدد • مطلوب منافس' : 'Open Lobbies & Challengers',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      letterSpacing: 0.1,
                    ),
                  ),
                ],
              ),
              if (onCreateLobby != null)
                TextButton.icon(
                  onPressed: onCreateLobby,
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: Text(
                    isArabic ? 'افتح لوبي' : 'Host Lobby',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            scrollDirection: Axis.horizontal,
            itemCount: activeLobbies.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final lobby = activeLobbies[index];
              return _LobbyCard(
                lobby: lobby,
                onTap: () => onJoinLobby(lobby),
                isArabic: isArabic,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LobbyCard extends StatelessWidget {
  final HagzyBooking lobby;
  final VoidCallback onTap;
  final bool isArabic;

  const _LobbyCard({
    required this.lobby,
    required this.onTap,
    required this.isArabic,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChallenger = lobby.neededRoles.contains('1v1_challenger') ||
        (lobby.lobbyTitle?.toLowerCase().contains('challenger') ?? false);

    final perPerson = lobby.perPersonShareEgp.toStringAsFixed(0);
    final title = lobby.lobbyTitle ??
        (isChallenger
            ? (isArabic ? 'مطلوب منافس ١ ضد ١' : '1v1 Challenger Needed')
            : (isArabic ? 'كمّل الشلة' : 'Open Shilla Match'));

    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isChallenger
              ? Colors.amber.withValues(alpha: 0.4)
              : theme.colorScheme.primary.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: (isChallenger ? Colors.amber : theme.colorScheme.primary)
                .withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isChallenger
                          ? Colors.amber.withValues(alpha: 0.2)
                          : theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isChallenger
                          ? (isArabic ? '⚔️ مطلوب منافس' : '⚔️ 1v1 Challenge')
                          : (isArabic ? '👥 ناقص أفراد' : '👥 Need Players'),
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: isChallenger ? Colors.amber.shade300 : theme.colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${lobby.startTime.hour.toString().padLeft(2, '0')}:${lobby.startTime.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${lobby.venueName ?? "Hagzy Venue"} • ${lobby.venueCity ?? "Kafr El Sheikh"}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.0,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            // Slot progress bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        isArabic
                            ? '${lobby.filledSlots}/${lobby.totalSlots} مكان مكتمل'
                            : '${lobby.filledSlots}/${lobby.totalSlots} Slots Taken',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.0,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isArabic ? '$perPerson ج.م / فرد' : '$perPerson EGP/player',
                      style: TextStyle(
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: lobby.totalSlots > 0 ? (lobby.filledSlots / lobby.totalSlots) : 0.5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isChallenger ? Colors.amber : theme.colorScheme.primary,
                    ),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
            SizedBox(
              width: double.infinity,
              height: 32,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isChallenger ? Colors.amber : theme.colorScheme.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  isChallenger
                      ? (isArabic ? 'اقبل التحدي ⚔️' : 'Accept Challenge ⚔️')
                      : (isArabic ? 'احجز مكانك في الشلة' : 'Claim My Spot'),
                  style: const TextStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
