import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../data/courses_repository.dart';
import 'courses_overview.dart';
import 'widgets/lesson_grid_card.dart';

/// Mirrors CoursesPage.tsx + Home.tsx's lesson grid, collapsed into one
/// screen — see courses_overview.dart's doc comment for why.
class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(coursesOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Курсы')),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Не удалось загрузить курсы: $err')),
        data: (data) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(coursesOverviewProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.legacyLessons.isNotEmpty) ...[
                Text('Немецкий с нуля', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (var i = 0; i < data.legacyLessons.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: LessonGridCard(
                      index: i,
                      lesson: data.legacyLessons[i],
                      onTap: () => context.go('/lesson/${data.legacyLessons[i].lessonId}/${data.legacyLessons[i].targetStage.name}'),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              if (data.builderCourses.isNotEmpty) ...[
                Text('Другие курсы', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                for (final course in data.builderCourses)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BuilderCourseCard(course: course, onTap: () => context.go('/courses/${course.id}')),
                  ),
              ],
              if (data.legacyLessons.isEmpty && data.builderCourses.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Курсы не найдены'))),
            ],
          ),
        ),
      ),
    );
  }
}

class _BuilderCourseCard extends ConsumerWidget {
  const _BuilderCourseCard({required this.course, required this.onTap});

  final BuilderCourseSummary course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverUrl = ref.read(apiClientProvider).assetUrl(course.coverUrl);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (coverUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(coverUrl, width: 56, height: 56, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(course.title, style: Theme.of(context).textTheme.titleMedium),
                    Text(course.description?.isNotEmpty == true ? course.description! : '${course.lessonCount} уроков'),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
