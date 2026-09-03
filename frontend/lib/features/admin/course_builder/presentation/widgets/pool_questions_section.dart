import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/locale/content_locale.dart';
import '../../../../../core/locale/locale_provider.dart';
import '../../../../../core/theme/app_theme.dart';
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
      AutoBlankDraft(:final phrases) => phrases.isEmpty ? 'Пропущенное слово (авто)' : '${phrases.length} фраз: ${phrases.first}',
      AutoTranslateDraft(:final source, :final count) => 'Переведи слово: $count вопр. · ${source.label}',
      AutoMatchDraft(:final count) => 'Сопоставление (авто): $count вариантов',
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
  const PoolQuestionsSection({
    super.key,
    this.materialBlockId,
    this.lessonBlockId,
    this.lessonId,
    this.topicId,
    this.languageId,
    this.numberOffset = 0,
    this.showHeading = true,
  }) : assert(materialBlockId != null || lessonBlockId != null, 'must scope to either a material or lesson block');

  final String? materialBlockId;
  final String? lessonBlockId;
  // Needed only to offer the "verifies which reading block" picker for a
  // lessonBlockId-scoped question — the lesson's own MaterialBlocks.
  final String? lessonId;
  final String? topicId;
  // The course's real Language.id, for tagging a new pool question with a
  // Topic (§ topic-language fix, 2026-09-01) — null (no level/language
  // picked yet) just leaves the topic picker empty instead of querying a
  // bogus language.
  final String? languageId;
  // How many items already precede this list (§ course-builder redesign,
  // "единый список заданий" — a quiz block's static LessonQuestion items
  // are numbered first, this list continues the same sequence, 2026-09-01).
  // Zero (default) for the Материал stage's own checkpoint list, which
  // isn't numbered at all.
  final int numberOffset;
  // False merges this list into a caller's own numbered sequence with no
  // section break (the quiz-stage unified list) — true (default) keeps the
  // standalone "Вопросы из общего пула" heading for the Материал stage.
  final bool showHeading;

  @override
  ConsumerState<PoolQuestionsSection> createState() => _PoolQuestionsSectionState();
}

class _PoolQuestionsSectionState extends ConsumerState<PoolQuestionsSection> {
  QuestionDraft? _draft;
  String? _draftTopicId;
  String? _draftVerifiesBlockId;
  bool _saving = false;
  bool _searching = false;
  List<PoolQuestion>? _attached;
  List<AdminTopic> _topics = [];
  List<AdminMaterialBlock> _verifyBlocks = [];
  // How many distinct words each source can currently offer, for the
  // "Переведи слово" editor's ceiling hint (§ auto translate, 2026-09-02).
  // Advisory only — the server validates the count on save and applies the
  // real cap when generating.
  final Map<WordPoolSource, int> _poolSizes = {};

  // How the auto-match pool splits for this learner, for the editor's hint.
  ({int todayFree, int total})? _matchBreakdown;

  Future<void> _loadMatchBreakdown() async {
    final lessonId = widget.lessonId;
    if (lessonId == null || _matchBreakdown != null) return;
    try {
      final b = await ref.read(builderRepositoryProvider).matchPoolBreakdown(lessonId: lessonId);
      if (mounted) setState(() => _matchBreakdown = b);
    } catch (_) {
      // Non-critical — the editor falls back to its generic hint.
    }
  }

