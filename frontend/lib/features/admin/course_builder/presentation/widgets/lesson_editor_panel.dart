import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/admin_feedback.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
import 'block_editor.dart';
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

/// Counter shown to the right of a collapsed stage's header — computed from
/// the lesson's real data, never hardcoded, so an admin can tell a stage is
/// empty without opening it (Screenshot 1/6).
String _counterFor(AdminLesson lesson, String key) {
  switch (key) {
    case 'vocabulary':
      return '${lesson.vocabulary.length} слов';
    case 'material':
      return 'блоки материала';
    case 'video':
      return lesson.videoUrl != null && lesson.videoUrl!.isNotEmpty
          ? 'файл загружен'
          : 'нет';
    case 'audio':
      return lesson.audioUrl != null && lesson.audioUrl!.isNotEmpty
          ? 'файл загружен'
          : 'нет';
    case 'minitest':
    case 'practice':
    case 'review':
      final blocks = lesson.blocksFor(key);
      if (blocks.isEmpty) return 'нет блоков';
      final questions = blocks.fold(0, (sum, b) => sum + b.questions.length);
      return '${blocks.length} блок(ов) · $questions вопросов';
    case 'complete':
    default:
      return 'считается автоматически';
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
  });

  final String courseId;
  final AdminLesson lesson;
  final Future<List<MediaLibraryEntry>> Function(String kind) libraryLoader;
  final Future<void> Function(String kind, List<int> bytes, String filename)
  onUploadMedia;
  final Future<void> Function(String kind) onRemoveMedia;
  final Future<void> Function(String kind, String url) onReuseMedia;
  final VoidCallback onReload;

  @override
  ConsumerState<LessonEditorPanel> createState() => _LessonEditorPanelState();
}

class _LessonEditorPanelState extends ConsumerState<LessonEditorPanel> {
  String? _open = 'vocabulary';

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
      if (mounted)
        showErrorSnack(context, e, 'Не удалось изменить порядок блоков');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _chain.length; i++) ...[
          _section(context, i + 1, _chain[i]),
          if (i < _chain.length - 1) const AdminStepConnector(),
        ],
      ],
    );
  }

  Widget _section(
    BuildContext context,
    int number,
    ({String key, String label, String? note}) step,
  ) {
    final isOpen = _open == step.key;
    return AdminCard(
      padding: EdgeInsets.zero,
      highlighted: isOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminStageHeader(
            number: number,
            title: step.label,
            subtitle: step.note,
            counter: _counterFor(widget.lesson, step.key),
            isOpen: isOpen,
            onTap: () => setState(() => _open = isOpen ? null : step.key),
          ),
          if (isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _body(context, step.key),
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
        return const Text(
          'Считается автоматически — экран результатов показывает итоги мини-теста, практики и закрепления.',
          style: AdminTypography.caption,
        );
    }
  }
}
