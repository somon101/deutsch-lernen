import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../profile/data/profile_repository.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';

final _coursesHubProvider = FutureProvider.autoDispose<List<AdminCourseSummary>>((ref) => ref.watch(builderRepositoryProvider).listCourses());
final _legacyLessonCountProvider = FutureProvider.autoDispose<int>((ref) async => (await ref.watch(profileRepositoryProvider).fetchLegacyLessons()).length);

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
      appBar: AppBar(
        title: const Text('Курсы'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarClearance(context)),
        children: [
          Card(
            child: ListTile(
              title: const Text('Немецкий с нуля'),
              subtitle: Text('${legacyCount ?? "…"} уроков · основной курс из файлов'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/admin/courses/legacy'),
            ),
          ),
          const SizedBox(height: 16),
          const _CreateCourseCard(),
          const SizedBox(height: 16),
          courses.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => Text('Не удалось загрузить курсы: $err'),
            data: (list) => Column(
              children: [for (var i = 0; i < list.length; i++) _CourseRow(course: list[i], index: i, total: list.length)],
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseRow extends ConsumerWidget {
  const _CourseRow({required this.course, required this.index, required this.total});
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
      if (context.mounted) showErrorSnack(context, e, 'Не удалось изменить порядок');
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
      if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить курс');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverUrl = ref.read(apiClientProvider).assetUrl(course.coverUrl);
    final placeholder = Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(6)),
      child: const Icon(Icons.image_not_supported_outlined, size: 18),
    );
    // Reorder/open/delete used to share one Row with the thumbnail and text
    // — six elements wide enough that on a narrow phone the title/subtitle
    // got squeezed. Splitting into a content row (thumbnail + text) and a
    // separate actions row below gives each its own full-width line
    // regardless of screen size, rather than a breakpoint hack.
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
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
                    child: Image.network(coverUrl, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => placeholder),
                  )
                else
                  placeholder,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(course.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                      if (course.description.isNotEmpty) Text(course.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                      Text('${course.lessonCount} уроков · ${course.wordCount} слов · ${course.questionCount} вопросов', style: Theme.of(context).textTheme.bodySmall),
                      Text(course.status == 'PUBLISHED' ? 'Опубликован' : 'Черновик', style: TextStyle(color: course.status == 'PUBLISHED' ? Colors.green : Colors.orange, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  visualDensity: VisualDensity.compact,
                  onPressed: index > 0 ? () => _reorder(ref, context, -1) : null,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  visualDensity: VisualDensity.compact,
                  onPressed: index < total - 1 ? () => _reorder(ref, context, 1) : null,
                ),
                const Spacer(),
                TextButton(onPressed: () => context.go('/admin/builder/${course.id}'), child: const Text('Открыть')),
                IconButton(icon: const Icon(Icons.delete_outline), visualDensity: VisualDensity.compact, onPressed: () => _delete(ref, context)),
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
      await ref.read(builderRepositoryProvider).createCourse(title: _title.text.trim(), description: _description.text.trim().isEmpty ? null : _description.text.trim());
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Новый курс', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: _title, decoration: const InputDecoration(labelText: 'Название')),
            const SizedBox(height: 8),
            TextField(controller: _description, maxLines: 3, decoration: const InputDecoration(labelText: 'Описание (необязательно)')),
            const SizedBox(height: 4),
            const Text(
              'Новый курс создаётся пустым. Ничего не копируется из других курсов — уроки, слова и вопросы вы добавляете вручную.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Создаём…' : 'Создать курс')),
            ),
          ],
        ),
      ),
    );
  }
}
