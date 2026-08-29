import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/push/notification_settings_repository.dart';
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

    return Scaffold(
      backgroundColor: AdminColors.bg,
      appBar: AppBar(
        backgroundColor: AdminColors.card,
        foregroundColor: AdminColors.text,
        elevation: 0,
        title: const Text('Курсы', style: AdminTypography.pageTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: AdminMaxWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            AdminMetrics.cardGap,
            16,
            AdminMetrics.cardGap + bottomBarClearance(context),
          ),
          children: [
            AdminCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AdminMetrics.cardRadius),
                ),
                title: const Text(
                  'Немецкий с нуля',
                  style: AdminTypography.cardTitle,
                ),
                subtitle: Text(
                  '${legacyCount ?? "…"} уроков · основной курс из файлов',
                  style: AdminTypography.caption,
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AdminColors.textSecondary,
                ),
                onTap: () => context.go('/admin/courses/legacy'),
              ),
            ),
            const SizedBox(height: AdminMetrics.cardGap),
            const _NotificationSettingsCard(),
            const SizedBox(height: AdminMetrics.cardGap),
            const _CreateCourseCard(),
            const SizedBox(height: AdminMetrics.cardGap),
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

class _CourseRow extends ConsumerWidget {
  const _CourseRow({
    required this.course,
    required this.index,
    required this.total,
  });
  final AdminCourseSummary course;
  final int index;
  final int total;

  Future<void> _reorder(WidgetRef ref, BuildContext context, int delta) async {
    final list = ref.read(_coursesHubProvider).value;
    if (list == null) return;
    final ids = list.map((c) => c.id).toList();
    final j = index + delta;
    if (j < 0 || j >= ids.length) return;
    final tmp = ids[index];
    ids[index] = ids[j];
    ids[j] = tmp;
    try {
      await ref.read(builderRepositoryProvider).reorderCourses(ids);
      ref.invalidate(_coursesHubProvider);
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, e, 'Не удалось изменить порядок');
      }
    }
  }

  Future<void> _delete(WidgetRef ref, BuildContext context) async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить курс «${course.title}»?',
      message: 'Со всеми уроками и словами. Это действие необратимо.',
    );
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteCourse(course.id);
      ref.invalidate(_coursesHubProvider);
    } catch (e) {
      if (context.mounted) {
        showErrorSnack(context, e, 'Не удалось удалить курс');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverUrl = ref.read(apiClientProvider).assetUrl(course.coverUrl);
    final placeholder = Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AdminColors.blockBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Icon(
        Icons.image_not_supported_outlined,
        size: 16,
        color: AdminColors.textMuted,
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
                      width: 40,
                      height: 40,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AdminTypography.cardTitle,
                      ),
                      if (course.description.isNotEmpty)
                        Text(
                          course.description,
                          maxLines: 2,
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
                AdminReorderArrows(
                  canMoveUp: index > 0,
                  canMoveDown: index < total - 1,
                  onMove: (delta) => _reorder(ref, context, delta),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/admin/builder/${course.id}'),
                  style: AdminButtonStyles.text(),
                  child: const Text('Открыть'),
                ),
                const SizedBox(width: 4),
                AdminDeleteLink(onPressed: () => _delete(ref, context)),
              ],
            ),
          ],
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Автоматическая отправка уведомлений', style: AdminTypography.cardTitle),
                SizedBox(height: 2),
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
          const Text('Новый курс', style: AdminTypography.cardTitle),
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
          const Text(
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
