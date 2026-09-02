import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/push/notification_settings_repository.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import '../domain/taxonomy_domain.dart';
import 'widgets/level_picker.dart';

final _coursesHubProvider =
    FutureProvider.autoDispose<List<AdminCourseSummary>>(
      (ref) => ref.watch(builderRepositoryProvider).listCourses(),
    );
final _legacyLessonCountProvider = FutureProvider.autoDispose<int>(
  (ref) async =>
      (await ref.watch(profileRepositoryProvider).fetchLegacyLessons()).length,
);
final _autoSendOnNewLessonProvider = FutureProvider.autoDispose<bool>(
  (ref) => ref.watch(notificationSettingsRepositoryProvider).getAutoSendOnNewLesson(),
);

/// Language + Level lists, used only to group the (unchanged) course list
/// below into Язык → Уровень → Курс for display — the courses themselves,
/// their reorder/delete/create logic, and Course.position all stay exactly
/// as they already worked; this only changes which heading a course's
/// existing row renders under.
final _languagesProvider = FutureProvider.autoDispose<List<AdminLanguage>>(
  (ref) => ref.watch(builderRepositoryProvider).listLanguages(),
);
final _levelsProvider = FutureProvider.autoDispose<List<AdminLevel>>(
  (ref) => ref.watch(builderRepositoryProvider).listLevels(),
);

/// Mirrors AdminCoursesHubPage.tsx: the static legacy-course row (linking
/// to /admin/courses/legacy) plus every builder course, with reorder/
/// delete/create.
class AdminCoursesHubScreen extends ConsumerWidget {
  const AdminCoursesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(_coursesHubProvider);
    final languages = ref.watch(_languagesProvider).value ?? const [];
    final levels = ref.watch(_levelsProvider).value ?? const [];
    final legacyCount = ref.watch(_legacyLessonCountProvider).value;

