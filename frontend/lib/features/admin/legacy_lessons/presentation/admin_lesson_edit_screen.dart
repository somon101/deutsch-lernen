import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/widgets/back_guard.dart';
import '../../../profile/data/profile_repository.dart';
import '../../admin_tokens.dart';
import '../../course_builder/data/builder_repository.dart';
import '../../course_builder/domain/builder_domain.dart';
import '../../course_builder/presentation/widgets/lesson_editor_panel.dart';
import '../../widgets/admin_feedback.dart';
import '../data/legacy_admin_repository.dart';

final _legacyLessonProvider = FutureProvider.autoDispose
    .family<AdminLesson, String>((ref, lessonId) async {
      final lessons = await ref
          .watch(profileRepositoryProvider)
          .fetchLegacyLessons();
      final match = lessons.where((l) => l.lessonId == lessonId).toList();
      final title = match.isNotEmpty ? match.first.title : lessonId;
      return ref
          .watch(legacyAdminRepositoryProvider)
          .getContent(lessonId, title);
    });

/// Mirrors AdminLessonEditPage.tsx — the legacy-lesson editor, built on the
/// same LessonEditorPanel the course builder uses (courseId "legacy").
class AdminLessonEditScreen extends ConsumerWidget {
  const AdminLessonEditScreen({super.key, required this.lessonId});

  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = ref.watch(_legacyLessonProvider(lessonId));
    final repo = ref.watch(legacyAdminRepositoryProvider);

    void reload() => ref.invalidate(_legacyLessonProvider(lessonId));

    return BackGuard(
      fallbackPath: '/admin/courses/legacy',
      child: Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.card,
        foregroundColor: AdminColors.text,
        elevation: 0,
        title: Text(
          lesson.value?.title ?? 'Урок',
          style: AdminTypography.pageTitle,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/courses/legacy'),
        ),
      ),
      body: lesson.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(
          child: Text(
            'Не удалось загрузить урок: $err',
            style: AdminTypography.body,
          ),
        ),
        data: (l) => AdminMaxWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LessonEditorPanel(
                courseId: 'legacy',
                lesson: l,
                // The media library is global/cross-course (builder.py's
                // /api/builder/media/library) — legacy lessons reuse it too.
                libraryLoader: (kind) =>
                    ref.read(builderRepositoryProvider).listMediaLibrary(kind),
                onUploadMedia: (kind, bytes, filename) async {
                  try {
                    await repo.uploadMedia(
                      lessonId,
                      l.title,
                      kind: kind,
                      bytes: bytes,
                      filename: filename,
                    );
                    reload();
                    if (context.mounted) showSuccessSnack(context);
                  } catch (e) {
                    if (context.mounted) {
                      showErrorSnack(context, e, 'Не удалось загрузить файл');
                    }
                  }
                },
                onRemoveMedia: (kind) async {
                  try {
                    await repo.removeMedia(lessonId, l.title, kind);
                    reload();
                  } catch (e) {
                    if (context.mounted) {
                      showErrorSnack(context, e, 'Не удалось удалить файл');
                    }
                  }
                },
                onReuseMedia: (kind, url) async {
                  try {
                    await repo.reuseMedia(lessonId, l.title, kind, url);
                    reload();
                  } catch (e) {
                    if (context.mounted) {
                      showErrorSnack(context, e, 'Не удалось выбрать файл');
                    }
                  }
                },
                onReload: reload,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
