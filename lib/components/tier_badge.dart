import 'package:flutter/material.dart';
import 'package:hajj_wallet/theme.dart';

/// TierBadge renders a compact pill badge for user tiers.
///
/// Parameters:
/// - tier: 'Silver' | 'Gold' | 'Platinum' (case-insensitive supported)
/// - size: 'sm' | 'md' | 'lg' (default: 'md')
/// - light: when true, forces white text/icon for use on dark backgrounds
class TierBadge extends StatelessWidget {
  const TierBadge({super.key, required this.tier, this.size = 'md', this.light = false});

  final String tier;
  final String size;
  final bool light;

  @override
  Widget build(BuildContext context) {
    final t = tier.trim().toLowerCase();

    // Colors per tier
    Color bg;
    Color fg;
    Color? border;
    IconData icon;

    switch (t) {
      case 'gold':
        bg = AppColors.tierGoldBg;
        fg = AppColors.tierGoldText;
        border = AppColors.tierGoldText.withValues(alpha: 0.25);
        icon = Icons.star;
        break;
      case 'platinum':
        bg = AppColors.tierPlatinumBg;
        fg = AppColors.tierPlatinumText;
        border = AppColors.tierPlatinumBorder;
        icon = Icons.diamond;
        break;
      case 'silver':
      default:
        bg = AppColors.tierSilverBg;
        fg = AppColors.tierSilverText;
        border = AppColors.tierSilverText.withValues(alpha: 0.25);
        icon = Icons.shield_outlined;
    }

    // Size mapping (textSize/iconSize/padding)
    double textSize;
    double iconSize;
    EdgeInsets padding;
    switch (size) {
      case 'sm':
        textSize = 10;
        iconSize = 12;
        padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
        break;
      case 'lg':
        textSize = 14;
        iconSize = 16;
        padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
        break;
      case 'md':
      default:
        textSize = 12;
        iconSize = 14;
        padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6);
    }

    final textColor = light ? Colors.white : fg;
    final iconColor = light ? Colors.white : fg;
    final borderColor = light ? Colors.white.withValues(alpha: 0.30) : border;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: borderColor ?? Colors.transparent, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: iconColor),
          const SizedBox(width: 4),
          Text(
            _displayText(tier),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: textSize,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
          ),
        ],
      ),
    );
  }

  String _displayText(String raw) {
    if (raw.isEmpty) return 'Silver';
    final lower = raw.toLowerCase();
    if (lower == 'gold') return 'Gold';
    if (lower == 'platinum') return 'Platinum';
    return 'Silver';
  }
}
