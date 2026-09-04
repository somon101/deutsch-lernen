import 'package:flutter/material.dart';

/// Loading placeholder — a podium-shaped skeleton plus 5 row skeletons,
/// instead of a full-screen spinner (§ leaderboard redesign, 2026-09-04).
/// No shimmer/skeleton package exists anywhere else in this app yet (a
/// full grep turned up nothing), so this is a from-scratch, dependency-free
/// pulsing-opacity treatment rather than a real shimmer sweep.
class LeaderboardSkeleton extends StatefulWidget {
  const LeaderboardSkeleton({super.key});

  @override
  State<LeaderboardSkeleton> createState() => _LeaderboardSkeletonState();
}

class _LeaderboardSkeletonState extends State<LeaderboardSkeleton> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.5 + 0.5 * _controller.value;
        return Opacity(
          opacity: opacity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Block(height: 42, radius: 16, color: base),
                const SizedBox(height: 24),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PodiumColumn(diameter: 66, color: base),
                    const SizedBox(width: 12),
                    _PodiumColumn(diameter: 92, color: base),
                    const SizedBox(width: 12),
                    _PodiumColumn(diameter: 66, color: base),
                  ],
                ),
                const SizedBox(height: 24),
                _Block(height: 64, radius: 18, color: base),
                const SizedBox(height: 20),
                for (var i = 0; i < 5; i++) ...[
                  _Block(height: 62, radius: 18, color: base),
                  const SizedBox(height: 7),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.height, required this.radius, required this.color});
  final double height;
  final double radius;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: height, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)));
}

class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({required this.diameter, required this.color});
  final double diameter;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: diameter, height: diameter, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 8),
        Container(width: diameter * 0.8, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      ],
    );
  }
}
