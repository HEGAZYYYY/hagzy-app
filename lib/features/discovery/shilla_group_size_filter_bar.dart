import 'package:flutter/material.dart';
import '../../core/utils/smart_defaults.dart';

/// Group-Size Filter Bar ("Shilla Filter") enforcing Principle 1 (Smart Defaults)
class ShillaGroupSizeFilterBar extends StatelessWidget {
  final ShillaSizePreset selectedPreset;
  final ValueChanged<ShillaSizePreset> onPresetSelected;
  final bool isArabic;

  const ShillaGroupSizeFilterBar({
    super.key,
    required this.selectedPreset,
    required this.onPresetSelected,
    this.isArabic = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Row(
            children: [
              Icon(
                Icons.group_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                isArabic ? 'حجم الشلة (تصفية فورية)' : 'Shilla Group Size',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            scrollDirection: Axis.horizontal,
            itemCount: ShillaSizePreset.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final preset = ShillaSizePreset.values[index];
              final isSelected = preset == selectedPreset;
              final label = isArabic ? preset.labelAr : preset.labelEn;

              IconData icon;
              switch (preset) {
                case ShillaSizePreset.all:
                  icon = Icons.grid_view_rounded;
                  break;
                case ShillaSizePreset.solo:
                  icon = Icons.person_rounded;
                  break;
                case ShillaSizePreset.duo:
                  icon = Icons.people_outline_rounded;
                  break;
                case ShillaSizePreset.group:
                  icon = Icons.groups_rounded;
                  break;
                case ShillaSizePreset.squad:
                  icon = Icons.sports_soccer_rounded;
                  break;
              }

              return ChoiceChip(
                showCheckmark: false,
                avatar: Icon(
                  icon,
                  size: 15,
                  color: isSelected ? Colors.white : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                label: Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected ? Colors.white : null,
                    fontSize: 12,
                  ),
                ),
                selected: isSelected,
                selectedColor: Theme.of(context).colorScheme.primary,
                backgroundColor: Theme.of(context).cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).dividerColor.withValues(alpha: 0.25),
                  ),
                ),
                onSelected: (selected) {
                  if (selected) {
                    onPresetSelected(preset);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

