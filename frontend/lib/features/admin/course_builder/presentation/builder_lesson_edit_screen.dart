import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import '../domain/taxonomy_domain.dart';
import 'builder_course_edit_screen.dart';
import 'widgets/lesson_editor_panel.dart';
import 'widgets/lesson_graph_editor.dart';

final _levelsForLanguageProvider = FutureProvider.autoDispose<List<AdminLevel>>(
  (ref) => ref.watch(builderRepositoryProvider).listLevels(),
);

/// One lesson's editor, on its own screen (§9 of the course-builder
/// redesign, 2026-09-01: "разворот открывает не аккордеон, а переход на
/// экран урока с рельсом") — the same LessonEditorPanel the legacy-lesson
/// screen (AdminLessonEditScreen) already uses, reached via
/// BuilderCourseEditScreen's lesson list instead of expanding in place.
class BuilderLessonEditScreen extends ConsumerWidget {
  const BuilderLessonEditScreen({super.key, required this.courseId, required this.lessonId});

  final String courseId;
  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(builderCourseProvider(courseId));
    void reload() => ref.invalidate(builderCourseProvider(courseId));
    final lesson = course.value?.lessons.where((l) => l.id == lessonId).cast<AdminLesson?>().firstWhere((l) => l != null, orElse: () => null);
    // Course.levelId → Level.languageId (§ topic-language fix, 2026-09-01)
    // — MaterialBlockEditor needs a real Language.id to create topics
    // against; null (level not picked, or still loading) disables that
    // instead of guessing.
    final levelId = course.value?.levelId;
    final levels = ref.watch(_levelsForLanguageProvider).value;
    final languageId = levelId == null || levels == null
        ? null
        : levels.where((l) => l.id == levelId).map((l) => l.languageId).cast<String?>().firstWhere((_) => true, orElse: () => null);

    return BackGuard(
      fallbackPath: '/admin/builder/$courseId',
      // Same fixed-light-palette fix as the other admin screens (§ admin
      // light-theme fix, 2026-09-01).
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text(lesson?.title ?? 'Урок', style: AdminTypography.pageTitle),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  context.go('/admin/builder/$courseId');
                }
              },
            ),
          ),
          body: course.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => Center(
              child: Text('Не удалось загрузить урок: $err', style: AdminTypography.body),
            ),
            data: (c) {
              if (lesson == null) {
                return Center(child: Text('Урок не найден', style: AdminTypography.body));
              }
              // Deliberately no AdminMaxWidth here (§ builder full-width
              // layout, 2026-09-02) — the rail is a fixed 220px and the
              // working area takes everything else, so a wide monitor
              // actually buys the teacher room to edit rather than empty
              // margins.
              //
              // A Column, not a ListView: the header below is pinned and the
              // panel does its own scrolling, so that scrolling a long word
              // list never carries the lesson header and the step rail off
              // screen with it (§ pinned header + independent scroll,
              // 2026-09-02).
              // A lesson with a real graph (§ lesson graph, 2026-09-03 —
              // `lesson.graph != null`, set once a teacher explicitly
              // converts it) gets the new free-form canvas; every other
              // lesson keeps today's exact fixed 8-step rail, byte-for-byte
              // unchanged, with just a "Перевести в граф" entry point added.
              final graph = lesson.graph;
              return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdminCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LessonNameCard(courseId: courseId, lesson: lesson),
                          if (graph == null) ...[
                            const SizedBox(height: AdminMetrics.fieldGap),
                            _ConvertToGraphRow(courseId: courseId, lesson: lesson, onDone: reload),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    Expanded(
                      child: graph != null
                        ? LessonGraphEditor(courseId: courseId, lesson: lesson, languageId: languageId, onReload: reload)
                        : LessonEditorPanel(
                      courseId: courseId,
                      lesson: lesson,
                      languageId: languageId,
                      scrollBottomInset: bottomBarClearance(context),
                      libraryLoader: (kind) => ref.read(builderRepositoryProvider).listMediaLibrary(kind),
                      onUploadMedia: (kind, bytes, filename) async {
                        try {
                          await ref.read(builderRepositoryProvider).uploadLessonMedia(courseId, lesson.id, kind: kind, bytes: bytes, filename: filename);
                          reload();
                          if (context.mounted) showSuccessSnack(context);
                        } catch (e) {
                          if (context.mounted) showErrorSnack(context, e, 'Не удалось загрузить файл');
                        }
                      },
                      onRemoveMedia: (kind) async {
                        try {
                          await ref.read(builderRepositoryProvider).removeLessonMedia(courseId, lesson.id, kind);
                          reload();
                        } catch (e) {
                          if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить файл');
                        }
                      },
                      onReuseMedia: (kind, url) async {
                        try {
                          await ref.read(builderRepositoryProvider).reuseLessonMedia(courseId, lesson.id, kind, url);
                          reload();
                        } catch (e) {
                          if (context.mounted) showErrorSnack(context, e, 'Не удалось выбрать файл');
                        }
                      },
                      onReload: reload,
                    ),
                    ),
                  ],
                  ),
                );
            },
          ),
        ),
      ),
    );
  }
}

