import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/admin_feedback.dart';
import '../../../admin_tokens.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
import '../../domain/taxonomy_domain.dart';
import 'block_editor.dart';
import 'lesson_map_view.dart';
import 'material_block_editor.dart';
import 'media_editor.dart';
import 'vocabulary_editor.dart';

const _chain = [
  (key: 'vocabulary', label: 'Слова', note: 'карточки словаря'),
  (key: 'material', label: 'Материал', note: 'текст урока'),
  (key: 'video', label: 'Видео', note: null),
  (key: 'minitest', label: 'Мини-тест', note: 'вопросы после видео'),
  (key: 'audio', label: 'Аудио', note: 'прослушивание, без заданий'),
  (key: 'practice', label: 'Практика', note: 'вопросы'),
  (key: 'review', label: 'Закрепление', note: 'итоговый тест урока'),
  (key: 'complete', label: 'Итог', note: 'экран результатов'),
];

/// Terse rail counter (§ course-builder redesign, "рельс этапов", 2026-09-01
/// — "12, ✓, ✗, авто" per the spec's own mockup) — computed from the
/// lesson's real data, never hardcoded, so an admin can tell a stage is
/// empty without opening it. A word/question count of zero renders muted
/// (see _RailItem) rather than as a different string — the rail's whole
/// point is that the number itself is the signal.
String _counterFor(AdminLesson lesson, String key, int? materialBlockCount) {
  switch (key) {
    case 'vocabulary':
      return '${lesson.vocabulary.length}';
    case 'material':
      return materialBlockCount == null ? '…' : '$materialBlockCount';
    case 'video':
      return lesson.videoUrl != null && lesson.videoUrl!.isNotEmpty ? '✓' : '✗';
    case 'audio':
      return lesson.audioUrl != null && lesson.audioUrl!.isNotEmpty ? '✓' : '✗';
    case 'minitest':
    case 'practice':
    case 'review':
      final blocks = lesson.blocksFor(key);
      final questions = blocks.fold(0, (sum, b) => sum + b.questions.length);
      return '$questions';
    case 'complete':
    default:
      return 'авто';
  }
}

/// True when a stage has real content — drives the rail counter's muted vs
/// ink color (§ course-builder redesign, 2026-09-01).
bool _hasContent(AdminLesson lesson, String key, int? materialBlockCount) {
  switch (key) {
    case 'vocabulary':
      return lesson.vocabulary.isNotEmpty;
    case 'material':
      return (materialBlockCount ?? 0) > 0;
    case 'video':
      return lesson.videoUrl != null && lesson.videoUrl!.isNotEmpty;
    case 'audio':
      return lesson.audioUrl != null && lesson.audioUrl!.isNotEmpty;
    case 'minitest':
    case 'practice':
    case 'review':
      return lesson.blocksFor(key).any((b) => b.questions.isNotEmpty);
    case 'complete':
    default:
      return true;
  }
}

/// Mirrors BuilderLessonEditor.tsx's LESSON_CHAIN — one reusable 8-step
/// editor, used identically for legacy lessons (courseId "legacy") and
/// builder-course lessons; only material/media save differently between the
/// two (injected via callbacks), vocabulary/blocks always go through
/// BuilderRepository regardless of courseId (see the migration notes).
class LessonEditorPanel extends ConsumerStatefulWidget {
  const LessonEditorPanel({
    super.key,
    required this.courseId,
    required this.lesson,
    required this.libraryLoader,
    required this.onUploadMedia,
    required this.onRemoveMedia,
    required this.onReuseMedia,
    required this.onReload,
    this.languageId,
    this.scrollBottomInset = 0,
  });

  /// Padding added at the bottom of the panel's own scroll areas — the
  /// mobile tab bar's height, so the last row isn't hidden behind it. Sits
  /// here rather than on the screen's outer padding because the scrolling
  /// moved inside the panel (§ pinned header + independent scroll,
  /// 2026-09-02).
  final double scrollBottomInset;