  Future<void> _loadPoolSize(WordPoolSource source) async {
    final lessonId = widget.lessonId;
    if (lessonId == null || _poolSizes.containsKey(source)) return;
    try {
      final size = await ref.read(builderRepositoryProvider).wordPoolSize(source: source.wire, lessonId: lessonId);
      if (mounted) setState(() => _poolSizes[source] = size);
    } catch (_) {
      // Non-critical — the editor just shows its generic hint instead.
    }
  }

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
    final languageId = widget.languageId;
    if (languageId == null) return;
    try {
      final topics = await ref.read(builderRepositoryProvider).listTopics(languageId: languageId);
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

  Future<void> _setVerifies(PoolQuestion q, String? blockId) async {
    final placementId = q.placementId;
    if (placementId == null) return;
    try {
      await ref.read(builderRepositoryProvider).setPlacementVerifiesBlock(placementId, blockId);
      await _loadAttached();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить привязку');
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

  void _startNew(QuestionDraft blank) {
    if (blank is AutoTranslateDraft) _loadPoolSize(blank.source);
    if (blank is AutoMatchDraft) _loadMatchBreakdown();
    setState(() {
        _draft = blank;
        _draftTopicId = widget.topicId;
        _draftVerifiesBlockId = null;
        _searching = false;
      });
  }

  /// "+ Задание" (§ course-builder redesign, "один вход", 2026-09-01) —
  /// always creates a pool question (confirmed with the user: going
  /// forward every NEW question is reusable/connectable; existing local
  /// LessonQuestion rows stay exactly as they are, edited in place through
  /// their own unchanged UI). Six types: five one-tap ones, and auto_blank
  /// set apart with its own longer explanation since it behaves
  /// differently and the teacher needs to know that BEFORE picking it, not
  /// after.
  Future<void> _pickType(BuildContext context) async {
    // Forces lightTheme (§ admin light-theme fix, 2026-09-01) —
    // showModalBottomSheet attaches to the Navigator's Overlay, outside any
    // ancestor `Theme(data: lightTheme, ...)` wrapper, so this sheet's
    // hardcoded AdminColors/AdminTypography text would otherwise pair with
    // whatever the app's actual ambient theme happens to be.
    final picked = await showModalBottomSheet<QuestionDraft Function()>(
      context: context,
      builder: (context) => Theme(
        data: lightTheme,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Новое задание', style: AdminTypography.cardTitle),
              ),
              _TypeRow(title: 'Выбор ответа', note: 'один правильный вариант', onTap: () => Navigator.of(context).pop(ChoiceDraft.blank)),
              _TypeRow(title: 'Верно / неверно', note: 'утверждение, да или нет', onTap: () => Navigator.of(context).pop(TrueFalseDraft.blank)),
              _TypeRow(title: 'Пропущенное слово', note: 'фраза с одним пропуском', onTap: () => Navigator.of(context).pop(ClozeDraft.blank)),
              _TypeRow(title: 'Собери фразу', note: 'слова вразброс', onTap: () => Navigator.of(context).pop(ScrambleDraft.blank)),
              _TypeRow(title: 'Сопоставление', note: 'пары слово → перевод', onTap: () => Navigator.of(context).pop(MatchDraft.blank)),
              const Divider(height: 20, color: AdminColors.border),
              _TypeRow(
                title: 'Пропущенное слово (авто)',
                note: 'пропуск и неверные варианты система подбирает сама, для каждого ученика свои',
                onTap: () => Navigator.of(context).pop(AutoBlankDraft.blank),
              ),
              _TypeRow(
                title: 'Переведи слово (авто)',
                note: 'слова берутся из выбранного источника, варианты система подбирает сама',
                onTap: () => Navigator.of(context).pop(AutoTranslateDraft.blank),
              ),
              _TypeRow(
                title: 'Сопоставление (авто)',
                note: 'пары подбираются сами: сначала слова, изученные сегодня',
                onTap: () => Navigator.of(context).pop(AutoMatchDraft.blank),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) _startNew(picked());
  }

  Future<void> _submitDraft() async {
    final draft = _draft;
    if (draft == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(builderRepositoryProvider);
      final similar = await repo.checkQuestionSimilarity(draft, topicId: _draftTopicId);
      if (similar.isNotEmpty && mounted) {
        final action = await _showSimilarityWarning(context, similar);
        if (action == null) {
          if (mounted) setState(() => _saving = false);
          return;
        }
        if (action is SimilarQuestionMatch) {
          await repo.reusePoolQuestion(
            action.question.id,
            materialBlockId: widget.materialBlockId ?? _draftVerifiesBlockId,
            lessonBlockId: widget.lessonBlockId,
          );
          if (mounted) {
            showSuccessSnack(context, 'Вопрос привязан (без копирования)');
            setState(() => _draft = null);
          }
          await _loadAttached();
          if (mounted) setState(() => _saving = false);
          return;
        }
        // action == true — "Всё равно создать новое", fall through below.
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

  /// Returns `true` ("Всё равно создать новое"), a [SimilarQuestionMatch]
  /// (tapped a row — attach that one instead), or `null` (dismissed) — §
  /// course-builder redesign, "Похоже на существующее задание", 2026-09-01:
  /// attaching an existing match is now the primary, one-tap action, not
  /// buried behind a plain "cancel".
  Future<Object?> _showSimilarityWarning(BuildContext context, List<SimilarQuestionMatch> similar) {
    // Forces lightTheme, same reason as _pickType above.
    return showDialog<Object?>(
      context: context,
      builder: (context) => Theme(
        data: lightTheme,
        child: AlertDialog(
        title: const Text('Похоже на существующее задание'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final match in similar)
                InkWell(
                  onTap: () => Navigator.of(context).pop(match),
                  borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('«${poolQuestionPreviewText(match.question.draft)}» — сходство ${match.score}%', style: AdminTypography.body),
                        if (match.location != null) ...[
                          const SizedBox(height: 2),
                          Text(match.location!, style: AdminTypography.caption),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
              Text('Нажмите на задание, чтобы привязать его вместо создания нового.', style: AdminTypography.caption),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: AdminButtonStyles.text(),
            child: const Text('Всё равно создать новое'),
          ),
        ],
        ),
      ),
    );
  }

  Widget _draftEditor(QuestionDraft draft) => switch (draft) {
        ChoiceDraft d => ChoiceEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        ClozeDraft d => ClozeEditorAdapter(draft: d, onChanged: (v) => setState(() => _draft = v)),
        TrueFalseDraft d => TrueFalseEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        ScrambleDraft d => ScrambleEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        MatchDraft d => MatchEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        AutoBlankDraft d => AutoBlankEditor(draft: d, onChanged: (v) => setState(() => _draft = v)),
        AutoMatchDraft d => AutoMatchEditor(draft: d, breakdown: _matchBreakdown, onChanged: (v) => setState(() => _draft = v)),
        AutoTranslateDraft d => AutoTranslateEditor(
            draft: d,
            poolSize: _poolSizes[d.source],
            onChanged: (v) {
              setState(() => _draft = v);
              if (v is AutoTranslateDraft) _loadPoolSize(v.source);
            },
          ),
      };

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final attached = _attached;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading) ...[
          Text('Вопросы из общего пула', style: AdminTypography.fieldLabel),
          const SizedBox(height: 6),
        ],
        if (attached == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else if (attached.isEmpty && widget.showHeading)
          Text('К этому блоку пока не привязано ни одного вопроса.', style: AdminTypography.caption)
        else
          for (var i = 0; i < attached.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _AttachedQuestionTile(
                question: attached[i],
                number: widget.numberOffset + i + 1,
                showNumber: !widget.showHeading,
                onUnlink: () => _unlink(attached[i]),
                verifyBlocks: _showsVerifiesPicker ? _verifyBlocks : const [],
                onVerifiesChanged: _showsVerifiesPicker ? (blockId) => _setVerifies(attached[i], blockId) : null,
              ),
            ),
        const SizedBox(height: 6),
        if (draft == null) ...[
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => _pickType(context),
                style: AdminButtonStyles.secondary(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Задание'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => setState(() => _searching = !_searching),
                style: AdminButtonStyles.text(),
                icon: const Icon(Icons.north_east, size: 15),
                label: const Text('Найти существующее'),
              ),
            ],
          ),
          if (_searching) ...[
            const SizedBox(height: 6),
            _PoolQuestionSearch(
              materialBlockId: widget.materialBlockId,
              lessonBlockId: widget.lessonBlockId,
              verifyBlocks: _showsVerifiesPicker ? _verifyBlocks : const [],
              onReused: _loadAttached,
            ),
          ],
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
  const _AttachedQuestionTile({
    required this.question,
    required this.onUnlink,
    this.number,
    this.showNumber = false,
    this.verifyBlocks = const [],
    this.onVerifiesChanged,
  });
  final PoolQuestion question;
  final VoidCallback onUnlink;
  // § course-builder redesign, "единый список заданий", 2026-09-01 — the
  // quiz-stage editor merges this list into one continuously-numbered
  // sequence with its own static questions; the Материал stage's own
  // checkpoint list stays unnumbered (showNumber false, the default).
  final int? number;
  final bool showNumber;
  // Only non-empty for a lessonBlockId-scoped listing (quiz stages) — the
  // lesson's own MaterialBlocks, to offer as "verifies" chip choices.
  final List<AdminMaterialBlock> verifyBlocks;
  // Null when this tile is a Материал-stage's own inline question (no
  // "verifies" concept applies there — a material block can't verify
  // itself). Non-null (even if verifyBlocks is momentarily still loading)
  // is what makes the chip render at all.
  final ValueChanged<String?>? onVerifiesChanged;

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

  Future<void> _pickVerifies(BuildContext context) async {
    final onChanged = widget.onVerifiesChanged;
    if (onChanged == null) return;
    // Forces lightTheme, same reason as _pickType above.
    final picked = await showModalBottomSheet<Object?>(
      context: context,
      builder: (context) => Theme(
        data: lightTheme,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('Проверяет блок материала', style: AdminTypography.cardTitle),
              ),
              ListTile(
                dense: true,
                title: Text('Не привязывать', style: AdminTypography.body),
                onTap: () => Navigator.of(context).pop(const _ClearVerifies()),
              ),
              for (final b in widget.verifyBlocks)
                ListTile(dense: true, title: Text(b.title, style: AdminTypography.body), onTap: () => Navigator.of(context).pop(b.id)),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return; // dismissed without choosing
    onChanged(picked is _ClearVerifies ? null : picked as String);
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final showsChip = widget.onVerifiesChanged != null;
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
                    widget.showNumber && widget.number != null
                        ? '${widget.number}   ${questionKindLabel(q.draft)}'
                        : '${questionKindLabel(q.draft)}: ${poolQuestionPreviewText(q.draft)}',
                    style: AdminTypography.body,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              _UsageCountChip(count: q.placementCount),
              const SizedBox(width: 6),
              if (showsChip) ...[
                _VerifiesChip(title: q.verifiesBlockTitle, onTap: () => _pickVerifies(context)),
                const SizedBox(width: 6),
              ],
              IconButton(
                icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: _toggle,
              ),
              AdminDeleteLink(label: 'Открепить', onPressed: widget.onUnlink),
            ],
          ),
          if (widget.showNumber) ...[
            const SizedBox(height: 2),
            Text(
              '«${poolQuestionPreviewText(q.draft)}»',
              style: AdminTypography.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (_open) ...[
            const Divider(height: 16, color: AdminColors.border),
            _ReadOnlyQuestionContent(draft: q.draft),
            const SizedBox(height: 8),
            Text('Тема: ${q.topicName ?? '—'}', style: AdminTypography.caption),
            const SizedBox(height: 8),
            Text('Где используется:', style: AdminTypography.fieldLabel),
            if (_usages == null)
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator())
            else
              for (final u in _usages!) Text('• ${_usageLine(u)}', style: AdminTypography.caption),
            const SizedBox(height: 8),
            _QuestionTranslationsSection(questionId: q.id, draft: q.draft),
          ],
        ],
      ),
    );
  }
}

/// Which text fields are worth translating for a given question kind (§
/// course content language, 2026-09-04) — auto_blank/auto_translate/
/// auto_match generate their content from vocabulary at serve time (see
/// backend material.py's to_question_dtos comment) and have nothing
/// authored here to translate; match's pairs aren't supported by this
/// generic editor yet (scope note in _QuestionTranslationsSection).
enum _TranslatableFields { promptOptionsAnswer, promptOnly, none }

_TranslatableFields _translatableFieldsFor(QuestionDraft d) => switch (d) {
      ChoiceDraft() || ClozeDraft() || ScrambleDraft() => _TranslatableFields.promptOptionsAnswer,
      TrueFalseDraft() || MatchDraft() => _TranslatableFields.promptOnly,
      AutoBlankDraft() || AutoTranslateDraft() || AutoMatchDraft() => _TranslatableFields.none,
    };

/// Locale-toggle translation editor for one pool Question (§ course content
/// language, 2026-09-04, spec §5) — same pattern as
/// _CourseTranslationsSection/_MaterialBlockTranslationsSection, but the
/// fields shown depend on the question's own kind (see
/// _translatableFieldsFor), and match's pairs / auto-generated kinds are
/// out of scope for this generic editor (not enough shared shape to justify
/// one more structured per-kind form on top of the 8 the question authoring
/// UI already has).
class _QuestionTranslationsSection extends ConsumerStatefulWidget {
  const _QuestionTranslationsSection({required this.questionId, required this.draft});
  final String questionId;
  final QuestionDraft draft;

  @override
  ConsumerState<_QuestionTranslationsSection> createState() => _QuestionTranslationsSectionState();
}

class _QuestionTranslationsSectionState extends ConsumerState<_QuestionTranslationsSection> {
  Map<String, QuestionTranslationFields>? _translations;
  String _locale = supportedContentLocales.first;
  final _prompt = TextEditingController();
  final _options = TextEditingController();
  final _correctAnswer = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final translations = await ref.read(builderRepositoryProvider).getQuestionTranslations(widget.questionId);
      if (!mounted) return;
      setState(() {
        _translations = translations;
        _fillFrom(translations[_locale]);
      });
    } catch (_) {
      if (mounted) setState(() => _translations = {});
    }
  }

  void _fillFrom(QuestionTranslationFields? t) {
    _prompt.text = t?.prompt ?? '';
    _options.text = (t?.options ?? const []).join('\n');
    _correctAnswer.text = t?.correctAnswer ?? '';
  }

  void _switchLocale(String locale) {
    setState(() {
      _locale = locale;
      _fillFrom(_translations?[locale]);
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final fields = _translatableFieldsFor(widget.draft);
      final translations = await ref.read(builderRepositoryProvider).setQuestionTranslation(
            widget.questionId,
            _locale,
            prompt: _prompt.text.trim().isEmpty ? null : _prompt.text.trim(),
            options: fields == _TranslatableFields.promptOptionsAnswer
                ? _options.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
                : null,
            correctAnswer: _correctAnswer.text.trim().isEmpty ? null : _correctAnswer.text.trim(),
          );
      if (mounted) setState(() => _translations = translations);
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить перевод');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _options.dispose();
    _correctAnswer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = _translatableFieldsFor(widget.draft);
    if (fields == _TranslatableFields.none) {
      return Text(
        'Для этого типа задания перевод не нужен — содержимое подбирается автоматически по словарю.',
        style: AdminTypography.caption,
      );
    }
    if (_translations == null) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: LinearProgressIndicator());
    }
    final translations = _translations!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdminColors.card, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius), border: Border.all(color: AdminColors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Языковые версии задания', style: AdminTypography.fieldLabel),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final locale in supportedContentLocales)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${localeDisplayName(Locale(locale))}${translations.containsKey(locale) ? '' : ' — нет перевода'}'),
                    selected: _locale == locale,
                    onSelected: (_) => _switchLocale(locale),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _prompt, decoration: adminInputDecoration(label: 'Текст вопроса / условие')),
          if (fields == _TranslatableFields.promptOptionsAnswer) ...[
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: _options, maxLines: 4, decoration: adminInputDecoration(label: 'Варианты (по одному на строку)')),
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: _correctAnswer, decoration: adminInputDecoration(label: 'Правильный ответ')),
          ],
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: AdminButtonStyles.primary(),
              child: Text('Сохранить перевод (${localeDisplayName(Locale(_locale))})'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row in the "+ Задание" type-picker sheet (§ course-builder redesign,
/// "лист выбора типа", 2026-09-01) — name plus one explanatory phrase, no
/// icons or badges (§ redesign principle: badges everywhere turn a list
/// into a card wall).
class _TypeRow extends StatelessWidget {
  const _TypeRow({required this.title, required this.note, required this.onTap});
  final String title;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AdminTypography.body.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(note, style: AdminTypography.caption),
          ],
        ),
      ),
    );
  }
}

