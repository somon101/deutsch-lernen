import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/block_question.dart';
import '../../domain/taxonomy_domain.dart';
import 'question_kind_editors.dart';

String poolQuestionPreviewText(QuestionDraft d) => switch (d) {
      ChoiceDraft(:final prompt) => prompt,
      TrueFalseDraft(:final prompt) => prompt,
      ClozeDraft(:final prompt) => prompt,
      ScrambleDraft(:final translation) => translation,
      MatchDraft(:final prompt) => prompt.isEmpty ? 'Сопоставление' : prompt,
    };

/// Reusable-question management for one block — shows what's already
/// attached, lets the teacher create a brand-new question (with an
/// automatic similarity warning, §29/§30) or search the existing pool and
/// attach one by reference (§16/§17/§31) instead of copying it. Shared
/// between the "Материал" stage's block editor (pass [materialBlockId]) and
/// the quiz-block editor for minitest/practice/review (pass
/// [lessonBlockId]) — same reusable-pool mechanism either way, exactly one
/// of the two ids must be given.
class PoolQuestionsSection extends ConsumerStatefulWidget {
  const PoolQuestionsSection({super.key, this.materialBlockId, this.lessonBlockId, this.topicId})
      : assert(materialBlockId != null || lessonBlockId != null, 'must scope to either a material or lesson block');

  final String? materialBlockId;
  final String? lessonBlockId;
  final String? topicId;

  @override
  ConsumerState<PoolQuestionsSection> createState() => _PoolQuestionsSectionState();
}

class _PoolQuestionsSectionState extends ConsumerState<PoolQuestionsSection> {
  QuestionDraft? _draft;
  bool _saving = false;
  List<PoolQuestion>? _attached;

  @override
  void initState() {
    super.initState();
    _loadAttached();
  }

  Future<void> _loadAttached() async {
    try {
      final attached = await ref
          .read(builderRepositoryProvider)
          .listBlockQuestions(materialBlockId: widget.materialBlockId, lessonBlockId: widget.lessonBlockId);
      if (mounted) setState(() => _attached = attached);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить вопросы блока');
    }
  }

  Future<void> _unlink(PoolQuestion q) async {
    final placementId = q.placementId;
    if (placementId == null) return;
    final ok = await confirmDialog(context, title: 'Открепить вопрос от блока?', confirmLabel: 'Открепить');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).removePlacement(placementId);
      if (mounted) setState(() => _attached = _attached?.where((a) => a.placementId != placementId).toList());
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось открепить вопрос');
    }
  }

  void _startNew(QuestionDraft blank) => setState(() => _draft = blank);

  Future<void> _submitDraft() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(builderRepositoryProvider);
      final similar = await repo.checkQuestionSimilarity(draft, topicId: widget.topicId);
      if (similar.isNotEmpty && mounted) {
        final force = await _showSimilarityWarning(context, similar);
        if (!force) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      await repo.createPoolQuestion(
        draft,
        topicId: widget.topicId,
        materialBlockId: widget.materialBlockId,
        lessonBlockId: widget.lessonBlockId,
        force: true,
      );
      if (mounted) {
        showSuccessSnack(context, 'Вопрос добавлен');
        setState(() => _draft = null);
      }
      await _loadAttached();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось добавить вопрос');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _showSimilarityWarning(BuildContext context, List<SimilarQuestionMatch> similar) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ Найден похожий вопрос'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final match in similar)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('«${poolQuestionPreviewText(match.question.draft)}» — сходство ${match.score}%', style: AdminTypography.body),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Создать новый')),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _draftEditor(QuestionDraft draft) => switch (draft) {
        ChoiceDraft d => ChoiceEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        ClozeDraft d => ClozeEditorAdapter(draft: d, onChanged: (v) => setState(() => _draft = v)),
        TrueFalseDraft d => TrueFalseEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        ScrambleDraft d => ScrambleEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        MatchDraft d => MatchEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
      };

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final attached = _attached;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Вопросы из общего пула', style: AdminTypography.fieldLabel),
        const SizedBox(height: 6),
        if (attached == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else if (attached.isEmpty)
          const Text('К этому блоку пока не привязано ни одного вопроса.', style: AdminTypography.caption)
        else
          for (final q in attached)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${questionKindLabel(q.draft)}: ${poolQuestionPreviewText(q.draft)}',
                        style: AdminTypography.body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    AdminDeleteLink(label: 'Открепить', onPressed: () => _unlink(q)),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 6),
        if (draft == null) ...[
          _PoolQuestionSearch(materialBlockId: widget.materialBlockId, lessonBlockId: widget.lessonBlockId, onReused: _loadAttached),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: () => _startNew(ChoiceDraft.blank()), style: AdminButtonStyles.secondary(), child: const Text('Вопрос с вариантами')),
              OutlinedButton(onPressed: () => _startNew(TrueFalseDraft.blank()), style: AdminButtonStyles.secondary(), child: const Text('Верно / Неверно')),
              OutlinedButton(onPressed: () => _startNew(ClozeDraft.blank()), style: AdminButtonStyles.secondary(), child: const Text('Пропущенное слово')),
              OutlinedButton(onPressed: () => _startNew(ScrambleDraft.blank()), style: AdminButtonStyles.secondary(), child: const Text('Собери фразу')),
              OutlinedButton(onPressed: () => _startNew(MatchDraft.blank()), style: AdminButtonStyles.secondary(), child: const Text('Сопоставление')),
            ],
          ),
        ] else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _draftEditor(draft),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => setState(() => _draft = null),
                      style: AdminButtonStyles.text(),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : _submitDraft,
                      style: AdminButtonStyles.primary(),
                      child: Text(_saving ? 'Сохраняем…' : 'Добавить вопрос'),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PoolQuestionSearch extends ConsumerStatefulWidget {
  const _PoolQuestionSearch({this.materialBlockId, this.lessonBlockId, required this.onReused});
  final String? materialBlockId;
  final String? lessonBlockId;
  final VoidCallback onReused;

  @override
  ConsumerState<_PoolQuestionSearch> createState() => _PoolQuestionSearchState();
}

class _PoolQuestionSearchState extends ConsumerState<_PoolQuestionSearch> {
  final _query = TextEditingController();
  List<PoolQuestion>? _results;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String value) async {
    if (value.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    final results = await ref.read(builderRepositoryProvider).searchQuestionPool(query: value.trim());
    if (mounted) setState(() => _results = results);
  }

  Future<void> _reuse(PoolQuestion question) async {
    try {
      await ref
          .read(builderRepositoryProvider)
          .reusePoolQuestion(question.id, materialBlockId: widget.materialBlockId, lessonBlockId: widget.lessonBlockId);
      if (mounted) {
        showSuccessSnack(context, 'Вопрос привязан (без копирования)');
        setState(() {
          _results = null;
          _query.clear();
        });
      }
      widget.onReused();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось привязать вопрос');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _query, decoration: adminInputDecoration(label: 'Найти существующий вопрос для переиспользования'), onChanged: _search),
        if (_results != null && _results!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(border: Border.all(color: AdminColors.border), borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
            child: Column(
              children: [
                for (final q in _results!)
                  ListTile(
                    dense: true,
                    title: Text(poolQuestionPreviewText(q.draft), style: AdminTypography.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(onPressed: () => _reuse(q), style: AdminButtonStyles.text(), child: const Text('Привязать')),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