  final String courseId;
  final AdminLesson lesson;
  final Future<List<MediaLibraryEntry>> Function(String kind) libraryLoader;
  final Future<void> Function(String kind, List<int> bytes, String filename)
  onUploadMedia;
  final Future<void> Function(String kind) onRemoveMedia;
  final Future<void> Function(String kind, String url) onReuseMedia;
  final VoidCallback onReload;
  // The course's resolved Language.id — threaded down to MaterialBlockEditor
  // for topic creation (§ topic-language fix, 2026-09-01). Null for legacy
  // lessons and for a builder course with no level/language picked yet.
  final String? languageId;

  @override
  ConsumerState<LessonEditorPanel> createState() => _LessonEditorPanelState();
}

/// Manual send — always fires regardless of the auto-send setting (that
/// toggle, in the courses hub, only gates the automatic call made when a
/// lesson is added to an already-published course).
class _NotifyButton extends ConsumerStatefulWidget {
  const _NotifyButton({required this.courseId, required this.lessonId});
  final String courseId;
  final String lessonId;

  @override
  ConsumerState<_NotifyButton> createState() => _NotifyButtonState();
}

class _NotifyButtonState extends ConsumerState<_NotifyButton> {
  bool _busy = false;

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).notifyLessonCreated(widget.courseId, widget.lessonId);
      if (mounted) showSuccessSnack(context, 'Уведомление отправлено');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось отправить уведомление');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _busy ? null : _send,
        style: AdminButtonStyles.secondary(),
        icon: const Icon(Icons.notifications_outlined, size: 18),
        label: Text(_busy ? 'Отправляем…' : 'Отправить уведомление'),
      ),
    );
  }
}

/// Below this width the rail collapses into a horizontal icon strip, same
/// breakpoint concept as AppShell's own nav-rail/bottom-bar split (§
/// course-builder redesign, "рельс этапов", 2026-09-01).
const _railBreakpoint = 900.0;

class _LessonEditorPanelState extends ConsumerState<LessonEditorPanel> {
  String _selected = 'vocabulary';
  int? _materialBlockCount;

  @override
  void initState() {
    super.initState();
    _loadMaterialBlockCount();
  }

  // AdminLesson carries the quiz-stage `blocks` but not material blocks
  // (those live in a separate Material row MaterialBlockEditor fetches on
  // its own) — this is a lightweight, READ-ONLY mirror of just enough of
  // that fetch to show a real count on the rail, deliberately not calling
  // createMaterial (unlike MaterialBlockEditor._load) so merely glancing at
  // the rail can never conjure a Material row into existence.
  Future<void> _loadMaterialBlockCount() async {
    try {
      final repo = ref.read(builderRepositoryProvider);
      final materials = await repo.listMaterials(widget.lesson.id);
      final material = materials.where((m) => m.materialType == 'text').cast<AdminMaterial?>().firstWhere((m) => m != null, orElse: () => null);
      if (material == null) {
        if (mounted) setState(() => _materialBlockCount = 0);
        return;
      }
      final blocks = await repo.listMaterialBlocks(material.id);
      if (mounted) setState(() => _materialBlockCount = blocks.length);
    } catch (_) {
      // Non-critical — the rail counter just stays "…" indefinitely.
    }
  }

  /// Opens the read-only "Карта урока" overview (§8 of the redesign,
  /// 2026-09-01) and, if the teacher tapped an element in it, switches the
  /// rail to that step — the map itself never edits anything.
  Future<void> _openMap() async {
    final key = await showLessonConnectionsMap(
      context,
      courseId: widget.courseId,
      lessonId: widget.lesson.id,
      lessonTitle: widget.lesson.title,
    );
    if (key != null) _select(key);
  }

  void _select(String key) {
    setState(() => _selected = key);
    // Cheap enough to just always refresh — the admin may have just edited
    // material blocks on the stage they're navigating away from, and there
    // is no other signal that tells this widget the count changed.
    _loadMaterialBlockCount();
  }

  Future<void> _addBlock(String stage) async {
    final label = _chain.firstWhere((s) => s.key == stage).label;
    final existing = widget.lesson.blocksFor(stage).length;
    try {
      await ref
          .read(builderRepositoryProvider)
          .addBlock(
            widget.courseId,
            widget.lesson.id,
            stage,
            '$label ${existing + 1}',
          );
      widget.onReload();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось добавить блок');
    }
  }

