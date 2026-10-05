import '../../ai/presentation/ai_lesson_generator_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/locale/content_locale.dart';
import '../../../../core/locale/locale_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import 'widgets/lesson_map_view.dart';
import 'widgets/level_picker.dart';

final builderCourseProvider = FutureProvider.autoDispose.family<AdminCourse, String>(
  (ref, courseId) => ref.watch(builderRepositoryProvider).getCourse(courseId),
);

/// Where "back" from a course goes: its language's workspace (courses tab),
/// or the language list when the course has no level yet.
final _courseBackPathProvider = FutureProvider.autoDispose.family<String, String?>((ref, levelId) async {
  if (levelId == null) return '/admin/courses';
  final levels = await ref.watch(builderRepositoryProvider).listLevels();
  final match = levels.where((l) => l.id == levelId);
  return match.isEmpty ? '/admin/courses' : '/admin/languages/${Uri.encodeComponent(match.first.languageId)}';
});

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

/// Course settings (collapsed by default — §9 of the course-builder
/// redesign, 2026-09-01: "учитель приходит сюда за уроками, а не за
/// описанием") plus the lesson tree; opening a lesson navigates to
/// [BuilderLessonEditScreen] instead of expanding in place.
class BuilderCourseEditScreen extends ConsumerWidget {
  const BuilderCourseEditScreen({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(builderCourseProvider(courseId));
    final backPath = ref.watch(_courseBackPathProvider(course.value?.levelId)).value ?? '/admin/courses';

    return BackGuard(
      fallbackPath: backPath,
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
          onPressed: () => context.go(backPath),
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
          maxWidth: AdminMetrics.maxListWidth,
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarClearance(context)),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => context.go(backPath),
                  child: Text('Курсы →', style: AdminTypography.caption),
                ),
              ),
              _CourseSettingsCard(course: c),
              const SizedBox(height: AdminMetrics.cardGap),
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Структура курса', style: AdminTypography.cardTitle),
                        Wrap(
                          spacing: 4,
                          children: [
                            TextButton.icon(
                              onPressed: () async {
                                final saved = await Navigator.of(context).push<bool>(
                                  MaterialPageRoute(builder: (_) => AiLessonGeneratorScreen(courseId: courseId, courseTitle: c.title)),
                                );
                                if (saved == true) ref.invalidate(builderCourseProvider(courseId));
                              },
                              style: AdminButtonStyles.text(),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Создать уроки с ИИ'),
                            ),
                            TextButton.icon(
                              onPressed: () => context.go('/admin/builder/${Uri.encodeComponent(courseId)}/videos'),
                              style: AdminButtonStyles.text(),
                              icon: const Icon(Icons.smart_display_outlined, size: 16),
                              label: const Text('Видеоуроки'),
                            ),
                            if (c.lessons.isNotEmpty)
                              TextButton.icon(
                                onPressed: () => showCourseConnectionsMap(context, courseId: courseId, courseTitle: c.title),
                                style: AdminButtonStyles.text(),
                                icon: const Icon(Icons.hub_outlined, size: 16),
                                label: const Text('Карта курса'),
                              ),
                            TextButton.icon(
                              onPressed: () => _editModule(context, ref, courseId, null),
                              style: AdminButtonStyles.text(),
                              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
                              label: const Text('+ Модуль'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      '${c.modules.isNotEmpty ? '${c.modules.length} модулей · ' : ''}'
                      '${c.lessons.length} уроков · ${_wordCount(c)} слов · ${_questionCount(c)} вопросов',
                      style: AdminTypography.caption,
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    if (c.modules.isEmpty)
                      for (var i = 0; i < c.lessons.length; i++) _LessonTile(courseId: courseId, course: c, index: i)
                    else ...[
                      for (var m = 0; m < c.modules.length; m++) ...[
                        _ModuleHeader(courseId: courseId, course: c, index: m),
                        for (var i = 0; i < c.lessons.length; i++)
                          if (c.lessons[i].moduleId == c.modules[m].id) _LessonTile(courseId: courseId, course: c, index: i),
                        if (!c.lessons.any((l) => l.moduleId == c.modules[m].id))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Text('В модуле пока нет уроков.', style: AdminTypography.caption),
                          ),
                      ],
                      if (c.lessons.any((l) => !c.modules.any((m) => m.id == l.moduleId))) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                          child: Text('Без модуля', style: AdminTypography.fieldLabel),
                        ),
                        for (var i = 0; i < c.lessons.length; i++)
                          if (!c.modules.any((m) => m.id == c.lessons[i].moduleId)) _LessonTile(courseId: courseId, course: c, index: i),
                      ],
                    ],
                    if (c.lessons.isEmpty)
                      Text(
                        'Уроков пока нет — добавьте первый ниже.',
                        style: AdminTypography.caption,
                      ),
                    const SizedBox(height: 8),
                    _AddLessonRow(courseId: courseId, modules: c.modules),
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
  // Collapsed by default (§9 of the course-builder redesign, 2026-09-01:
  // "учитель приходит сюда за уроками, а не за описанием").
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
      await ref
          .read(builderRepositoryProvider)
          .updateCourse(
            widget.course.id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            levelId: _levelId,
          );
      ref.invalidate(builderCourseProvider(widget.course.id));
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
      ref.invalidate(builderCourseProvider(widget.course.id));
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
      ref.invalidate(builderCourseProvider(widget.course.id));
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
      ref.invalidate(builderCourseProvider(widget.course.id));
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
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AdminColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.course.title,
                    style: AdminTypography.cardTitle,
                  ),
                ),
                AdminStatusBadge(published: published),
              ],
            ),
          ),
          if (!_expanded)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 2),
              child: Text('Настройки курса', style: AdminTypography.caption),
            ),
          if (_expanded) ...[
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
            const SizedBox(height: AdminMetrics.cardGap),
            _CourseTranslationsSection(courseId: widget.course.id, translations: widget.course.translations),
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
            // Said before the click, not only after it: a course with no
            // level is filtered out of every learner's course list (the home
            // screen always asks by language, and that filter joins through
            // Level), so publishing it would reach nobody. The server refuses
            // the publish; this is the part that explains why in advance
            // (§ course level required to publish, 2026-09-02).
            if (widget.course.levelId == null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: AdminColors.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Уровень не указан — курс нельзя опубликовать: ученики не увидят его в списке.',
                      style: AdminTypography.caption.copyWith(color: AdminColors.danger),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AdminMetrics.cardGap),
            ],
            Row(
              children: [
                OutlinedButton(
                  onPressed: (!published && widget.course.levelId == null) ? null : _togglePublish,
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
        ],
      ),
    );
  }
}

