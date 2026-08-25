import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/profile_gamification_repository.dart';
import '../profile_tokens.dart';

class _HexagonClipper extends CustomClipper<Path> {
  const _HexagonClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      // Flat-top hexagon: first vertex at -90deg so two edges are horizontal.
      final angle = (math.pi / 180) * (60 * i - 90);
      final x = w / 2 + (w / 2) * math.cos(angle);
      final y = h / 2 + (h / 2) * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

IconData _iconFor(String name) => switch (name) {
      'mic' => Icons.mic,
      'week' => Icons.calendar_month,
      'target' => Icons.track_changes,
      'trophy' => Icons.emoji_events,
      _ => Icons.lock,
    };

/// Hexagonal achievement badge — 64px, 2px stroke, three visual states:
/// earned (full accent color), in-progress (accent, dimmed a touch, no
/// lock), locked (muted fill with a lock glyph instead of the achievement
/// icon).
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final locked = achievement.state == AchievementState.locked;
    final iconColor = locked ? c.textMuted : Colors.white;
    final fill = switch (achievement.state) {
      AchievementState.earned => c.accent,
      AchievementState.inProgress => c.accent.withValues(alpha: 0.75),
      AchievementState.locked => c.border,
    };

    return SizedBox(
      width: ProfileMetrics.badgeSize + 16,
      child: Column(
        children: [
          SizedBox(
            width: ProfileMetrics.badgeSize,
            height: ProfileMetrics.badgeSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipPath(clipper: const _HexagonClipper(), child: Container(color: fill)),
                ClipPath(
                  clipper: const _HexagonClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: locked ? c.border : c.accent, width: ProfileMetrics.badgeStroke),
                    ),
                  ),
                ),
                Icon(locked ? Icons.lock_outline : _iconFor(achievement.icon), color: iconColor, size: 26),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            achievement.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: ProfileTypography.caption(context).copyWith(fontWeight: FontWeight.w600, color: c.text),
          ),
          const SizedBox(height: 2),
          Text(achievement.subtitle, textAlign: TextAlign.center, style: ProfileTypography.caption(context)),
        ],
      ),
    );
  }
}