  Future<void> _moveBlock(
    String stage,
    List<AdminBlock> blocks,
    int index,
    int delta,
  ) async {
    final j = index + delta;
    if (j < 0 || j >= blocks.length) return;
    final ids = blocks.map((b) => b.id).toList();
    final tmp = ids[index];
    ids[index] = ids[j];
    ids[j] = tmp;
    try {
      await ref
          .read(builderRepositoryProvider)
          .reorderBlocks(widget.courseId, widget.lesson.id, stage, ids);
      widget.onReload();
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e, 'Не удалось изменить порядок блоков');
      }
    }
  }

  /// The panel owns the scrolling now (§ pinned header + independent scroll,
  /// 2026-09-02) and therefore needs a bounded height — callers hand it an
  /// Expanded, never a ListView child. Only the working area scrolls: the
  /// rail stays put, so switching from a long word list to "Мини-тест" never
  /// means scrolling back to the top first.
  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= _railBreakpoint;
    final bottomInset = widget.scrollBottomInset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Legacy lessons predate courses/lessons as real Course rows, so
        // there's no course to check "already published" against — the
        // manual send only makes sense for a real builder course.
        if (widget.courseId != 'legacy') ...[
          _NotifyButton(courseId: widget.courseId, lessonId: widget.lesson.id),
          const SizedBox(height: AdminMetrics.cardGap),
        ],
        if (isWide)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: AdminMetrics.railWidth,
                  // The rail gets its own scroll purely as an overflow escape
                  // hatch — on a short window the 8 steps plus the map button
                  // can outgrow the viewport, and clipping them would hide
                  // exactly the navigation this change exists to keep visible.
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: _rail(context),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(bottom: bottomInset),
                    child: _workingArea(context),
                  ),
                ),
              ],
            ),
          )
        else ...[
          _horizontalRail(context),
          const SizedBox(height: AdminMetrics.cardGap),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _workingArea(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _workingArea(BuildContext context) {
    final step = _chain.firstWhere((s) => s.key == _selected);
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(step.label, style: AdminTypography.cardTitle),
          if (step.note != null) ...[
            const SizedBox(height: 2),
            Text(step.note!, style: AdminTypography.caption),
          ],
          const SizedBox(height: AdminMetrics.fieldGap),
          _body(context, _selected),
        ],
      ),
    );
  }

  /// The step rail (§ course-builder redesign, "рельс этапов", 2026-09-01):
  /// always visible, doesn't scroll away with the working area's own
  /// content, one continuous 1px line connecting every item top to bottom
  /// (the old interface's "↓" made literal) — the sequence is fixed, this
  /// is not a row of independent tabs.
  Widget _rail(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text('ЭТАПЫ', style: AdminTypography.fieldLabel),
        ),
        for (var i = 0; i < _chain.length; i++)
          _RailItem(
            number: i + 1,
            label: _chain[i].label,
            counter: _counterFor(widget.lesson, _chain[i].key, _materialBlockCount),
            hasContent: _hasContent(widget.lesson, _chain[i].key, _materialBlockCount),
            selected: _selected == _chain[i].key,
            isFirst: i == 0,
            isLast: i == _chain.length - 1,
            onTap: () => _select(_chain[i].key),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _openMap,
              style: AdminButtonStyles.secondary(),
              icon: const Icon(Icons.hub_outlined, size: 16),
              label: const Text('Карта урока'),
            ),
          ),
        ),
      ],
    );
  }

  /// Narrow-viewport counterpart (< 900px — phone, a squeezed window) —
  /// same idea as AppShell's own rail/bottom-bar split: a horizontal strip
  /// of icons under where the AppBar is, working area at full width below.
  Widget _horizontalRail(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final step in _chain)
            _HorizontalRailItem(
              label: step.label,
              selected: _selected == step.key,
              hasContent: _hasContent(widget.lesson, step.key, _materialBlockCount),
              onTap: () => _select(step.key),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: OutlinedButton.icon(
              onPressed: _openMap,
              style: AdminButtonStyles.secondary(),
              icon: const Icon(Icons.hub_outlined, size: 16),
              label: const Text('Карта'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, String key) {
    switch (key) {
      case 'vocabulary':
        return VocabularyEditor(
          courseId: widget.courseId,
          lessonId: widget.lesson.id,
          words: widget.lesson.vocabulary,
          onChanged: widget.onReload,
        );
      case 'material':
        return MaterialBlockEditor(
          courseId: widget.courseId,
          lessonId: widget.lesson.id,
          lessonTitle: widget.lesson.title,
          languageId: widget.languageId,
        );
      case 'video':
      case 'audio':
        final url = key == 'video'
            ? widget.lesson.videoUrl
            : widget.lesson.audioUrl;
        return MediaEditor(
          kind: key,
          url: url,
          libraryLoader: () => widget.libraryLoader(key),
          onUpload: (bytes, filename) =>
              widget.onUploadMedia(key, bytes, filename),
          onRemove: () => widget.onRemoveMedia(key),
          onReuse: (url) => widget.onReuseMedia(key, url),
        );
      case 'minitest':
      case 'practice':
      case 'review':
        final blocks = widget.lesson.blocksFor(key);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < blocks.length; i++)
              BlockEditor(
                key: ValueKey(blocks[i].id),
                courseId: widget.courseId,
                lessonId: widget.lesson.id,
                block: blocks[i],
                index: i,
                total: blocks.length,
                onMove: (delta) => _moveBlock(key, blocks, i, delta),
                onChanged: widget.onReload,
                languageId: widget.languageId,
              ),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _addBlock(key),
                style: AdminButtonStyles.secondary(),
                child: Text(
                  '+ Добавить ${_chain.firstWhere((s) => s.key == key).label.toLowerCase()}',
                ),
              ),
            ),
          ],
        );
      case 'complete':
      default:
        return Text(
          'Считается автоматически — экран результатов показывает итоги мини-теста, практики и закрепления.',
          style: AdminTypography.caption,
        );
    }
  }
}

