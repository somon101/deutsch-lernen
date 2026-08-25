import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/seeded_random.dart';
import '../../../../core/utils/sound_effects.dart';
import '../../grading/match_grader.dart';
import '../../domain/exercise.dart';

/// Mirrors MatchView.tsx — see match_grader.dart's MatchGrader for the "0
/// wrong attempts" correctness rule this widget delegates to.
class MatchQuestionView extends ConsumerStatefulWidget {
  const MatchQuestionView({super.key, required this.exercise, required this.onAnswered});

  final MatchExercise exercise;
  final ValueChanged<bool> onAnswered;

  @override
  ConsumerState<MatchQuestionView> createState() => _MatchQuestionViewState();
}

class _MatchQuestionViewState extends ConsumerState<MatchQuestionView> {
  late final MatchGrader _grader = MatchGrader(widget.exercise.pairs);
  late final List<MatchPair> _left = shuffleSeeded(widget.exercise.pairs, seededRandom(hashString('${widget.exercise.id}-left')));
  late final List<MatchPair> _right = shuffleSeeded(widget.exercise.pairs, seededRandom(hashString('${widget.exercise.id}-right')));

  String? _selectedLeft;
  String? _selectedRight;
  ({String left, String right})? _wrongPair;
  bool _finished = false;

  void _attempt(String? leftId, String? rightId) {
    if (leftId == null || rightId == null) return;

    if (leftId == rightId) {
      _grader.attempt(leftPairId: leftId, rightPairId: rightId);
      setState(() {
        _selectedLeft = null;
        _selectedRight = null;
      });
      ref.read(soundEffectsProvider).playCorrect();
      if (_grader.isComplete && !_finished) {
        _finished = true;
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) widget.onAnswered(_grader.isCorrect);
        });
      }
      return;
    }

    _grader.attempt(leftPairId: leftId, rightPairId: rightId);
    setState(() => _wrongPair = (left: leftId, right: rightId));
    ref.read(soundEffectsProvider).playIncorrect();
    Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _wrongPair = null;
        _selectedLeft = null;
        _selectedRight = null;
      });
    });
  }

  void _pickLeft(String id) {
    if (_grader.isPairMatched(id) || _wrongPair != null) return;
    setState(() => _selectedLeft = id);
    _attempt(id, _selectedRight);
  }

  void _pickRight(String id) {
    if (_grader.isPairMatched(id) || _wrongPair != null) return;
    setState(() => _selectedRight = id);
    _attempt(_selectedLeft, id);
  }

  Color? _bg(BuildContext context, String id, {required bool isLeft}) {
    final scheme = Theme.of(context).colorScheme;
    if (_grader.isPairMatched(id)) return Colors.green.withValues(alpha: 0.15);
    final wrongId = isLeft ? _wrongPair?.left : _wrongPair?.right;
    if (wrongId == id) return scheme.errorContainer;
    final selectedId = isLeft ? _selectedLeft : _selectedRight;
    if (selectedId == id) return scheme.primaryContainer;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Сопоставьте немецкие слова с переводом', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  for (final pair in _left)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MatchCell(
                        label: pair.left,
                        background: _bg(context, pair.id, isLeft: true),
                        onTap: _grader.isPairMatched(pair.id) ? null : () => _pickLeft(pair.id),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  for (final pair in _right)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MatchCell(
                        label: pair.right,
                        background: _bg(context, pair.id, isLeft: false),
                        onTap: _grader.isPairMatched(pair.id) ? null : () => _pickRight(pair.id),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Сопоставлено: ${widget.exercise.pairs.where((p) => _grader.isPairMatched(p.id)).length} / ${widget.exercise.pairs.length}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _MatchCell extends StatelessWidget {
  const _MatchCell({required this.label, required this.background, required this.onTap});

  final String label;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: background,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        alignment: Alignment.centerLeft,
        minimumSize: const Size.fromHeight(0),
      ),
      child: Text(label, textAlign: TextAlign.left),
    );
  }
}
