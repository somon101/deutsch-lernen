import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../admin_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import 'builder_course_edit_screen.dart';
import 'widgets/lesson_editor_panel.dart';

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
              return AdminMaxWidth(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AdminCard(child: LessonNameCard(courseId: courseId, lesson: lesson)),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    LessonEditorPanel(
                      courseId: courseId,
                      lesson: lesson,
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
    );
  }
}
