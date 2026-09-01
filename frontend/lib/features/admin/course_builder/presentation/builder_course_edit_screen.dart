import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import 'widgets/lesson_editor_panel.dart';
import 'widgets/level_picker.dart';

final _courseProvider = FutureProvider.autoDispose.family<AdminCourse, String>(
  (ref, courseId) => ref.watch(builderRepositoryProvider).getCourse(courseId),
);

int _wordCount(AdminCourse c) =>
    c.lessons.fold(0, (sum, l) => sum + l.vocabulary.length);
int _questionCount(AdminCourse c) => c.lessons.fold(
  0,
  (sum, l) => sum + l.blocks.fold(0, (s, b) => s + b.questions.length),
);

String _mediaCounter(String? url) =>
    url != null && url.isNotEmpty ? 'файл' : 'нет';
String _blocksCounter(List<AdminBlock> blocks) =>
    blocks.isEmpty ? 'нет блоков' : '${blocks.length} блок(ов)';

/// Mirrors BuilderCourseEditPage.tsx: course settings (title/description/
/// cover/publish toggle), the lesson tree, and — when a lesson is expanded
/// — the same LessonEditorPanel the legacy-lesson screen uses.
class BuilderCourseEditScreen extends ConsumerWidget {
  const BuilderCourseEditScreen({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(_courseProvider(courseId));

    return BackGuard(
      fallbackPath: '/admin/courses',
      // Forces this fixed-light-palette screen family's unstyled defaults
      // (e.g. a plain TextField's own text color) to match, regardless of
      // the app's dark-mode toggle — see the matching fix + full
      // explanation in admin_courses_hub_screen.dart (§ admin light-theme
      // fix, 2026-09-01).
      child: Theme(
        data: lightTheme,
        child: Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.card,
        foregroundColor: AdminColors.text,
        elevation: 0,
        title: Text(
          course.value?.title ?? 'Курс',
          style: AdminTypography.pageTitle,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/courses'),
        ),
      ),
      body: course.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) {
          // Mirrors the React page's redirect-to-hub-on-load-failure.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) context.go('/admin/courses');
          });
          return const Center(child: CircularProgressIndicator());
        },
        data: (c) => AdminMaxWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => context.go('/admin/courses'),
                  child: Text('Курсы →', style: AdminTypography.caption),
                ),
              ),
              _CourseSettingsCard(course: c),
              const SizedBox(height: AdminMetrics.cardGap),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Структура курса',
                      style: AdminTypography.cardTitle,
                    ),
                    Text(
                      '${c.lessons.length} уроков · ${_wordCount(c)} слов · ${_questionCount(c)} вопросов',
                      style: AdminTypography.caption,
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    for (var i = 0; i < c.lessons.length; i++)
                      _LessonTile(courseId: courseId, course: c, index: i),
                    if (c.lessons.isEmpty)
                      Text(
                        'Уроков пока нет — добавьте первый ниже.',
                        style: AdminTypography.caption,
                      ),
                    const SizedBox(height: 8),
                    _AddLessonRow(courseId: courseId),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}

class _CourseSettingsCard extends ConsumerStatefulWidget {
  const _CourseSettingsCard({required this.course});
  final AdminCourse course;

  @override
  ConsumerState<_CourseSettingsCard> createState() =>
      _CourseSettingsCardState();
}

