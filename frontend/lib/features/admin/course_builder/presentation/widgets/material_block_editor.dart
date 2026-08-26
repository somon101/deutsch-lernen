import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/block_question.dart';
import '../../domain/taxonomy_domain.dart';
import 'question_kind_editors.dart';

/// Replaces the old single-textarea material editor with real, addressable
/// blocks (§6-9 of the content-taxonomy plan): each block has its own
/// title+content, can be added/removed/reordered by drag-and-drop, and can
/// carry its own reusable questions. One lesson currently gets one "text"
/// Material (auto-created on first open) — the schema supports several, but
/// the UI only needs one for now.
class MaterialBlockEditor extends ConsumerStatefulWidget {
  const MaterialBlockEditor({super.key, required this.courseId, required this.lessonId, required this.lessonTitle});

  final String courseId;
  final String lessonId;
  final String lessonTitle;

  @override
  ConsumerState<MaterialBlockEditor> createState() => _MaterialBlockEditorState();
}

class _MaterialBlockEditorState extends ConsumerState<MaterialBlockEditor> {
  AdminMaterial? _material;
  List<AdminMaterialBlock> _blocks = [];
  List<AdminTopic> _topics = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final repo = ref.read(builderRepositoryProvider);
    final materials = await repo.listMaterials(widget.lessonId);
    var material = materials.where((m) => m.materialType == 'text').cast<AdminMaterial?>().firstWhere((m) => m != null, orElse: () => null);
    material ??= await repo.createMaterial(courseId: widget.courseId, lessonId: widget.lessonId, materialType: 'text', title: widget.lessonTitle);
    final blocks = await repo.listMaterialBlocks(material.id);
    final topics = await repo.listTopics(languageId: 'de');
    if (mounted) {
      setState(() {
        _material = material;
        _blocks = blocks;
        _topics = topics;
        _loading = false;
      });
    }
  }

  Future<void> _addBlock() async {
    final material = _material;
    if (material == null) return;
    try {
      final block = await ref.read(builderRepositoryProvider).addMaterialBlock(material.id, title: 'Новый блок', content: '');
      setState(() => _blocks = [..._blocks, block]);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось добавить блок');
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final material = _material;
    if (material == null) return;
    setState(() {
      final item = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, item);
    });
    try {
      await ref.read(builderRepositoryProvider).reorderMaterialBlocks(material.id, _blocks.map((b) => b.id).toList());
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить порядок блоков');
    }
  }

  Future<void> _deleteBlock(AdminMaterialBlock block) async {
    final ok = await confirmDialog(context, title: 'Удалить блок «${block.title}»?');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteMaterialBlock(block.id);
      setState(() => _blocks.removeWhere((b) => b.id == block.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить блок');
    }
  }

  Future<void> _onTopicChanged(String? topicId) async {
    final material = _material;
    if (material == null) return;
    try {
      final updated = await ref.read(builderRepositoryProvider).updateMaterial(material.id, topicId: topicId);
      setState(() => _material = updated);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось привязать тему');
    }
  }

  Future<void> _createTopic(String name) async {
    try {
      final (topic, existing) = await ref.read(builderRepositoryProvider).createTopic('de', name);
      setState(() => _topics = _topics.any((t) => t.id == topic.id) ? _topics : [..._topics, topic]);
      await _onTopicChanged(topic.id);
      if (mounted && existing) showSuccessSnack(context, 'Использована существующая тема «${topic.name}»');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось создать тему');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    final material = _material!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TopicPicker(topics: _topics, selectedTopicId: material.topicId, onChanged: _onTopicChanged, onCreate: _createTopic),
        const SizedBox(height: AdminMetrics.cardGap),
        if (_blocks.isEmpty) const Text('Блоков пока нет — добавьте первый ниже.', style: AdminTypography.caption),
        ReorderableListView.builder(
          buildDefaultDragHandles: false,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _blocks.length,
          onReorderItem: _reorder,
          itemBuilder: (context, index) => _MaterialBlockCard(
            key: ValueKey(_blocks[index].id),
            index: index,
            block: _blocks[index],
            topicId: material.topicId,
            onDeleted: () => _deleteBlock(_blocks[index]),
            onSaved: (updated) => setState(() => _blocks[index] = updated),
          ),
        ),
        const SizedBox(height: AdminMetrics.fieldGap),
        AddRowButton(label: '+ Добавить блок', onPressed: _addBlock),
      ],
    );
  }
}

class _TopicPicker extends StatelessWidget {
  const _TopicPicker({required this.topics, required this.selectedTopicId, required this.onChanged, required this.onCreate});

