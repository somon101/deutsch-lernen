import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import 'widgets/lesson_editor_panel.dart';

final _courseProvider = FutureProvider.autoDispose.family<AdminCourse, String>((ref, courseId) => ref.watch(builderRepositoryProvider).getCourse(courseId));

/// Mirrors BuilderCourseEditPage.tsx: course settings (title/description/
/// cover/publish toggle), the lesson tree, and — when a lesson is expanded
/// — the same LessonEditorPanel the legacy-lesson screen uses.
class BuilderCourseEditScreen extends ConsumerWidget {
  const BuilderCourseEditScreen({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(_courseProvider(courseId));

    return Scaffold(
      appBar: AppBar(
        title: Text(course.value?.title ?? 'Курс'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/admin/courses')),
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
        data: (c) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CourseSettingsCard(course: c),
            const SizedBox(height: 20),
            Text('Уроки', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (var i = 0; i < c.lessons.length; i++) _LessonTile(courseId: courseId, course: c, index: i),
            const SizedBox(height: 12),
            _AddLessonCard(courseId: courseId),
          ],
        ),
      ),
    );
  }
}

class _CourseSettingsCard extends ConsumerStatefulWidget {
  const _CourseSettingsCard({required this.course});
  final AdminCourse course;

  @override
  ConsumerState<_CourseSettingsCard> createState() => _CourseSettingsCardState();
}

class _CourseSettingsCardState extends ConsumerState<_CourseSettingsCard> {
  late final _title = TextEditingController(text: widget.course.title);
  late final _description = TextEditingController(text: widget.course.description);
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
      await ref.read(builderRepositoryProvider).updateCourse(widget.course.id, title: _title.text.trim(), description: _description.text.trim());
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
      await ref.read(builderRepositoryProvider).updateCourse(widget.course.id, status: next);
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
      await ref.read(builderRepositoryProvider).uploadCourseCover(widget.course.id, bytes: bytes, filename: file.name);
      ref.invalidate(_courseProvider(widget.course.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить обложку');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCover() async {
    try {
      await ref.read(builderRepositoryProvider).removeCourseCover(widget.course.id);
      ref.invalidate(_courseProvider(widget.course.id));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить обложку');
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl = ref.read(apiClientProvider).assetUrl(widget.course.coverUrl);
    final published = widget.course.status == 'PUBLISHED';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (coverUrl.isNotEmpty)
              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(coverUrl, height: 120, fit: BoxFit.cover)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(onPressed: _busy ? null : _pickCover, child: const Text('Загрузить обложку')),
                if (coverUrl.isNotEmpty) OutlinedButton(onPressed: _removeCover, child: const Text('Удалить обложку')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание')),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(onPressed: _busy ? null : _save, child: const Text('Сохранить')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _togglePublish,
                  child: Text(published ? 'Вернуть в черновики' : 'Опубликовать курс'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonTile extends ConsumerStatefulWidget {
  const _LessonTile({required this.courseId, required this.course, required this.index});
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
      await ref.read(builderRepositoryProvider).reorderLessons(widget.courseId, ids);
      ref.invalidate(_courseProvider(widget.courseId));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить порядок уроков');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Удалить урок «${_lesson.title}» вместе со словами и вопросами?');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).removeLesson(widget.courseId, _lesson.id);
      ref.invalidate(_courseProvider(widget.courseId));
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить урок');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = _lesson;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_upward), onPressed: widget.index > 0 ? () => _reorder(-1) : null),
                IconButton(icon: const Icon(Icons.arrow_downward), onPressed: widget.index < widget.course.lessons.length - 1 ? () => _reorder(1) : null),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('${widget.index + 1}. ${lesson.title}', style: Theme.of(context).textTheme.titleSmall),
                    ),
                  ),
                ),
                IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more), onPressed: () => setState(() => _open = !_open)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
              ],
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LessonNameCard(courseId: widget.courseId, lesson: lesson),
                  const SizedBox(height: 8),
                  LessonEditorPanel(
                    courseId: widget.courseId,
                    lesson: lesson,
                    onSaveMaterial: (text) async {
                      await ref.read(builderRepositoryProvider).updateLesson(widget.courseId, lesson.id, materialText: text);
                      ref.invalidate(_courseProvider(widget.courseId));
                    },
                    libraryLoader: (kind) => ref.read(builderRepositoryProvider).listMediaLibrary(kind),
                    onUploadMedia: (kind, bytes, filename) async {
                      try {
                        await ref.read(builderRepositoryProvider).uploadLessonMedia(widget.courseId, lesson.id, kind: kind, bytes: bytes, filename: filename);
                        ref.invalidate(_courseProvider(widget.courseId));
                        if (context.mounted) showSuccessSnack(context);
                      } catch (e) {
                        if (context.mounted) showErrorSnack(context, e, 'Не удалось загрузить файл');
                      }
                    },
                    onRemoveMedia: (kind) async {
                      try {
                        await ref.read(builderRepositoryProvider).removeLessonMedia(widget.courseId, lesson.id, kind);
                        ref.invalidate(_courseProvider(widget.courseId));
                      } catch (e) {
                        if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить файл');
                      }
                    },
                    onReuseMedia: (kind, url) async {
                      try {
                        await ref.read(builderRepositoryProvider).reuseLessonMedia(widget.courseId, lesson.id, kind, url);
                        ref.invalidate(_courseProvider(widget.courseId));
                      } catch (e) {
                        if (context.mounted) showErrorSnack(context, e, 'Не удалось выбрать файл');
                      }
                    },
                    onReload: () => ref.invalidate(_courseProvider(widget.courseId)),
                  ),
                ],
              ),
            ),
        ],
      ),
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
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название урока')),
        const SizedBox(height: 8),
        TextField(controller: _description, decoration: const InputDecoration(labelText: 'Описание')),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _busy ? null : _save, child: const Text('Сохранить название'))),
      ],
    );
  }
}

class _AddLessonCard extends ConsumerStatefulWidget {
  const _AddLessonCard({required this.courseId});
  final String courseId;

  @override
  ConsumerState<_AddLessonCard> createState() => _AddLessonCardState();
}

class _AddLessonCardState extends ConsumerState<_AddLessonCard> {
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
      await ref.read(builderRepositoryProvider).addLesson(widget.courseId, title: _title.text.trim());
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
        Expanded(child: TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название нового урока'))),
        const SizedBox(width: 8),
        ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('+ Добавить урок')),
      ],
    );
  }
}