    return BackGuard(
      fallbackPath: '/',
      // Admin/course-builder screens are a deliberately fixed light palette
      // (admin_tokens.dart) that doesn't follow the app's dark-mode toggle —
      // but that was only ever applied to the explicit AdminColors/
      // AdminTypography constants. A plain TextField with no explicit style
      // (e.g. the "Название" field below) still fell back to the AMBIENT
      // theme's default text color, which in dark mode is near-white —
      // invisible on AdminColors.card's hardcoded white fill (§ admin
      // light-theme fix, 2026-09-01, reported: white text on white field).
      // Forcing `lightTheme` here makes every unstyled default match the
      // fixed light palette this whole screen family already assumes.
      child: Theme(
        data: lightTheme,
        child: Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.card,
        foregroundColor: AdminColors.text,
        elevation: 0,
        title: Text('Курсы', style: AdminTypography.pageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        // §9 of the course-builder redesign, 2026-09-01: course list moves
        // to the top of the page, "+ Новый курс" becomes a header button
        // (form opens in a bottom sheet) and notification settings move
        // into this "⋯" menu — neither is content the teacher scans past
        // every visit.
        actions: [
          TextButton.icon(
            onPressed: () => _openCreateCourseSheet(context),
            style: AdminButtonStyles.text(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Новый курс'),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _openSettingsSheet(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AdminMaxWidth(
        maxWidth: AdminMetrics.maxListWidth,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            AdminMetrics.cardGap,
            16,
            AdminMetrics.cardGap + bottomBarClearance(context),
          ),
          children: [
            // The old file-based course stays the very first row of the
            // list, styled identically to a real course row — no separate
            // frame of its own (§9: "остаётся первой карточкой списка ...
            // без отдельной рамки").
            _LegacyCourseRow(legacyCount: legacyCount),
            const SizedBox(height: 8),
            courses.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, st) => Text(
                'Не удалось загрузить курсы: $err',
                style: AdminTypography.body,
              ),
              data: (list) => Column(
                children: _groupedCourseWidgets(list, languages, levels),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  void _openCreateCourseSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AdminColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      // A bare Padding/Column child still gets stretched to the sheet's
      // full max-height slot by showModalBottomSheet's own layout — Wrap is
      // the standard fix, since RenderWrap always sizes to its children
      // regardless of how loose the incoming constraints are.
      //
      // showModalBottomSheet attaches its content to the Navigator's
      // Overlay, which sits OUTSIDE this screen's local `Theme(data:
      // lightTheme, ...)` wrapper — so an unstyled TextField inside it falls
      // back to the ambient (possibly dark) theme's text color, same bug as
      // admin_courses_hub_screen.dart's own §admin light-theme fix, just in
      // a spot that wrapper doesn't reach. Forcing lightTheme again here
      // fixes it for this sheet specifically.
      builder: (sheetContext) => Theme(
        data: lightTheme,
        child: Wrap(
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: const _CreateCourseCard(),
            ),
          ],
        ),
      ),
    );
  }

  void _openSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AdminColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      // Same forced-lightTheme fix as _openCreateCourseSheet above.
      builder: (sheetContext) => Theme(
        data: lightTheme,
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: const _NotificationSettingsCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same visual treatment as [_CourseRow] (§9: "без отдельной рамки" — no
/// distinct card style of its own), just pointed at the static file-based
/// course instead of a real Course row, and with no reorder/delete (its
/// position is always first, and it can't be deleted from here).
class _LegacyCourseRow extends StatelessWidget {
  const _LegacyCourseRow({required this.legacyCount});
  final int? legacyCount;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: () => context.go('/admin/courses/legacy'),
        child: Row(
          children: [
            Container(
              width: AdminMetrics.courseCoverWidth,
              height: AdminMetrics.courseCoverHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(6)),
              child: const Icon(Icons.folder_outlined, size: 20, color: AdminColors.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Немецкий с нуля', maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminTypography.cardTitle),
                  Text('основной курс из файлов', maxLines: 1, overflow: TextOverflow.ellipsis, style: AdminTypography.caption),
                  const SizedBox(height: 2),
                  Text('${legacyCount ?? "…"} уроков', style: AdminTypography.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AdminColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Groups the (unmodified) course list into Язык → Уровень → Курс for
/// display, per §2/§4 of the level-picker request — a course with no
/// levelId (every course created before this feature existed) renders
/// exactly as before, under a plain "Без уровня" heading, so nothing that
/// already worked changes for existing courses that haven't been assigned
/// a level yet. Reorder arrows still act on the full, flat course list —
/// Course.position was always global, not per-level, and stays that way.
List<Widget> _groupedCourseWidgets(
  List<AdminCourseSummary> courses,
  List<AdminLanguage> languages,
  List<AdminLevel> levels,
) {
  final indexByCourseId = {for (var i = 0; i < courses.length; i++) courses[i].id: i};
  final levelById = {for (final l in levels) l.id: l};
  final coursesByLevelId = <String, List<AdminCourseSummary>>{};
  final unleveled = <AdminCourseSummary>[];
  for (final c in courses) {
    if (c.levelId != null && levelById.containsKey(c.levelId)) {
      coursesByLevelId.putIfAbsent(c.levelId!, () => []).add(c);
    } else {
      unleveled.add(c);
    }
  }

  Widget courseRow(AdminCourseSummary c) => _CourseRow(course: c, index: indexByCourseId[c.id]!, total: courses.length);

  final widgets = <Widget>[];
  for (final language in languages) {
    final languageLevels = levels.where((l) => l.languageId == language.id).toList()
      ..sort((a, b) => a.position.compareTo(b.position));
    final levelsWithCourses = languageLevels.where((l) => coursesByLevelId.containsKey(l.id)).toList();
    if (levelsWithCourses.isEmpty) continue;

    widgets.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(language.name, style: AdminTypography.cardTitle)));
    for (final level in levelsWithCourses) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 0, 6),
          child: Text('${level.code} — ${level.name}', style: AdminTypography.stageTitle.copyWith(color: AdminColors.accent)),
        ),
      );
      for (final course in coursesByLevelId[level.id]!) {
        widgets.add(Padding(padding: const EdgeInsets.only(left: 16), child: courseRow(course)));
      }
    }
    widgets.add(const SizedBox(height: AdminMetrics.cardGap));
  }

  if (unleveled.isNotEmpty) {
    if (widgets.isNotEmpty) {
      widgets.add(Padding(padding: const EdgeInsets.only(bottom: 6), child: Text('Без уровня', style: AdminTypography.cardTitle)));
    }
    for (final course in unleveled) {
      widgets.add(courseRow(course));
    }
  }

  return widgets;
}

class _CourseRow extends ConsumerStatefulWidget {
  const _CourseRow({
    required this.course,
    required this.index,
    required this.total,
  });
  final AdminCourseSummary course;
  final int index;
  final int total;

  @override
  ConsumerState<_CourseRow> createState() => _CourseRowState();
}

class _CourseRowState extends ConsumerState<_CourseRow> {
  // Reorder arrows show only on hover/long-press (§9 of the redesign,
  // 2026-09-01: "чтобы не шуметь") — long-press pins them visible for
  // touch, where there's no hover at all.
  bool _hovering = false;
  bool _pinned = false;

  Future<void> _reorder(int delta) async {
    final list = ref.read(_coursesHubProvider).value;
    if (list == null) return;
    final ids = list.map((c) => c.id).toList();
    final j = widget.index + delta;
    if (j < 0 || j >= ids.length) return;
    final tmp = ids[widget.index];
    ids[widget.index] = ids[j];
    ids[j] = tmp;
    try {
      await ref.read(builderRepositoryProvider).reorderCourses(ids);
      ref.invalidate(_coursesHubProvider);
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e, 'Не удалось изменить порядок');
      }
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить курс «${widget.course.title}»?',
      message: 'Со всеми уроками и словами. Это действие необратимо.',
    );
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteCourse(widget.course.id);
      ref.invalidate(_coursesHubProvider);
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e, 'Не удалось удалить курс');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = widget.course;
    final coverUrl = ref.read(apiClientProvider).assetUrl(course.coverUrl);
    final placeholder = Container(
      width: AdminMetrics.courseCoverWidth,
      height: AdminMetrics.courseCoverHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AdminColors.blockBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 18,
        color: AdminColors.textMuted,
      ),
    );
    final arrowsVisible = _hovering || _pinned;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onLongPress: () => setState(() => _pinned = !_pinned),
          child: AdminCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (coverUrl.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          coverUrl,
                          width: AdminMetrics.courseCoverWidth,
                          height: AdminMetrics.courseCoverHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => placeholder,
                        ),
                      )
                    else
                      placeholder,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AdminTypography.cardTitle,
                          ),
                          if (course.description.isNotEmpty)
                            Text(
                              course.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AdminTypography.caption,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            '${course.lessonCount} уроков · ${course.wordCount} слов · ${course.questionCount} вопросов',
                            style: AdminTypography.caption,
                          ),
                        ],
                      ),
                    ),
                    AdminStatusBadge(published: course.status == 'PUBLISHED'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    AnimatedOpacity(
                      duration: AdminMetrics.transition,
                      opacity: arrowsVisible ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !arrowsVisible,
                        child: AdminReorderArrows(
                          canMoveUp: widget.index > 0,
                          canMoveDown: widget.index < widget.total - 1,
                          onMove: _reorder,
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => context.go('/admin/builder/${course.id}'),
                      style: AdminButtonStyles.text(),
                      child: const Text('Открыть'),
                    ),
                    const SizedBox(width: 4),
                    AdminDeleteLink(onPressed: _delete),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Generic push mechanism (§ any future event type reuses the same
/// send path), only "lesson_created" wired up today: ON sends
/// automatically when a lesson is added to an already-published course;
/// OFF leaves it to the "Отправить уведомление" button on the lesson itself.
class _NotificationSettingsCard extends ConsumerStatefulWidget {
  const _NotificationSettingsCard();
  @override
  ConsumerState<_NotificationSettingsCard> createState() => _NotificationSettingsCardState();
}

class _NotificationSettingsCardState extends ConsumerState<_NotificationSettingsCard> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await ref.read(notificationSettingsRepositoryProvider).setAutoSendOnNewLesson(value);
      ref.invalidate(_autoSendOnNewLessonProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить настройку');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final autoSend = ref.watch(_autoSendOnNewLessonProvider);
    return AdminCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Автоматическая отправка уведомлений', style: AdminTypography.cardTitle),
                const SizedBox(height: 2),
                Text(
                  'Когда включено: уведомление о новом уроке уходит сразу после его создания (если курс уже опубликован). '
                  'Когда выключено: уведомление можно отправить вручную кнопкой у урока.',
                  style: AdminTypography.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          autoSend.when(
            loading: () => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            error: (err, st) => const Icon(Icons.error_outline, color: AdminColors.danger),
            data: (value) => Switch(
              value: value,
              onChanged: _busy ? null : _toggle,
              activeThumbColor: AdminColors.accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateCourseCard extends ConsumerStatefulWidget {
  const _CreateCourseCard();
  @override
  ConsumerState<_CreateCourseCard> createState() => _CreateCourseCardState();
}

class _CreateCourseCardState extends ConsumerState<_CreateCourseCard> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  String? _levelId;
  bool _busy = false;
  String? _error;
  // Bumped after a successful create so LevelPickerField (which loads its
  // own state once in initState) gets a fresh key and actually resets,
  // instead of silently keeping the just-submitted language/level selected.
  int _formGeneration = 0;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(builderRepositoryProvider)
          .createCourse(
            title: _title.text.trim(),
            description: _description.text.trim().isEmpty
                ? null
                : _description.text.trim(),
            levelId: _levelId,
          );
      _title.clear();
      _description.clear();
      setState(() {
        _levelId = null;
        _formGeneration++;
      });
      ref.invalidate(_coursesHubProvider);
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось создать курс'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Новый курс', style: AdminTypography.cardTitle),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _title,
            decoration: adminInputDecoration(label: 'Название'),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          LevelPickerField(
            key: ValueKey(_formGeneration),
            initialLevelId: _levelId,
            onChanged: (id) => setState(() => _levelId = id),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _description,
            maxLines: 3,
            decoration: adminInputDecoration(label: 'Описание (необязательно)'),
          ),
          const SizedBox(height: 6),
          Text(
            'Новый курс создаётся пустым. Ничего не копируется из других курсов — уроки, слова и вопросы вы добавляете вручную.',
            style: AdminTypography.caption,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AdminColors.danger, fontSize: 12),
              ),
            ),
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _submit,
              style: AdminButtonStyles.primary(),
              child: Text(_busy ? 'Создаём…' : 'Создать курс'),
            ),
          ),
        ],
      ),
    );
  }
}
