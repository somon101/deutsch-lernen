import 'package:flutter/material.dart';

import '../../models/leaderboard_entry.dart';
import 'podium_place.dart';

// Mirrors the approved mockup's .pod-2/.pod-1/.pod-3 animation-delay values
// exactly (50ms/160ms/270ms), 620ms rise each.
const _delayByRank = {2: Duration(milliseconds: 50), 1: Duration(milliseconds: 160), 3: Duration(milliseconds: 270)};
const _riseDuration = Duration(milliseconds: 620);

/// Top-3 podium, columns in 2-1-3 left-to-right order (§ leaderboard
/// redesign, 2026-09-04) — [entries] is whatever ranks 1..3 actually exist
/// (0-3 of them; fewer than 3 participants just omits the missing slot
/// rather than drawing an empty one, per spec). Plays its staggered
/// fade+slide+scale entrance once when first built and again whenever the
/// entry set changes (a period switch reloading different people),
/// respecting MediaQuery.disableAnimations.
class LeaderboardPodium extends StatefulWidget {
  const LeaderboardPodium({super.key, required this.entries, required this.onTapEntry});

  final List<LeaderboardEntry> entries;
  final ValueChanged<LeaderboardEntry> onTapEntry;

  @override
  State<LeaderboardPodium> createState() => _LeaderboardPodiumState();
}

class _LeaderboardPodiumState extends State<LeaderboardPodium> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration get _totalDuration => _delayByRank.values.reduce((a, b) => a > b ? a : b) + _riseDuration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    _play();
  }

  void _play() {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant LeaderboardPodium oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed = oldWidget.entries.length != widget.entries.length ||
        [for (var i = 0; i < widget.entries.length; i++) widget.entries[i].userId] !=
            [for (var i = 0; i < oldWidget.entries.length; i++) oldWidget.entries[i].userId];
    if (changed) _play();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Interval _intervalFor(int rank) {
    final delay = _delayByRank[rank]!;
    final totalMs = _totalDuration.inMilliseconds;
    final start = delay.inMilliseconds / totalMs;
    final end = (delay.inMilliseconds + _riseDuration.inMilliseconds) / totalMs;
    return Interval(start, end.clamp(0.0, 1.0), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    LeaderboardEntry? byRank(int rank) {
      for (final e in widget.entries) {
        if (e.rank == rank) return e;
      }
      return null;
    }
    // Left-to-right visual order is always 2, 1, 3 — any rank missing (< 3
    // participants) is simply skipped, not replaced with an empty slot.
    final ordered = [for (final rank in [2, 1, 3]) if (byRank(rank) != null) (rank: rank, entry: byRank(rank)!)];
    if (ordered.isEmpty) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final o in ordered)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _intervalFor(o.rank).transform(_controller.value).clamp(0.0, 1.0);
              return Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, 26 * (1 - t)),
                  child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
                ),
              );
            },
            child: PodiumPlace(entry: o.entry, rank: o.rank, onTap: () => widget.onTapEntry(o.entry)),
          ),
      ],
    );
  }
}
