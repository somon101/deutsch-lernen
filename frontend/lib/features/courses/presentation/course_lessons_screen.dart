import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'courses_overview.dart';
import 'widgets/lesson_grid_card.dart';

/// Mirrors CourseLessonsPage.tsx: one published builder course's lesson
/// grid, same card pattern as CoursesScreen's legacy section.
class CourseLessonsScreen extends ConsumerWidget {
  const CourseLessonsScreen({super.key, required this.courseId});

  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(courseLessonsProvider(courseId));

    return Scaffold(
      appBar: AppBar(title: Text(data.value?.title ?? 'Курс')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Курс не найден')),
        data: (course) {
          if (course.lessons.isEmpty) {
            return const Center(child: Text('Уроков пока нет — администратор ещё наполняет этот курс.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (course.description?.isNotEmpty == true) ...[
                Text(course.description!, style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 16),
              ],
              for (var i = 0; i < course.lessons.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LessonGridCard(
                    index: i,
                    lesson: course.lessons[i],
                    onTap: () => context.go('/courses/$courseId/lesson/${course.lessons[i].lessonId}/${course.lessons[i].targetStage.name}'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
