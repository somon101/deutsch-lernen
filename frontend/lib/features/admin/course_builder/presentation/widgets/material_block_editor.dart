import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/taxonomy_domain.dart';
import 'pool_questions_section.dart';
import 'question_kind_editors.dart';

/// Replaces the old single-textarea material editor with real, addressable
/// blocks (§6-9 of the content-taxonomy plan): each block has its own
/// title+content, can be added/removed/reordered by drag-and-drop, and can
/// carry its own reusable questions. Without a [materialId] (the old fixed
/// rail's "Материал" step), a lesson gets one "text" Material,
/// auto-created on first open. A graph "material" node (§ lesson graph,
/// 2026-09-03) passes its own materialId instead, so a lesson can have
/// several of these editors open on several distinct Material rows.
class MaterialBlockEditor extends ConsumerStatefulWidget {
  const MaterialBlockEditor({super.key, required this.courseId, required this.lessonId, required this.lessonTitle, required this.languageId, this.materialId});

  final String courseId;
  final String lessonId;
  final String lessonTitle;
  // When set (§ lesson graph, 2026-09-03 — a graph "material" node), loads
  // this EXACT Material row directly instead of the old "the lesson's one
  // text Material, auto-created on first open" lookup below — a lesson can
  // now have several Material nodes, each its own row. Null keeps the
  // original single-material behavior used by the old fixed-chain rail.
  final String? materialId;
  // The course's real Language.id (resolved from Course.levelId → Level.
  // languageId by the caller) — topics are scoped per-language, and Topic
  // creation needs an actual Language row to attach to. Null when the
  // course has no level/language assigned yet (a course created without
  // picking one, or the legacy file-based course, which predates the
  // Language/Level system entirely) — topic management is disabled rather
  // than guessing, since a wrong guess here previously caused a hardcoded
  // 'de' literal to 404 as "Язык не найден" (no Language row actually has
  // that id — real Language ids are UUIDs).
  final String? languageId;

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
    AdminMaterial? material;
    final materialId = widget.materialId;
    if (materialId != null) {
      material = materials.cast<AdminMaterial?>().firstWhere((m) => m!.id == materialId, orElse: () => null);
    } else {
      material = materials.where((m) => m.materialType == 'text').cast<AdminMaterial?>().firstWhere((m) => m != null, orElse: () => null);
    }
    // Defensive fallback only — a graph node's materialId is expected to
    // always resolve; this mirrors the old single-material auto-create path
    // rather than crashing if it somehow doesn't.
    material ??= await repo.createMaterial(courseId: widget.courseId, lessonId: widget.lessonId, materialType: 'text', title: widget.lessonTitle);
    final blocks = await repo.listMaterialBlocks(material.id);
    final languageId = widget.languageId;
    final topics = languageId == null ? <AdminTopic>[] : await repo.listTopics(languageId: languageId);
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
    final languageId = widget.languageId;
    if (languageId == null) {
      showErrorSnack(context, Exception('no language'), 'Сначала укажите язык курса в его настройках — темы привязаны к языку');
      return;
    }
    try {
      final (topic, existing) = await ref.read(builderRepositoryProvider).createTopic(languageId, name);
      setState(() => _topics = _topics.any((t) => t.id == topic.id) ? _topics : [..._topics, topic]);
      await _onTopicChanged(topic.id);
      if (mounted && existing) showSuccessSnack(context, 'Использована существующая тема «${topic.name}»');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось создать тему');
    }
  }

  Future<void> _deleteTopic(AdminTopic topic) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить тему «${topic.name}»?',
      message: 'Материалы и вопросы с этой темой не удалятся — просто потеряют привязку к ней.',
    );
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteTopic(topic.id);
      setState(() {
        _topics = _topics.where((t) => t.id != topic.id).toList();
        final material = _material;
        if (material != null && material.topicId == topic.id) {
          _material = AdminMaterial(
            id: material.id,
            courseId: material.courseId,
            lessonId: material.lessonId,
            materialType: material.materialType,
            title: material.title,
            topicId: null,
            position: material.position,
          );
        }
      });
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить тему');
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
        _TopicPicker(
          topics: _topics,
          selectedTopicId: material.topicId,
          languageAvailable: widget.languageId != null,
          onChanged: _onTopicChanged,
          onCreate: _createTopic,
          onDelete: _deleteTopic,
        ),
        const SizedBox(height: AdminMetrics.cardGap),
        if (_blocks.isEmpty) Text('Блоков пока нет — добавьте первый ниже.', style: AdminTypography.caption),
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
            languageId: widget.languageId,
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
  const _TopicPicker({
    required this.topics,
    required this.selectedTopicId,
    required this.languageAvailable,
    required this.onChanged,
    required this.onCreate,
    required this.onDelete,
  });

  final List<AdminTopic> topics;
  final String? selectedTopicId;
  // False when the course has no language resolved yet (§ topic-language
  // fix, 2026-09-01) — creating a topic needs a real Language row to
  // attach to, so the button is disabled with an explanatory tooltip
  // instead of failing with a confusing "Язык не найден".
  final bool languageAvailable;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onCreate;
  final ValueChanged<AdminTopic> onDelete;

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
        Tooltip(
          message: languageAvailable ? '' : 'Сначала укажите язык курса в его настройках',
          child: TextButton(
            onPressed: languageAvailable ? () => _promptNewTopic(context) : null,
            style: AdminButtonStyles.text(),
            child: const Text('+ Новая тема'),
          ),
        ),
        IconButton(
          tooltip: 'Управление темами',
          icon: const Icon(Icons.settings_outlined, size: 20),
          onPressed: topics.isEmpty ? null : () => _manageTopics(context),
        ),
      ],
    );
  }

  // Closes on any delete rather than trying to keep the dialog's own list in
  // sync with the parent's setState — reopening to delete another is a
  // small price for not fighting two independent rebuild sources.
  // Both dialogs below force lightTheme (§ admin light-theme fix,
  // 2026-09-01) — showDialog attaches to the Navigator's Overlay, outside
  // this screen's own `Theme(data: lightTheme, ...)` wrapper.
  Future<void> _manageTopics(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Theme(
        data: lightTheme,
        child: AlertDialog(
          title: const Text('Темы языка'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final topic in topics)
                  ListTile(
                    dense: true,
                    title: Text(topic.name),
                    trailing: AdminDeleteLink(
                      onPressed: () {
                        Navigator.of(context).pop();
                        onDelete(topic);
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Готово'))],
        ),
      ),
    );
  }

  Future<void> _promptNewTopic(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => Theme(
        data: lightTheme,
        child: AlertDialog(
          title: const Text('Новая тема'),
          content: TextField(controller: controller, decoration: adminInputDecoration(label: 'Название темы', hint: 'Präteritum')),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Создать')),
          ],
        ),
      ),
    );
    if (name != null && name.isNotEmpty) onCreate(name);
  }
}

