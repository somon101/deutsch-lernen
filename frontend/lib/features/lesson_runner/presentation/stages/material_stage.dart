import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/word_audio_button.dart';
import '../../../../l10n/app_localizations.dart';
import '../../data/lesson_repository.dart';
import '../../domain/exercise.dart';
import '../../domain/lesson_content.dart';
import '../lesson_runner_controller.dart';
import '../widgets/auto_blank_question.dart';
import '../widgets/choice_question.dart';
import '../widgets/cloze_question.dart';
import '../widgets/match_question.dart';
import '../widgets/scramble_question.dart';
import '../widgets/truefalse_question.dart';

class _Group {
  _Group({this.title});
  final String? title;
  final List<MaterialBlock> blocks = [];
}

/// Mirrors MaterialStage.tsx's groupBlocks: a new "step" block starts a new
/// page; every other block joins the current page. Paginated by page, not
/// rendered all at once.
List<_Group> _groupBlocks(List<MaterialBlock> blocks, AppLocalizations l10n) {
  final groups = <_Group>[];
  var current = _Group();

  for (final block in blocks) {
    if (block is MaterialStepBlock) {
      if (current.blocks.isNotEmpty) groups.add(current);
      current = _Group(title: l10n.materialStageStepTitle(block.number, block.title))..blocks.add(block);
    } else if (block is MaterialGenericBlock) {
      if (current.blocks.isNotEmpty) groups.add(current);
      current = _Group(title: block.title)..blocks.add(block);
    } else {
      current.blocks.add(block);
    }
  }
  if (current.blocks.isNotEmpty) groups.add(current);
  return groups;
}

/// Mirrors MaterialStage.tsx: the lesson's text material, split into
/// step-grouped pages the learner flips through with Назад/Далее.
class MaterialStage extends ConsumerStatefulWidget {
  const MaterialStage({super.key, required this.runnerKey, required this.onComplete, this.materialOverride, this.nextLabel});

  final LessonRunnerKey runnerKey;
  final VoidCallback onComplete;
  // A graph "material" node's OWN blocks (§ lesson graph, 2026-09-03) —
  // fetched by the caller via LessonRepository.fetchMaterialBlocksForNode,
  // since the shared content's flat `material` field loses which Material
  // row a block came from once a lesson has more than one. Null keeps the
  // original lesson-wide `data.content.material` behavior.
  final List<MaterialBlock>? materialOverride;
  final String? nextLabel;

  @override
  ConsumerState<MaterialStage> createState() => _MaterialStageState();
}

/// Per-section time cap (§ time tracking, 2026-08-29) — a section left open
/// longer than this contributes at most this many seconds, so it can't be
/// artificially inflated by just leaving it open.
const _materialSectionCapSeconds = 120;

class _MaterialStageState extends ConsumerState<MaterialStage> {
  int _page = 0;
  DateTime _sectionShownAt = DateTime.now();

  /// Held as a field so `dispose()` can still report the time for a stage
  /// the learner walked out of. Reading `ref` during dispose is not merely
  /// discouraged — flutter_riverpod throws, and because the throw landed
  /// before `super.dispose()`, the time was lost AND the dispose contract
  /// was broken (§ daily goal, 2026-09-03; same fix already applied to
  /// exercise_stage).
  LessonRunnerController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier);
  }

  /// Flushes the section being LEFT (still the current `_page` at call
  /// time) before switching pages or leaving the stage entirely.
  void _flushSection() {
    final elapsed = DateTime.now().difference(_sectionShownAt).inSeconds.clamp(0, _materialSectionCapSeconds);
    _sectionShownAt = DateTime.now();
    if (elapsed > 0) {
      _controller?.recordActivityTime('material', elapsed);
    }
  }

  void _goToPage(int page) {
    _flushSection();
    setState(() => _page = page);
  }

  @override
  void dispose() {
    _flushSection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    final groups = _groupBlocks(widget.materialOverride ?? data.content.material, l10n);

    if (groups.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.materialStageMissing, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(l10n.materialStageNotFound, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: widget.onComplete, child: Text(l10n.lessonStageSkip)),
          ],
        ),
      );
    }

    final page = _page.clamp(0, groups.length - 1);
    final isLast = page == groups.length - 1;
    final group = groups[page];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.materialStageSection(page + 1, groups.length), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final block in group.blocks) _MaterialBlockView(block: block, vocabulary: data.content.vocabulary),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton(
                onPressed: page > 0 ? () => _goToPage(page - 1) : null,
                child: Text(l10n.materialStageBack),
              ),
              ElevatedButton(
                onPressed: () {
                  if (isLast) {
                    _flushSection();
                    widget.onComplete();
                  } else {
                    _goToPage(page + 1);
                  }
                },
                child: Text(isLast ? (widget.nextLabel ?? l10n.materialStageDefaultNextVideo) : l10n.materialStageNextArrow),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MaterialBlockView extends StatelessWidget {
  const _MaterialBlockView({required this.block, required this.vocabulary});

  final MaterialBlock block;
  final List<VocabularyEntry> vocabulary;

  @override
  Widget build(BuildContext context) {
    final b = block;
    return switch (b) {
      MaterialTitleBlock() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(b.text, style: Theme.of(context).textTheme.headlineSmall),
        ),
      MaterialStepBlock() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              CircleAvatar(radius: 14, child: Text('${b.number}')),
              const SizedBox(width: 10),
              Expanded(child: Text(b.title, style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
        ),
      MaterialSubheadingBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              if (b.icon != null) Padding(padding: const EdgeInsets.only(right: 6), child: Text(b.icon!)),
              Expanded(child: Text(b.text, style: Theme.of(context).textTheme.titleSmall)),
            ],
          ),
        ),
      MaterialPhraseBlock() => _PhraseView(block: b, vocabulary: vocabulary),
      MaterialLineBlock() => Padding(
          padding: EdgeInsets.only(bottom: b.tight ? 2 : 10),
          child: Text(b.text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      MaterialGenericBlock() => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(b.content, style: Theme.of(context).textTheme.bodyLarge),
              if (b.questions.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final exercise in b.questions)
                  Padding(padding: const EdgeInsets.only(bottom: 12), child: _InlineCheckpointQuestion(key: ValueKey(exercise.id), exercise: exercise)),
              ],
            ],
          ),
        ),
    };
  }
}