class _CourseSettingsCardState extends ConsumerState<_CourseSettingsCard> {
  late final _title = TextEditingController(text: widget.course.title);
  late final _description = TextEditingController(
    text: widget.course.description,
  );
  late String? _levelId = widget.course.levelId;
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
      await ref
          .read(builderRepositoryProvider)
          .updateCourse(
            widget.course.id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            levelId: _levelId,
          );
      ref.invalidate(_courseProvider(widget.course.id));
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить курс');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePublish() async {
    final next = widget.course.status == 'PUBLISHED' ? 'DRAFT' : 'PUBLISHED';
    try {
      await ref
          .read(builderRepositoryProvider)
          .updateCourse(widget.course.id, status: next);
      ref.invalidate(_courseProvider(widget.course.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить статус');
    }
  }

  Future<void> _pickCover() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref
          .read(builderRepositoryProvider)
          .uploadCourseCover(
            widget.course.id,
            bytes: bytes,
            filename: file.name,
          );
      ref.invalidate(_courseProvider(widget.course.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить обложку');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCover() async {
    try {
      await ref
          .read(builderRepositoryProvider)
          .removeCourseCover(widget.course.id);
      ref.invalidate(_courseProvider(widget.course.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить обложку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = ref
        .read(apiClientProvider)
        .assetUrl(widget.course.coverUrl);
    final published = widget.course.status == 'PUBLISHED';
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  widget.course.title,
                  style: AdminTypography.cardTitle,
                ),
              ),
              AdminStatusBadge(published: published),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _title,
            decoration: adminInputDecoration(label: 'Название курса'),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          LevelPickerField(initialLevelId: _levelId, onChanged: (id) => setState(() => _levelId = id)),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: adminInputDecoration(label: 'Описание'),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          if (coverUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(coverUrl, height: 100, fit: BoxFit.cover),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (coverUrl.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AdminColors.blockBg,
                    borderRadius: BorderRadius.circular(
                      AdminMetrics.buttonRadius,
                    ),
                  ),
                  child: Text(
                    'Без обложки',
                    style: AdminTypography.caption,
                  ),
                ),
              OutlinedButton(
                onPressed: _busy ? null : _pickCover,
                style: AdminButtonStyles.secondary(),
                child: Text(
                  coverUrl.isEmpty ? 'Загрузить обложку' : 'Заменить обложку',
                ),
              ),
              if (coverUrl.isNotEmpty)
                AdminDeleteLink(
                  onPressed: _removeCover,
                  label: 'Удалить обложку',
                ),
            ],
          ),
          const SizedBox(height: AdminMetrics.cardGap),
          Row(
            children: [
              OutlinedButton(
                onPressed: _togglePublish,
                style: AdminButtonStyles.secondary(),
                child: Text(
                  published ? 'Вернуть в черновики' : 'Опубликовать курс',
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: AdminButtonStyles.primary(),
                child: const Text('Сохранить курс'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonTile extends ConsumerStatefulWidget {
  const _LessonTile({
    required this.courseId,
    required this.course,
    required this.index,
  });
  final String courseId;
  final AdminCourse course;
  final int index;

  @override
  ConsumerState<_LessonTile> createState() => _LessonTileState();
}

class _LessonTileState extends ConsumerState<_LessonTile> {
  bool _open = false;

  AdminLesson get _lesson => widget.course.lessons[widget.index];

  Future<void> _reorder(int delta) async {
    final ids = widget.course.lessons.map((l) => l.id).toList();
    final j = widget.index + delta;
    if (j < 0 || j >= ids.length) return;
    final tmp = ids[widget.index];
    ids[widget.index] = ids[j];
    ids[j] = tmp;
    try {
      await ref
          .read(builderRepositoryProvider)
          .reorderLessons(widget.courseId, ids);
      ref.invalidate(_courseProvider(widget.courseId));
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e, 'Не удалось изменить порядок уроков');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить урок «${_lesson.title}» вместе со словами и вопросами?',
    );
    if (!ok) return;
    try {
      await ref
          .read(builderRepositoryProvider)
          .removeLesson(widget.courseId, _lesson.id);
      ref.invalidate(_courseProvider(widget.courseId));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить урок');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _open ? AdminColors.blockBg : null,
        borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _open = !_open),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${widget.index + 1}. ${lesson.title}',
                        style: AdminTypography.stageTitle,
                      ),
                    ),
                  ),
                ),
                AdminReorderArrows(
                  canMoveUp: widget.index > 0,
                  canMoveDown: widget.index < widget.course.lessons.length - 1,
                  onMove: _reorder,
                ),
                const SizedBox(width: 4),
                AdminDeleteLink(onPressed: _delete),
              ],
            ),
          ),
          if (!_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 10),
              child: _LessonStatusGrid(lesson: lesson),
            ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LessonNameCard(courseId: widget.courseId, lesson: lesson),
                  const SizedBox(height: AdminMetrics.fieldGap),
                  LessonEditorPanel(
                    courseId: widget.courseId,
                    lesson: lesson,
                    libraryLoader: (kind) => ref
                        .read(builderRepositoryProvider)
                        .listMediaLibrary(kind),
                    onUploadMedia: (kind, bytes, filename) async {
                      try {
                        await ref
                            .read(builderRepositoryProvider)
                            .uploadLessonMedia(
                              widget.courseId,
                              lesson.id,
                              kind: kind,
                              bytes: bytes,
                              filename: filename,
                            );
                        ref.invalidate(_courseProvider(widget.courseId));
                        if (context.mounted) showSuccessSnack(context);
                      } catch (e) {
                        if (context.mounted) {
                          showErrorSnack(
                            context,
                            e,
                            'Не удалось загрузить файл',
                          );
                        }
                      }
                    },
                    onRemoveMedia: (kind) async {
                      try {
                        await ref
                            .read(builderRepositoryProvider)
                            .removeLessonMedia(
                              widget.courseId,
                              lesson.id,
                              kind,
                            );
                        ref.invalidate(_courseProvider(widget.courseId));
                      } catch (e) {
                        if (context.mounted) {
                          showErrorSnack(context, e, 'Не удалось удалить файл');
                        }
                      }
                    },
                    onReuseMedia: (kind, url) async {
                      try {
                        await ref
                            .read(builderRepositoryProvider)
                            .reuseLessonMedia(
                              widget.courseId,
                              lesson.id,
                              kind,
                              url,
                            );
                        ref.invalidate(_courseProvider(widget.courseId));
                      } catch (e) {
                        if (context.mounted) {
                          showErrorSnack(context, e, 'Не удалось выбрать файл');
                        }
                      }
                    },
                    onReload: () =>
                        ref.invalidate(_courseProvider(widget.courseId)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The compact 3-column status grid shown under a collapsed lesson row —
/// lets an admin see which stages of every lesson are still empty without
/// opening each one (Screenshot 8).
class _LessonStatusGrid extends StatelessWidget {
  const _LessonStatusGrid({required this.lesson});
  final AdminLesson lesson;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Слова', '${lesson.vocabulary.length}'),
      ('Материал', 'блоки'),
      ('Видео', _mediaCounter(lesson.videoUrl)),
      ('Аудио', _mediaCounter(lesson.audioUrl)),
      ('Мини-тест', _blocksCounter(lesson.blocksFor('minitest'))),
      ('Практика', _blocksCounter(lesson.blocksFor('practice'))),
      ('Закрепление', _blocksCounter(lesson.blocksFor('review'))),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 4.2,
      mainAxisSpacing: 2,
      children: [
        for (final (label, value) in items)
          Row(
            children: [
              Text('$label ', style: AdminTypography.caption),
              Expanded(
                child: Text(
                  value,
                  style: AdminTypography.caption.copyWith(
                    color: AdminColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _LessonNameCard extends ConsumerStatefulWidget {
  const _LessonNameCard({required this.courseId, required this.lesson});
  final String courseId;
  final AdminLesson lesson;

  @override
  ConsumerState<_LessonNameCard> createState() => _LessonNameCardState();
}

class _LessonNameCardState extends ConsumerState<_LessonNameCard> {
  late final _title = TextEditingController(text: widget.lesson.title);
  late final _description = TextEditingController(
    text: widget.lesson.description,
  );
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
      await ref
          .read(builderRepositoryProvider)
          .updateLesson(
            widget.courseId,
            widget.lesson.id,
            title: _title.text.trim(),
            description: _description.text.trim(),
          );
      ref.invalidate(_courseProvider(widget.courseId));
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
        TextField(
          controller: _title,
          decoration: adminInputDecoration(label: 'Название урока'),
        ),
        const SizedBox(height: AdminMetrics.fieldGap),
        TextField(
          controller: _description,
          decoration: adminInputDecoration(label: 'Описание'),
        ),
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

class _AddLessonRow extends ConsumerStatefulWidget {
  const _AddLessonRow({required this.courseId});
  final String courseId;

  @override
  ConsumerState<_AddLessonRow> createState() => _AddLessonRowState();
}

class _AddLessonRowState extends ConsumerState<_AddLessonRow> {
  final _title = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(builderRepositoryProvider)
          .addLesson(widget.courseId, title: _title.text.trim());
      _title.clear();
      ref.invalidate(_courseProvider(widget.courseId));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось добавить урок');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _title,
            decoration: adminInputDecoration(label: 'Название нового урока'),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: AdminButtonStyles.primary(),
          child: const Text('+ Добавить урок'),
        ),
      ],
    );
  }
}