/// The teacher-facing side of course content language (§ course content
/// language, 2026-09-04, spec §5: "преподаватель должен видеть языковые
/// версии учебного контента"). A locale tab strip plus title/description
/// fields, each locale saved independently via its own translations/{locale}
/// endpoint — never touches the base title/description fields above, which
/// stay whatever the Russian original always was.
class _CourseTranslationsSection extends ConsumerStatefulWidget {
  const _CourseTranslationsSection({required this.courseId, required this.translations});
  final String courseId;
  final Map<String, AdminCourseTranslation> translations;

  @override
  ConsumerState<_CourseTranslationsSection> createState() => _CourseTranslationsSectionState();
}

class _CourseTranslationsSectionState extends ConsumerState<_CourseTranslationsSection> {
  String _locale = supportedContentLocales.first;
  late final _title = TextEditingController(text: widget.translations[_locale]?.title ?? '');
  late final _description = TextEditingController(text: widget.translations[_locale]?.description ?? '');
  bool _busy = false;

  void _switchLocale(String locale) {
    setState(() {
      _locale = locale;
      _title.text = widget.translations[locale]?.title ?? '';
      _description.text = widget.translations[locale]?.description ?? '';
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(builderRepositoryProvider)
          .setCourseTranslation(widget.courseId, _locale, title: _title.text.trim(), description: _description.text.trim());
      ref.invalidate(builderCourseProvider(widget.courseId));
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить перевод');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminColors.blockBg,
        borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Языковые версии курса', style: AdminTypography.cardTitle),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final locale in supportedContentLocales)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${localeDisplayName(Locale(locale))}${widget.translations.containsKey(locale) ? '' : ' — нет перевода'}',
                    ),
                    selected: _locale == locale,
                    onSelected: (_) => _switchLocale(locale),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _title, decoration: adminInputDecoration(label: 'Название курса')),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _description, maxLines: 3, decoration: adminInputDecoration(label: 'Описание')),
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

/// Collapsed row only (§9 of the course-builder redesign, 2026-09-01:
/// "та же логика, что и блоки материала: свёрнутая строка со сводкой
/// заполненности, разворот открывает не аккордеон, а переход на экран
/// урока с рельсом") — tapping navigates to [BuilderLessonEditScreen]
/// instead of expanding LessonEditorPanel in place.
class _LessonTile extends ConsumerWidget {
  const _LessonTile({
    required this.courseId,
    required this.course,
    required this.index,
  });
  final String courseId;
  final AdminCourse course;
  final int index;

