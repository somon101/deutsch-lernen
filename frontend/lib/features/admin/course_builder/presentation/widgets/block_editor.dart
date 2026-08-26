import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/admin_feedback.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../data/builder_repository.dart';
import '../../domain/block_question.dart';
import '../../domain/builder_domain.dart';
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
  late List<QuestionDraft> _questions = List.of(widget.block.questions);
  late final _titleController = TextEditingController(text: widget.block.title);
  bool _busy = false;

  @override
  void didUpdateWidget(covariant BlockEditor old) {
    super.didUpdateWidget(old);
    if (old.block.id != widget.block.id) {
      _questions = List.of(widget.block.questions);
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

  void _addQuestion(QuestionDraft Function() blank) =>
      setState(() => _questions = [..._questions, blank()]);
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
            for (var i = 0; i < _questions.length; i++)
              _QuestionCard(
                draft: _questions[i],
                index: i,
                total: _questions.length,
                onChanged: (d) => _replaceQuestion(i, d),
                onDelete: () => _removeQuestion(i),
                onMove: (delta) => _moveQuestion(i, delta),
              ),
            _QuestionLibrarySearch(onPick: (d) => _addQuestion(() => d)),
            const SizedBox(height: AdminMetrics.fieldGap),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _addQuestion(ChoiceDraft.blank),
                  style: AdminButtonStyles.secondary(),
                  child: const Text('Вопрос с вариантами'),
                ),
                OutlinedButton(
                  onPressed: () => _addQuestion(TrueFalseDraft.blank),
                  style: AdminButtonStyles.secondary(),
                  child: const Text('Верно / Неверно'),
                ),
                OutlinedButton(
                  onPressed: () => _addQuestion(ClozeDraft.blank),
                  style: AdminButtonStyles.secondary(),
                  child: const Text('Пропущенное слово'),
                ),
                OutlinedButton(
                  onPressed: () => _addQuestion(ScrambleDraft.blank),
                  style: AdminButtonStyles.secondary(),
                  child: const Text('Собери фразу'),
                ),
                OutlinedButton(
                  onPressed: () => _addQuestion(MatchDraft.blank),
                  style: AdminButtonStyles.secondary(),
                  child: const Text('Сопоставление'),
                ),
              ],
            ),
            const SizedBox(height: AdminMetrics.cardGap),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: AdminButtonStyles.primary(),
                child: Text(_busy ? 'Сохраняем…' : 'Сохранить вопросы'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionLibrarySearch extends ConsumerStatefulWidget {
  const _QuestionLibrarySearch({required this.onPick});
  final void Function(QuestionDraft) onPick;

  @override
  ConsumerState<_QuestionLibrarySearch> createState() =>
      _QuestionLibrarySearchState();
}

class _QuestionLibrarySearchState
    extends ConsumerState<_QuestionLibrarySearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<QuestionDraft>? _results;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref
          .read(builderRepositoryProvider)
          .searchQuestions(value.trim());
      if (mounted) setState(() => _results = results);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _query,
          decoration: adminInputDecoration(
            label: 'Найти готовое задание в других уроках',
          ),
          onChanged: _onChanged,
        ),
        if (_results != null && _results!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
            ),
            child: Column(
              children: [
                for (final r in _results!)
                  ListTile(
                    dense: true,
                    title: Text(_previewText(r), style: AdminTypography.body),
                    subtitle: Text(
                      questionKindLabel(r),
                      style: AdminTypography.caption,
                    ),
                    onTap: () {
                      widget.onPick(r);
                      setState(() {
                        _results = null;
                        _query.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _previewText(QuestionDraft d) => switch (d) {
    ChoiceDraft(:final prompt) => prompt,
    TrueFalseDraft(:final prompt) => prompt,
    ClozeDraft(:final prompt) => prompt,
    ScrambleDraft(:final translation) => translation,
    MatchDraft(:final prompt) => prompt.isEmpty ? 'Сопоставление' : prompt,
  };
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
                  'Задание ${index + 1} · ${questionKindLabel(draft)}',
                  style: AdminTypography.fieldLabel.copyWith(
                    color: AdminColors.text,
                  ),
                ),
              ),
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
  };
}