class _MaterialBlockCard extends ConsumerStatefulWidget {
  const _MaterialBlockCard({
    super.key,
    required this.index,
    required this.block,
    required this.topicId,
    required this.languageId,
    required this.onDeleted,
    required this.onSaved,
  });

  final int index;
  final AdminMaterialBlock block;
  final String? topicId;
  final String? languageId;
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
              PoolQuestionsSection(materialBlockId: widget.block.id, topicId: widget.topicId, languageId: widget.languageId),
              const SizedBox(height: AdminMetrics.cardGap),
              _VerifyingQuestionsSection(materialBlockId: widget.block.id),
            ],
          ],
        ),
      ),
    );
  }
}

/// Read-only reverse of PoolQuestionsSection's own list (§ course-builder
/// redesign, "Проверяет этот блок", 2026-09-01): quiz-stage questions
/// elsewhere (minitest/practice/review) that are tagged as verifying THIS
/// reading block — none of them live here, this is purely a pointer so the
/// teacher can see, from the theory side, what actually tests it. Not an
/// editor: attaching/detaching the tag happens on the question's own chip
/// (PoolQuestionsSection._VerifiesChip), where the question actually lives.
class _VerifyingQuestionsSection extends ConsumerStatefulWidget {
  const _VerifyingQuestionsSection({required this.materialBlockId});
  final String materialBlockId;

  @override
  ConsumerState<_VerifyingQuestionsSection> createState() => _VerifyingQuestionsSectionState();
}

class _VerifyingQuestionsSectionState extends ConsumerState<_VerifyingQuestionsSection> {
  List<VerifyingQuestion>? _questions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final questions = await ref.read(builderRepositoryProvider).listVerifyingQuestions(widget.materialBlockId);
      if (mounted) setState(() => _questions = questions);
    } catch (_) {
      // Non-critical, read-only section — just stays empty on failure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = _questions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Проверяет этот блок', style: AdminTypography.fieldLabel),
        const SizedBox(height: 6),
        if (questions == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
        else if (questions.isEmpty)
          Text('Ни одно задание пока не проверяет этот блок.', style: AdminTypography.caption)
        else
          for (final q in questions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _VerifyingQuestionRow(question: q),
            ),
      ],
    );
  }
}

class _VerifyingQuestionRow extends StatelessWidget {
  const _VerifyingQuestionRow({required this.question});
  final VerifyingQuestion question;

  @override
  Widget build(BuildContext context) {
    final q = question;
    return InkWell(
      borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
      onTap: q.courseId == null ? null : () => context.push('/admin/builder/${q.courseId}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '${q.stageLabel ?? q.stage ?? '?'} · ${poolQuestionPreviewText(q.draft)}',
                style: AdminTypography.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (q.courseId != null) const Icon(Icons.chevron_right, color: AdminColors.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