/// One reusable-pool question attached to a MaterialBlock, answered as a
/// checkpoint right where it appears in the reading flow (2026-08-26
/// decision: "внутри чтения материала") — reuses the exact same per-kind
/// widgets the quiz stages use, just without ExerciseStage's scoring/
/// results-screen wrapper, since a single inline checkpoint isn't a "test".
class _InlineCheckpointQuestion extends ConsumerWidget {
  const _InlineCheckpointQuestion({super.key, required this.exercise});
  final Exercise exercise;

  Future<void> _handleAnswered(WidgetRef ref, bool correct) async {
    try {
      await ref.read(lessonRepositoryProvider).submitAnswer(exercise.id, correct, placementId: exercise.placementId);
    } catch (_) {
      // Best-effort — a logging failure must never block reading the lesson.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void onAnswered(bool correct) => _handleAnswered(ref, correct);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (exercise) {
          ChoiceQuestion e => ChoiceQuestionView(exercise: e, onAnswered: onAnswered),
          TrueFalseQuestion e => TrueFalseQuestionView(exercise: e, onAnswered: onAnswered),
          ClozeExercise e => ClozeQuestionView(exercise: e, onAnswered: onAnswered),
          ScrambleExercise e => ScrambleQuestionView(exercise: e, onAnswered: onAnswered),
          MatchExercise e => MatchQuestionView(exercise: e, onAnswered: onAnswered),
          // Auto-translate blocks are a quiz-stage exercise; they are never
          // placed inline in a material block, so this branch only exists to
          // keep the switch exhaustive.
          AutoTranslateSlot() => const SizedBox.shrink(),
          AutoMatchSlot() => const SizedBox.shrink(),
          // No prefetch buffer here (there's no linear "next slot" concept
          // reading through material blocks) - the widget generates its own
          // question on first build, and already writes its own AnswerLog
          // via submitBlankAnswer, so onAnswered here is JUST the scoring
          // callback, never the generic submitAnswer above (§ auto blank,
          // 2026-08-31 - same reasoning as ExerciseStage's own skip of it).
          AutoBlankSlot e => AutoBlankQuestionView(exercise: e, onAnswered: (_) {}),
        },
      ),
    );
  }
}

class _PhraseView extends StatelessWidget {
  const _PhraseView({required this.block, required this.vocabulary});

  final MaterialPhraseBlock block;
  final List<VocabularyEntry> vocabulary;

  @override
  Widget build(BuildContext context) {
    String? recordedAudio;
    for (final v in vocabulary) {
      if (v.german.toLowerCase() == block.german.toLowerCase()) {
        recordedAudio = v.audioUrl;
        break;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (block.icon != null) Text('${block.icon} '),
                    Flexible(
                      child: Text(block.german, style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (block.pronunciation != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Text('[${block.pronunciation}]', style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
                Text(block.translation, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          WordAudioButton(word: block.german, audioUrl: recordedAudio, size: 18),
        ],
      ),
    );
  }
}
