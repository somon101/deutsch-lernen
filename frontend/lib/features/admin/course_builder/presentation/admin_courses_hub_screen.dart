import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';

final _coursesHubProvider =
    FutureProvider.autoDispose<List<AdminCourseSummary>>(
      (ref) => ref.watch(builderRepositoryProvider).listCourses(),
    );
final _legacyLessonCountProvider = FutureProvider.autoDispose<int>(
  (ref) async =>
      (await ref.watch(profileRepositoryProvider).fetchLegacyLessons()).length,
);

/// Mirrors AdminCoursesHubPage.tsx: the static legacy-course row (linking
/// to /admin/courses/legacy) plus every builder course, with reorder/
/// delete/create.
class AdminCoursesHubScreen extends ConsumerWidget {
  const AdminCoursesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(_coursesHubProvider);
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
            const _CreateCourseCard(),
            const SizedBox(height: AdminMetrics.cardGap),
            courses.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, st) => Text(
                'Не удалось загрузить курсы: $err',
                style: AdminTypography.body,
              ),
              data: (list) => Column(
                children: [
                  for (var i = 0; i < list.length; i++)
                    _CourseRow(course: list[i], index: i, total: list.length),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
      if (context.mounted)
        showErrorSnack(context, e, 'Не удалось изменить порядок');
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
      if (context.mounted)
        showErrorSnack(context, e, 'Не удалось удалить курс');
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

class _CreateCourseCard extends ConsumerStatefulWidget {
  const _CreateCourseCard();
  @override
  ConsumerState<_CreateCourseCard> createState() => _CreateCourseCardState();
}

class _CreateCourseCardState extends ConsumerState<_CreateCourseCard> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

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
          );
      _title.clear();
      _description.clear();
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