  final List<AdminTopic> topics;
  final String? selectedTopicId;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String?>(
            initialValue: selectedTopicId,
            isExpanded: true,
            decoration: adminInputDecoration(label: 'Тема (Topic)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Без темы')),
              for (final topic in topics) DropdownMenuItem<String?>(value: topic.id, child: Text(topic.name)),
            ],
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 8),
        TextButton(onPressed: () => _promptNewTopic(context), style: AdminButtonStyles.text(), child: const Text('+ Новая тема')),
      ],
    );
  }

  Future<void> _promptNewTopic(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Новая тема'),
        content: TextField(controller: controller, decoration: adminInputDecoration(label: 'Название темы', hint: 'Präteritum')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Создать')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) onCreate(name);
  }
}

class _MaterialBlockCard extends ConsumerStatefulWidget {
  const _MaterialBlockCard({super.key, required this.index, required this.block, required this.topicId, required this.onDeleted, required this.onSaved});

  final int index;
  final AdminMaterialBlock block;
  final String? topicId;
  final VoidCallback onDeleted;
  final ValueChanged<AdminMaterialBlock> onSaved;

  @override
  ConsumerState<_MaterialBlockCard> createState() => _MaterialBlockCardState();
}

class _MaterialBlockCardState extends ConsumerState<_MaterialBlockCard> {
  late final _title = TextEditingController(text: widget.block.title);
  late final _content = TextEditingController(text: widget.block.content);
  bool _busy = false;
  bool _open = false;

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final updated = await ref
          .read(builderRepositoryProvider)
          .updateMaterialBlock(widget.block.id, title: _title.text.trim(), content: _content.text);
      widget.onSaved(updated);
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить блок');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        padding: const EdgeInsets.all(12),
        highlighted: _open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(index: widget.index, child: const Icon(Icons.drag_indicator, color: AdminColors.textMuted, size: 20)),
                const SizedBox(width: 8),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Text(widget.block.title, style: AdminTypography.stageTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
                IconButton(
                  icon: Icon(_open ? Icons.expand_less : Icons.expand_more, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _open = !_open),
                ),
                AdminDeleteLink(onPressed: widget.onDeleted),
              ],
            ),
            if (_open) ...[
              const Divider(height: 20, color: AdminColors.border),
              TextField(controller: _title, decoration: adminInputDecoration(label: 'Название блока')),
              const SizedBox(height: AdminMetrics.fieldGap),
              TextField(controller: _content, maxLines: 6, decoration: adminInputDecoration(label: 'Содержимое')),
              const SizedBox(height: AdminMetrics.fieldGap),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(onPressed: _busy ? null : _save, style: AdminButtonStyles.primary(), child: Text(_busy ? 'Сохраняем…' : 'Сохранить')),
              ),
              const SizedBox(height: AdminMetrics.cardGap),
              _BlockQuestions(materialBlockId: widget.block.id, topicId: widget.topicId),
            ],
          ],
        ),
      ),
    );
  }
}

/// Reusable-question management for one MaterialBlock: shows what's already
/// attached, lets the teacher create a brand-new question (with an
/// automatic similarity warning, §29/§30) or search the existing pool and
/// attach one by reference (§16/§17/§31) instead of copying it.
class _BlockQuestions extends ConsumerStatefulWidget {
  const _BlockQuestions({required this.materialBlockId, required this.topicId});
  final String materialBlockId;
  final String? topicId;

  @override
  ConsumerState<_BlockQuestions> createState() => _BlockQuestionsState();
}

class _BlockQuestionsState extends ConsumerState<_BlockQuestions> {
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
      final attached = await ref.read(builderRepositoryProvider).listBlockQuestions(widget.materialBlockId);
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
      await repo.createPoolQuestion(draft, topicId: widget.topicId, materialBlockId: widget.materialBlockId, force: true);
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
                  child: Text('«${_previewText(match.question.draft)}» — сходство ${match.score}%', style: AdminTypography.body),
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

  String _previewText(QuestionDraft d) => switch (d) {
        ChoiceDraft(:final prompt) => prompt,
        TrueFalseDraft(:final prompt) => prompt,
        ClozeDraft(:final prompt) => prompt,
        ScrambleDraft(:final translation) => translation,
        MatchDraft(:final prompt) => prompt.isEmpty ? 'Сопоставление' : prompt,
      };

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
        Text('Вопросы блока', style: AdminTypography.fieldLabel),
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
                        '${questionKindLabel(q.draft)}: ${_previewText(q.draft)}',
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
          _PoolQuestionSearch(materialBlockId: widget.materialBlockId, onReused: _loadAttached),
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
  const _PoolQuestionSearch({required this.materialBlockId, required this.onReused});
  final String materialBlockId;
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
      await ref.read(builderRepositoryProvider).reusePoolQuestion(question.id, materialBlockId: widget.materialBlockId);
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
                    title: Text(_previewText(q.draft), style: AdminTypography.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: TextButton(onPressed: () => _reuse(q), style: AdminButtonStyles.text(), child: const Text('Привязать')),
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
