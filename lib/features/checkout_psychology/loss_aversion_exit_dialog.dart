import 'package:flutter/material.dart';

/// Loss-Aversion Checkout Exit Modal (Principle 5)
/// Triggered if user attempts to back out of a prime slot checkout
class LossAversionExitDialog extends StatelessWidget {
  final String slotTimeFormatted; // e.g., "Thursday 9:00 PM"
  final String venueName;
  final int recentViewersCount;
  final VoidCallback onKeepSlot;
  final VoidCallback onReleaseSlot;
  final bool isArabic;

  const LossAversionExitDialog({
    super.key,
    required this.slotTimeFormatted,
    required this.venueName,
    this.recentViewersCount = 4,
    required this.onKeepSlot,
    required this.onReleaseSlot,
    this.isArabic = false,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String slotTimeFormatted,
    required String venueName,
    int recentViewersCount = 4,
    bool isArabic = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => LossAversionExitDialog(
        slotTimeFormatted: slotTimeFormatted,
        venueName: venueName,
        recentViewersCount: recentViewersCount,
        isArabic: isArabic,
        onKeepSlot: () => Navigator.of(ctx).pop(false), // don't pop checkout
        onReleaseSlot: () => Navigator.of(ctx).pop(true), // confirm release
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final headline = isArabic
        ? 'تفرّط في ميعاد $slotTimeFormatted في $venueName؟'
        : 'Release $slotTimeFormatted at $venueName?';

    final socialProof = isArabic
        ? '⚠️ $recentViewersCount أشخاص تصفحوا هذا الميعاد مؤخراً. بمجرد الرجوع قد يحجزه شخص آخر فوراً.'
        : '⚠️ $recentViewersCount other people viewed this slot recently. Once released, someone else may book it instantly.';

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.amber.withValues(alpha: 0.4), width: 1.2),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              headline,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.2)),
            ),
            child: Text(
              socialProof,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Primary Loss-Aversion CTA: "Keep My Slot"
            ElevatedButton(
              onPressed: onKeepSlot,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                isArabic ? 'احتفظ بميعادي 🔒' : 'Keep My Slot 🔒',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
              ),
            ),
            const SizedBox(height: 8),

            // Dismiss Loss-Aversion CTA: "Release slot to others" (never neutral "Cancel")
            TextButton(
              onPressed: onReleaseSlot,
              style: TextButton.styleFrom(
                foregroundColor: Colors.redAccent,
              ),
              child: Text(
                isArabic ? 'فرّط في الميعاد لغيرك' : 'Release slot to others',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