/// Sentinel distinguishing "explicitly chose Не привязывать" from "dismissed
/// the sheet without picking anything" — both close the sheet with `pop`,
/// but only the former should actually call [onVerifiesChanged].
class _ClearVerifies {
  const _ClearVerifies();
}

/// Reusability at a glance (§ course-builder redesign, "в пуле · N мест"
/// chip, 2026-09-01) — neutral (this isn't a connectivity indicator, it's
/// just a count), always visible so the teacher doesn't have to expand a
/// row to learn whether editing it here would affect other lessons too.
class _UsageCountChip extends StatelessWidget {
  const _UsageCountChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AdminColors.border)),
      child: Text(
        count > 1 ? 'в пуле · $count мест' : 'только здесь',
        style: AdminTypography.caption,
      ),
    );
  }
}

/// The one connectivity indicator in the whole admin family (§2/§10 of the
/// course-builder redesign, 2026-09-01) — the accent color is reserved
/// exclusively for this. A resolved link renders as a small accent-outlined
/// pill with the block's title; no link yet renders as a muted "+
/// привязать" in the same spot, so the affordance never moves around.
class _VerifiesChip extends StatelessWidget {
  const _VerifiesChip({required this.title, required this.onTap});
  final String? title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final linked = title != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        constraints: const BoxConstraints(maxWidth: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: linked ? AdminColors.accent : AdminColors.border),
          color: linked ? AdminColors.accentSoft : Colors.transparent,
        ),
        child: Text(
          linked ? title! : '+ привязать',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AdminTypography.caption.copyWith(
            color: linked ? AdminColors.accent : AdminColors.textMuted,
            fontWeight: linked ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
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
                    ? AdminTypography.body.copyWith(color: AdminColors.success, fontWeight: FontWeight.w600)
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
      AutoBlankDraft(:final phrases) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [for (final p in phrases) Text('• $p', style: AdminTypography.body)],
        ),
      AutoTranslateDraft(:final source, :final count) =>
        Text('$count вопр. · ${source.label}', style: AdminTypography.body),
      AutoMatchDraft(:final count) => Text('$count вариантов', style: AdminTypography.body),
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
