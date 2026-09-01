import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/admin_feedback.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../data/builder_repository.dart';
import '../../domain/block_question.dart';
import '../../domain/builder_domain.dart';
import 'pool_questions_section.dart';
import 'question_kind_editors.dart';

/// Mirrors BuilderBlockEditor.tsx — one named block of questions (any mix
/// of the 5 kinds), fully local-editable draft state, replaced wholesale on
/// "Сохранить вопросы" (matches the backend's PUT .../blocks/:id/questions
/// full-replace contract).
class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.block,
    required this.index,
    required this.total,
    required this.onMove,
    required this.onChanged,
  });

  final String courseId;
  final String lessonId;
  final AdminBlock block;
  final int index;
  final int total;
  final void Function(int delta) onMove;
  final VoidCallback onChanged;

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  bool _open = false;
  late List<QuestionDraft> _questions = _legacyQuestions(widget.block);
  late final _titleController = TextEditingController(text: widget.block.title);
  bool _busy = false;

  // Only the real, locally-editable LessonQuestion rows (§ course-builder
  // redesign bugfix, 2026-09-01) — widget.block.questions also carries any
  // reusable-pool questions placed here (needed elsewhere for the course's
  // aggregate question count), which must never enter this wholesale-save
  // draft list or they'd get duplicated into a new LessonQuestion row on
  // "Сохранить вопросы" while the pool original stays untouched. Pool
  // questions are shown/edited exclusively through PoolQuestionsSection.
  static List<QuestionDraft> _legacyQuestions(AdminBlock block) => [
    for (var i = 0; i < block.questions.length; i++)
      if (block.questionSources[i] != 'pool') block.questions[i],
  ];

  @override
  void didUpdateWidget(covariant BlockEditor old) {
    super.didUpdateWidget(old);
    if (old.block.id != widget.block.id) {
      _questions = _legacyQuestions(widget.block);
      _titleController.text = widget.block.title;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    if (_titleController.text.trim().isEmpty) return;
    try {
      await ref
          .read(builderRepositoryProvider)
          .renameBlock(
            widget.courseId,
            widget.lessonId,
            widget.block.id,
            _titleController.text.trim(),
          );
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось переименовать блок');
    }
  }

  Future<void> _deleteBlock() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить «${widget.block.title}» вместе с вопросами?',
    );
    if (!ok) return;
    try {
      await ref
          .read(builderRepositoryProvider)
          .removeBlock(widget.courseId, widget.lessonId, widget.block.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить блок');
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(builderRepositoryProvider)
          .saveBlockQuestions(
            widget.courseId,
            widget.lessonId,
            widget.block.id,
            _questions,
          );
      widget.onChanged();
      if (mounted) showSuccessSnack(context, 'Вопросы сохранены');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить вопросы');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _replaceQuestion(int i, QuestionDraft draft) =>
      setState(() => _questions = [..._questions]..[i] = draft);
  void _removeQuestion(int i) =>
      setState(() => _questions = [..._questions]..removeAt(i));
  void _moveQuestion(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _questions.length) return;
    setState(() {
      final copy = [..._questions];
      final tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
      _questions = copy;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(12),
      highlighted: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _open = !_open),
                  child: Text(
                    '${widget.block.title} (${widget.block.questions.length} вопросов)',
                    style: AdminTypography.stageTitle,
                  ),
                ),
              ),
              AdminReorderArrows(
                canMoveUp: widget.index > 0,
                canMoveDown: widget.index < widget.total - 1,
                onMove: widget.onMove,
              ),
              IconButton(
                icon: Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _open = !_open),
              ),
              const SizedBox(width: 4),
              AdminDeleteLink(onPressed: _deleteBlock),
            ],
          ),
          if (_open) ...[
            const Divider(height: 20, color: AdminColors.border),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    decoration: adminInputDecoration(label: 'Название блока'),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _rename,
                  style: AdminButtonStyles.text(),
                  child: const Text('Переименовать'),
                ),
              ],
            ),
            const SizedBox(height: AdminMetrics.fieldGap),
            // Existing static LessonQuestion rows stay fully editable in
            // place (§12: "переписать блок" must stay available) — but
            // there's no "+ add another local one" control here anymore (§
            // course-builder redesign, "один вход", 2026-09-01, confirmed
            // with the user): every NEW question, from here on, is created
            // through PoolQuestionsSection's own "+ Задание" below, so it's
            // reusable/connectable from the start rather than a dead-end
            // copy. "Сохранить вопросы" only matters while this list is
            // non-empty (existing rows to edit); an empty list has nothing
            // to wholesale-replace.
            for (var i = 0; i < _questions.length; i++)
              _QuestionCard(
                draft: _questions[i],
                index: i,
                total: _questions.length,
                onChanged: (d) => _replaceQuestion(i, d),
                onDelete: () => _removeQuestion(i),
                onMove: (delta) => _moveQuestion(i, delta),
              ),
            if (_questions.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  style: AdminButtonStyles.primary(),
                  child: Text(_busy ? 'Сохраняем…' : 'Сохранить вопросы'),
                ),
              ),
              const SizedBox(height: AdminMetrics.fieldGap),
            ],
            // § course-builder redesign, "единый список заданий", 2026-09-01
            // — continues the SAME numbered sequence as the static
            // _QuestionCard list above (no divider, no separate heading),
            // even though the two groups still save through their own real,
            // separate mechanisms underneath (§12: both must stay
            // functional) — this is the actual reusable pool, and now the
            // only place a NEW question gets created from.
            PoolQuestionsSection(
              lessonBlockId: widget.block.id,
              lessonId: widget.lessonId,
              numberOffset: _questions.length,
              showHeading: false,
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.draft,
    required this.index,
    required this.total,
    required this.onChanged,
    required this.onDelete,
    required this.onMove,
  });

  final QuestionDraft draft;
  final int index;
  final int total;
  final ValueChanged<QuestionDraft> onChanged;
  final VoidCallback onDelete;
  final void Function(int delta) onMove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AdminColors.blockBg,
        borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${index + 1}   ${questionKindLabel(draft)}',
                  style: AdminTypography.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // § course-builder redesign, "единый список заданий",
              // 2026-09-01 — this is a static LessonQuestion, not a real
              // QuestionPlacement, so it structurally can't have the pool
              // items' reuse-count/verifies chips; this neutral label is
              // what tells the two mechanisms apart now that they're
              // visually merged (§12: both must stay distinguishable).
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AdminColors.border)),
                child: Text('локально', style: AdminTypography.caption),
              ),
              const SizedBox(width: 6),
              AdminReorderArrows(
                canMoveUp: index > 0,
                canMoveDown: index < total - 1,
                onMove: onMove,
                size: 16,
              ),
              const SizedBox(width: 4),
              AdminDeleteLink(onPressed: onDelete),
            ],
          ),
          const SizedBox(height: 4),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) => switch (draft) {
    ChoiceDraft d => ChoiceEditor(draft: d, onChanged: onChanged),
    ClozeDraft d => ClozeEditorAdapter(draft: d, onChanged: onChanged),
    TrueFalseDraft d => TrueFalseEditor(draft: d, onChanged: onChanged),
    ScrambleDraft d => ScrambleEditor(draft: d, onChanged: onChanged),
    MatchDraft d => MatchEditor(draft: d, onChanged: onChanged),
    // Not reachable in practice (see _previewText above) - no button here
    // ever creates one - but still handled so this editor keeps working
    // unmodified if an auto_blank draft somehow ends up here.
    AutoBlankDraft d => AutoBlankEditor(draft: d, onChanged: onChanged),
  };
}