/// One rail row: number circle, title, terse counter, and a continuous 1px
/// connecting line through the circle's center — half above (skipped for
/// the first item), half below (skipped for the last), so consecutive
/// items' segments join into one unbroken line rather than N separate
/// short ones. The selected item gets a `▸` marker and a background
/// slightly darker than the page (never the accent fill — §2 of the
/// redesign reserves that for connectivity indicators only).
class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.number,
    required this.label,
    required this.counter,
    required this.hasContent,
    required this.selected,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
  });

  final int number;
  final String label;
  final String counter;
  final bool hasContent;
  final bool selected;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;

  static const _circleSize = 24.0;
  static const _rowVPad = 8.0;

  Widget _lineSegment(bool visible) => SizedBox(
    width: _circleSize,
    height: _rowVPad,
    child: visible ? const Center(child: SizedBox(width: 1, height: _rowVPad, child: ColoredBox(color: AdminColors.border))) : null,
  );

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AdminColors.blockBg : null,
          borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
        ),
        child: Column(
          children: [
            _lineSegment(!isFirst),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: _circleSize,
                    height: _circleSize,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(shape: BoxShape.circle, border: Border.fromBorderSide(BorderSide(color: AdminColors.border))),
                    child: Text('$number', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AdminColors.text)),
                  ),
                  const SizedBox(width: 10),
                  if (selected) const Text('▸ ', style: TextStyle(color: AdminColors.text, fontWeight: FontWeight.w700)),
                  Expanded(
                    child: Text(
                      label,
                      style: AdminTypography.body.copyWith(fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    counter,
                    style: AdminTypography.caption.copyWith(color: hasContent ? AdminColors.text : AdminColors.textMuted),
                  ),
                ],
              ),
            ),
            _lineSegment(!isLast),
          ],
        ),
      ),
    );
  }
}

/// Narrow-viewport rail item — icon-free (this section has no icon set of
/// its own), just the label as a compact pill, matching the same
/// selected/muted vocabulary as [_RailItem].
class _HorizontalRailItem extends StatelessWidget {
  const _HorizontalRailItem({required this.label, required this.selected, required this.hasContent, required this.onTap});
  final String label;
  final bool selected;
  final bool hasContent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AdminColors.blockBg : null,
            border: Border.all(color: selected ? AdminColors.borderStrong : AdminColors.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: AdminTypography.body.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: hasContent ? AdminColors.text : AdminColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
