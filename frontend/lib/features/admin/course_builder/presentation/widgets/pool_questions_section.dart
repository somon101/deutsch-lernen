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
///
/// Every question gets its own Topic, independent of the block it's created
/// in (§3 of the approved rule, 2026-08-27), and — only when placed in a
/// quiz stage — can optionally be tagged as "verifying" a specific
/// MaterialBlock (§4), purely a label with no effect on where it's shown.
class PoolQuestionsSection extends ConsumerStatefulWidget {
  const PoolQuestionsSection({super.key, this.materialBlockId, this.lessonBlockId, this.lessonId, this.topicId})
      : assert(materialBlockId != null || lessonBlockId != null, 'must scope to either a material or lesson block');

  final String? materialBlockId;
  final String? lessonBlockId;
  // Needed only to offer the "verifies which reading block" picker for a
  // lessonBlockId-scoped question — the lesson's own MaterialBlocks.
  final String? lessonId;
  final String? topicId;

  @override
  ConsumerState<PoolQuestionsSection> createState() => _PoolQuestionsSectionState();
}

class _PoolQuestionsSectionState extends ConsumerState<PoolQuestionsSection> {
  QuestionDraft? _draft;
  String? _draftTopicId;
  String? _draftVerifiesBlockId;
  bool _saving = false;
  List<PoolQuestion>? _attached;
  List<AdminTopic> _topics = [];
  List<AdminMaterialBlock> _verifyBlocks = [];

  bool get _showsVerifiesPicker => widget.lessonBlockId != null && widget.lessonId != null;

  @override
  void initState() {
    super.initState();
    _loadAttached();
    _loadTopics();
    if (_showsVerifiesPicker) _loadVerifyBlocks();
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

  Future<void> _loadTopics() async {
    try {
      final topics = await ref.read(builderRepositoryProvider).listTopics(languageId: 'de');
      if (mounted) setState(() => _topics = topics);
    } catch (_) {
      // Non-critical — the Topic picker just stays empty.
    }
  }

  Future<void> _loadVerifyBlocks() async {
    try {
      final repo = ref.read(builderRepositoryProvider);
      final materials = await repo.listMaterials(widget.lessonId!);
      final material = materials.where((m) => m.materialType == 'text').cast<AdminMaterial?>().firstWhere((m) => m != null, orElse: () => null);
      if (material == null) return;
      final blocks = await repo.listMaterialBlocks(material.id);
      if (mounted) setState(() => _verifyBlocks = blocks);
    } catch (_) {
      // Non-critical — the "verifies" picker just stays empty.
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

  void _startNew(QuestionDraft blank) => setState(() {
        _draft = blank;
        _draftTopicId = widget.topicId;
        _draftVerifiesBlockId = null;
      });

  Future<void> _submitDraft() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(builderRepositoryProvider);
      final similar = await repo.checkQuestionSimilarity(draft, topicId: _draftTopicId);
      if (similar.isNotEmpty && mounted) {
        final force = await _showSimilarityWarning(context, similar);
        if (!force) {
          if (mounted) setState(() => _saving = false);
          return;
        }
      }
      await repo.createPoolQuestion(
        draft,
        topicId: _draftTopicId,
        materialBlockId: widget.materialBlockId ?? _draftVerifiesBlockId,
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
              child: _AttachedQuestionTile(question: q, onUnlink: () => _unlink(q)),
            ),
        const SizedBox(height: 6),
        if (draft == null) ...[
          _PoolQuestionSearch(
            materialBlockId: widget.materialBlockId,
            lessonBlockId: widget.lessonBlockId,
            verifyBlocks: _showsVerifiesPicker ? _verifyBlocks : const [],
            onReused: _loadAttached,
          ),
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
                const SizedBox(height: AdminMetrics.fieldGap),
                DropdownButtonFormField<String?>(
                  initialValue: _draftTopicId,
                  isExpanded: true,
                  decoration: adminInputDecoration(label: 'Тема (Topic)'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Без темы')),
                    for (final topic in _topics) DropdownMenuItem<String?>(value: topic.id, child: Text(topic.name)),
                  ],
                  onChanged: (v) => setState(() => _draftTopicId = v),
                ),
                if (_showsVerifiesPicker) ...[
                  const SizedBox(height: AdminMetrics.fieldGap),
                  DropdownButtonFormField<String?>(
                    initialValue: _draftVerifiesBlockId,
                    isExpanded: true,
                    decoration: adminInputDecoration(label: 'Проверяет блок материала (необязательно)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Не привязывать')),
                      for (final b in _verifyBlocks) DropdownMenuItem<String?>(value: b.id, child: Text(b.title)),
                    ],
                    onChanged: (v) => setState(() => _draftVerifiesBlockId = v),
                  ),
                ],
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

/// One attached question, collapsed to a single-line summary by default —
/// expands to show the real content (prompt/options/correct answer, §8),
/// the resolved Topic, the "verifies" tag (if any), and the full "where
/// it's actually shown" chain (§5/§6/§7), fetched lazily on first expand.
class _AttachedQuestionTile extends ConsumerStatefulWidget {
  const _AttachedQuestionTile({required this.question, required this.onUnlink});
  final PoolQuestion question;
  final VoidCallback onUnlink;

  @override
  ConsumerState<_AttachedQuestionTile> createState() => _AttachedQuestionTileState();
}

class _AttachedQuestionTileState extends ConsumerState<_AttachedQuestionTile> {
  bool _open = false;
  List<QuestionUsage>? _usages;

  Future<void> _toggle() async {
    setState(() => _open = !_open);
    if (_open && _usages == null) {
      try {
        final usages = await ref.read(builderRepositoryProvider).listQuestionPlacements(widget.question.id);
        if (mounted) setState(() => _usages = usages);
      } catch (_) {
        // Non-critical — the chain just stays unresolved.
      }
    }
  }

  String _usageLine(QuestionUsage u) {
    final lesson = u.lessonTitle ?? '?';
    if (u.location == 'lessonBlock') return 'Урок «$lesson» → ${u.stageLabel ?? u.stage} → ${u.blockTitle}';
    if (u.location == 'material') return 'Урок «$lesson» → Материал → ${u.blockTitle}';
    return 'Урок «$lesson» (устаревший курс)';
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _toggle,
                  child: Text(
                    '${questionKindLabel(q.draft)}: ${poolQuestionPreviewText(q.draft)}',
                    style: AdminTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _toggle,
              ),
              AdminDeleteLink(label: 'Открепить', onPressed: widget.onUnlink),
            ],
          ),
          if (_open) ...[
            const Divider(height: 16, color: AdminColors.border),
            _ReadOnlyQuestionContent(draft: q.draft),
            const SizedBox(height: 8),
            Text('Тема: ${q.topicName ?? '—'}', style: AdminTypography.caption),
            if (q.verifiesBlockId != null) Text('Проверяет блок материала: ${q.verifiesBlockTitle}', style: AdminTypography.caption),
            const SizedBox(height: 8),
            Text('Где используется:', style: AdminTypography.fieldLabel),
            if (_usages == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator())
            else
              for (final u in _usages!) Text('• ${_usageLine(u)}', style: AdminTypography.caption),
          ],
        ],
      ),
    );
  }
}