  AdminLesson get _lesson => course.lessons[index];

  bool _sameGroup(int j) => j >= 0 && j < course.lessons.length && course.lessons[j].moduleId == _lesson.moduleId;

  Future<void> _moveToModule(WidgetRef ref, BuildContext context, String? moduleId) async {
    try {
      await ref.read(builderRepositoryProvider).setLessonModule(courseId, _lesson.id, moduleId);
      ref.invalidate(builderCourseProvider(courseId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось перенести урок');
    }
  }

  Future<void> _reorder(WidgetRef ref, BuildContext context, int delta) async {
    final ids = course.lessons.map((l) => l.id).toList();
    final j = index + delta;
    if (!_sameGroup(j)) return;
    final tmp = ids[index];
    ids[index] = ids[j];
    ids[j] = tmp;
    try {
      await ref.read(builderRepositoryProvider).reorderLessons(courseId, ids);
      ref.invalidate(builderCourseProvider(courseId));
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, e, 'Не удалось изменить порядок уроков');
      }
    }
  }

  Future<void> _delete(WidgetRef ref, BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить урок «${_lesson.title}» вместе со словами и вопросами?',
    );
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).removeLesson(courseId, _lesson.id);
      ref.invalidate(builderCourseProvider(courseId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить урок');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = _lesson;
    void open() => context.push('/admin/builder/$courseId/lessons/${lesson.id}');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
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
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Icon(Icons.chevron_right, size: 20, color: AdminColors.textSecondary),
                ),
                Expanded(
                  child: InkWell(
                    onTap: open,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        '${index + 1}. ${lesson.title}',
                        style: AdminTypography.stageTitle,
                      ),
                    ),
                  ),
                ),
                if (lesson.pendingSteps > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Tooltip(
                      message: 'Шагов ждут ИИ: ${lesson.pendingSteps}',
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(Icons.auto_awesome, size: 14),
                        label: Text('ждёт ИИ: ${lesson.pendingSteps}', style: AdminTypography.caption),
                      ),
                    ),
                  ),
                if (course.modules.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Перенести в модуль',
                    icon: const Icon(Icons.drive_file_move_outline, size: 20, color: AdminColors.textSecondary),
                    onSelected: (v) => _moveToModule(ref, context, v.isEmpty ? null : v),
                    itemBuilder: (_) => [
                      for (final m in course.modules)
                        CheckedPopupMenuItem(value: m.id, checked: lesson.moduleId == m.id, child: Text(m.title)),
                      CheckedPopupMenuItem(value: '', checked: !course.modules.any((m) => m.id == lesson.moduleId), child: const Text('Без модуля')),
                    ],
                  ),
                AdminReorderArrows(
                  canMoveUp: _sameGroup(index - 1),
                  canMoveDown: _sameGroup(index + 1),
                  onMove: (delta) => _reorder(ref, context, delta),
                ),
                const SizedBox(width: 4),
                AdminDeleteLink(onPressed: () => _delete(ref, context)),
              ],
            ),
          ),
          InkWell(
            onTap: open,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(44, 0, 12, 10),
              child: _LessonStatusGrid(lesson: lesson),
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
      ('План', (lesson.planEn ?? '').trim().isNotEmpty || (lesson.planRu ?? '').trim().isNotEmpty ? 'есть' : 'нет'),
      ('Фразы', '${lesson.graph?.nodes.where((n) => n.type == 'phrases').fold<int>(0, (s, n) => s + n.phrases.length) ?? 0}'),
    ];
    // Fixed row height rather than childAspectRatio (§ builder full-width
    // layout, 2026-09-02) — an aspect ratio derives height from width, so on
    // a wide screen the rows stretched into tall bands of empty space. These
    // are single-line label+value pairs; their height should never depend on
    // how wide the window is.
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisExtent: 22,
        mainAxisSpacing: 6,
        crossAxisSpacing: 12,
      ),
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

class _AddLessonRow extends ConsumerStatefulWidget {
  const _AddLessonRow({required this.courseId, this.modules = const []});
  final String courseId;
  final List<AdminModule> modules;

  @override
  ConsumerState<_AddLessonRow> createState() => _AddLessonRowState();
}