/// Rename/re-describe a lesson — unchanged content, just relocated from the
/// old inline accordion onto this lesson's own screen.
class LessonNameCard extends ConsumerStatefulWidget {
  const LessonNameCard({super.key, required this.courseId, required this.lesson});
  final String courseId;
  final AdminLesson lesson;

  @override
  ConsumerState<LessonNameCard> createState() => _LessonNameCardState();
}

class _LessonNameCardState extends ConsumerState<LessonNameCard> {
  late final _title = TextEditingController(text: widget.lesson.title);
  late final _description = TextEditingController(text: widget.lesson.description);
  bool _busy = false;
  // Collapsed by default (§ pinned header + independent scroll, 2026-09-02).
  // This card is pinned above the working area now, so every pixel it takes
  // is a pixel the word/question list never gets back — the teacher comes
  // here to edit content, not to re-read the lesson's own description. Same
  // collapse pattern as the course screen's own settings section.
  bool _expanded = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).updateLesson(widget.courseId, widget.lesson.id, title: _title.text.trim(), description: _description.text.trim());
      ref.invalidate(builderCourseProvider(widget.courseId));
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить название');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: AdminColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _expanded ? 'Название и описание' : widget.lesson.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTypography.cardTitle,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _title, decoration: adminInputDecoration(label: 'Название урока')),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _description, decoration: adminInputDecoration(label: 'Описание')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _save,
              style: AdminButtonStyles.text(),
              child: const Text('Сохранить название'),
            ),
          ),
        ],
      ],
    );
  }
}

/// One-time "Перевести в граф" entry point (§ lesson graph, 2026-09-03) —
/// shown only for a lesson still on the old fixed 8-stage chain. Fetches the
/// computed preview first (what the conversion would produce, from the
/// lesson's CURRENT content) so the teacher confirms an actual plan rather
/// than a blind action; the conversion itself references existing
/// Material/LessonBlock/vocabulary rows, it never duplicates content.
class _ConvertToGraphRow extends ConsumerStatefulWidget {
  const _ConvertToGraphRow({required this.courseId, required this.lesson, required this.onDone});
  final String courseId;
  final AdminLesson lesson;
  final VoidCallback onDone;

  @override
  ConsumerState<_ConvertToGraphRow> createState() => _ConvertToGraphRowState();
}

class _ConvertToGraphRowState extends ConsumerState<_ConvertToGraphRow> {
  bool _busy = false;

  Future<void> _convert() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(builderRepositoryProvider);
      final preview = await repo.getLessonGraph(widget.courseId, widget.lesson.id);
      if (!mounted) return;
      final chain = preview.nodes.map((n) => n.title).join(' → ');
      final ok = await confirmDialog(
        context,
        title: 'Перевести урок в граф?',
        message: preview.nodes.isEmpty
            ? 'В уроке пока нет содержимого — граф начнётся пустым, добавляйте блоки сами.'
            : 'Текущий порядок станет графом:\n$chain\n\nСодержимое (материалы, вопросы, слова) не удаляется и не копируется — блоки графа будут ссылаться на него. Это действие необратимо.',
        confirmLabel: 'Перевести в граф',
      );
      if (!ok) return;
      await repo.materializeLessonGraph(widget.courseId, widget.lesson.id);
      widget.onDone();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось перевести урок в граф');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Свободный граф блоков вместо фиксированной цепочки этапов.',
            style: AdminTypography.caption,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _convert,
          style: AdminButtonStyles.secondary(),
          icon: const Icon(Icons.hub_outlined, size: 16),
          label: const Text('Перевести в граф'),
        ),
      ],
    );
  }
}