/// Plain read-only rendering of a question's actual content — prompt,
/// options with the correct one marked, or statement+answer for
/// true/false — so a teacher can see what a question really says without
/// having to reuse it just to check (§8 of the approved rule).
class _ReadOnlyQuestionContent extends StatelessWidget {
  const _ReadOnlyQuestionContent({required this.draft});
  final QuestionDraft draft;

  @override
  Widget build(BuildContext context) {
    return switch (draft) {
      ChoiceDraft(:final prompt, :final options, :final correctIndex) || ClozeDraft(:final prompt, :final options, :final correctIndex) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(prompt, style: AdminTypography.body),
            const SizedBox(height: 4),
            for (var i = 0; i < options.length; i++)
              Text(
                i == correctIndex ? '✓ ${options[i]}' : '• ${options[i]}',
                style: i == correctIndex
                    ? AdminTypography.body.copyWith(color: const Color(0xFF16A34A), fontWeight: FontWeight.w600)
                    : AdminTypography.body,
              ),
          ],
        ),
      TrueFalseDraft(:final prompt, :final correct) => Text('$prompt — верно: ${correct ? 'да' : 'нет'}', style: AdminTypography.body),
      ScrambleDraft(:final translation, :final correctPhrase) =>
        Text('$translation → $correctPhrase', style: AdminTypography.body),
      MatchDraft(:final pairs) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final p in pairs) Text('${p.left} — ${p.right}', style: AdminTypography.body)],
        ),
    };
  }
}

class _PoolQuestionSearch extends ConsumerStatefulWidget {
  const _PoolQuestionSearch({this.materialBlockId, this.lessonBlockId, this.verifyBlocks = const [], required this.onReused});
  final String? materialBlockId;
  final String? lessonBlockId;
  final List<AdminMaterialBlock> verifyBlocks;
  final VoidCallback onReused;

  @override
  ConsumerState<_PoolQuestionSearch> createState() => _PoolQuestionSearchState();
}

class _PoolQuestionSearchState extends ConsumerState<_PoolQuestionSearch> {
  final _query = TextEditingController();
  List<PoolQuestion>? _results;
  String? _verifiesBlockId;

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
      await ref.read(builderRepositoryProvider).reusePoolQuestion(
            question.id,
            materialBlockId: widget.materialBlockId ?? _verifiesBlockId,
            lessonBlockId: widget.lessonBlockId,
          );
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
        if (widget.verifyBlocks.isNotEmpty) ...[
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: _verifiesBlockId,
            isExpanded: true,
            decoration: adminInputDecoration(label: 'При привязке — проверяет блок материала (необязательно)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Не привязывать')),
              for (final b in widget.verifyBlocks) DropdownMenuItem<String?>(value: b.id, child: Text(b.title)),
            ],
            onChanged: (v) => setState(() => _verifiesBlockId = v),
          ),
        ],
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
