import 'package:flutter/material.dart';
import '../../theme/hagzy_theme.dart';
import '../../widgets/hagzy_components.dart';

/// Loss-Aversion Checkout Exit Modal (Principle 5)
/// Triggered if user attempts to back out of a prime slot checkout
class LossAversionExitDialog extends StatelessWidget {
  final String slotTimeFormatted; // e.g., "Thursday 9:00 PM"
  final String venueName;
  final int recentViewersCount;
  final VoidCallback onKeepSlot;
  final VoidCallback onReleaseSlot;
  final bool isArabic;
  final bool isSheet;

  const LossAversionExitDialog({
    super.key,
    required this.slotTimeFormatted,
    required this.venueName,
    this.recentViewersCount = 4,
    required this.onKeepSlot,
    required this.onReleaseSlot,
    this.isArabic = false,
    this.isSheet = false,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String slotTimeFormatted,
    required String venueName,
    int recentViewersCount = 4,
    bool isArabic = false,
  }) {
    return showHagzyAdaptiveModal<bool>(
      context: context,
      barrierDismissible: false,
      enableDrag: false,
      builder: (ctx, isSheet) => LossAversionExitDialog(
        slotTimeFormatted: slotTimeFormatted,
        venueName: venueName,
        recentViewersCount: recentViewersCount,
        isArabic: isArabic,
        isSheet: isSheet,
        onKeepSlot: () => Navigator.of(ctx).pop(false),
        onReleaseSlot: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || kDarkMode.value;

    final headline = isArabic
        ? 'تفرّط في ميعاد $slotTimeFormatted في $venueName؟'
        : 'Release $slotTimeFormatted at $venueName?';

    final socialProof = isArabic
        ? '$recentViewersCount أشخاص تصفحوا هذا الميعاد مؤخراً. بمجرد الرجوع قد يحجزه شخص آخر فوراً.'
        : '$recentViewersCount other people viewed this slot recently. Once released, someone else may book it instantly.';

    return HagzyModalCard(
      isSheet: isSheet,
      showCloseButton: false,
      icon: Icons.warning_amber_rounded,
      iconColor: kGold,
      iconBackgroundColor: kGold.withValues(alpha: isDark ? 0.22 : 0.14),
      title: headline,
      content: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kSurfaceSubtle,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Text(
          socialProof,
          style: TextStyle(
            fontSize: 13.5,
            color: kMuted,
            height: 1.48,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      customActions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: onKeepSlot,
              child: Text(
                isArabic ? 'احتفظ بميعادي 🔒' : 'Keep My Slot 🔒',
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onReleaseSlot,
            style: TextButton.styleFrom(
              backgroundColor: kError.withValues(alpha: 0.08),
              foregroundColor: kError,
              minimumSize: const Size(0, 46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              isArabic ? 'فرّط في الميعاد لغيرك' : 'Release slot to others',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