class _AddLessonRowState extends ConsumerState<_AddLessonRow> {
  final _title = TextEditingController();
  bool _busy = false;
  // '' = no module; null = not chosen yet (defaults to the last module).
  String? _moduleId;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _effectiveModuleId {
    if (_moduleId != null && (_moduleId!.isEmpty || widget.modules.any((m) => m.id == _moduleId))) return _moduleId!;
    return widget.modules.isEmpty ? '' : widget.modules.last.id;
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final moduleId = _effectiveModuleId;
      await ref.read(builderRepositoryProvider).addLesson(widget.courseId, title: _title.text.trim(), moduleId: moduleId.isEmpty ? null : moduleId);
      _title.clear();
      ref.invalidate(builderCourseProvider(widget.courseId));
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
        if (widget.modules.isNotEmpty) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _effectiveModuleId,
              isExpanded: true,
              decoration: adminInputDecoration(label: 'Модуль'),
              items: [
                for (final m in widget.modules) DropdownMenuItem(value: m.id, child: Text(m.title, overflow: TextOverflow.ellipsis)),
                const DropdownMenuItem(value: '', child: Text('Без модуля')),
              ],
              onChanged: (v) => setState(() => _moduleId = v ?? ''),
            ),
          ),
        ],
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


/// Creates (module == null) or renames a module: Russian title plus an
/// optional Tajik one (§ course modules, 2026-10-05).
Future<void> _editModule(BuildContext context, WidgetRef ref, String courseId, AdminModule? module) async {
  final title = TextEditingController(text: module?.title ?? '');
  final titleTg = TextEditingController(text: module?.titleTg ?? '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(module == null ? 'Новый модуль' : 'Модуль'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, autofocus: true, decoration: adminInputDecoration(label: 'Название (например, «Знакомство»)')),
            const SizedBox(height: 8),
            TextField(controller: titleTg, decoration: adminInputDecoration(label: 'Название на таджикском (необязательно)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), style: AdminButtonStyles.primary(), child: Text(module == null ? 'Создать' : 'Сохранить')),
      ],
    ),
  );
  final name = title.text.trim();
  final nameTg = titleTg.text.trim();
  title.dispose();
  titleTg.dispose();
  if (ok != true || name.isEmpty) return;
  try {
    final repo = ref.read(builderRepositoryProvider);
    if (module == null) {
      await repo.createModule(courseId, title: name, titleTg: nameTg.isEmpty ? null : nameTg);
    } else {
      await repo.updateModule(courseId, module.id, title: name, titleTg: nameTg);
    }
    ref.invalidate(builderCourseProvider(courseId));
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e, 'Не удалось сохранить модуль');
  }
}

class _ModuleHeader extends ConsumerWidget {
  const _ModuleHeader({required this.courseId, required this.course, required this.index});
  final String courseId;
  final AdminCourse course;
  final int index;

  AdminModule get _module => course.modules[index];

  Future<void> _move(BuildContext context, WidgetRef ref, int delta) async {
    final ids = course.modules.map((m) => m.id).toList();
    final j = index + delta;
    if (j < 0 || j >= ids.length) return;
    final tmp = ids[index];
    ids[index] = ids[j];
    ids[j] = tmp;
    try {
      await ref.read(builderRepositoryProvider).reorderModules(courseId, ids);
      ref.invalidate(builderCourseProvider(courseId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось изменить порядок модулей');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить модуль «${_module.title}»?',
      message: 'Уроки модуля не удалятся — они перейдут в «Без модуля».',
    );
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteModule(courseId, _module.id);
      ref.invalidate(builderCourseProvider(courseId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить модуль');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = _module;
    final count = course.lessons.where((l) => l.moduleId == m.id).length;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, index == 0 ? 4 : 16, 4, 8),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined, size: 20, color: AdminColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Модуль ${index + 1}. ${m.title}', style: AdminTypography.cardTitle),
                Text(
                  [if ((m.titleTg ?? '').isNotEmpty) m.titleTg!, '$count уроков'].join(' · '),
                  style: AdminTypography.caption,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Переименовать',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _editModule(context, ref, courseId, m),
          ),
          AdminReorderArrows(canMoveUp: index > 0, canMoveDown: index < course.modules.length - 1, onMove: (d) => _move(context, ref, d)),
          const SizedBox(width: 4),
          AdminDeleteLink(onPressed: () => _delete(context, ref)),
        ],
      ),
    );
  }
}
