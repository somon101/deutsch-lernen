import 'package:flutter/material.dart';

import '../courses_overview.dart';

/// Mirrors the .lesson-card styling shared by Home.tsx/CourseLessonsPage.tsx
/// — a badge, title, word count, progress bar, and a status line that's
/// either "✓ Урок завершён", "Продолжить" or "Начать урок".
class LessonGridCard extends StatelessWidget {
  const LessonGridCard({super.key, required this.index, required this.lesson, required this.onTap});

  final int index;
  final LessonCard lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(radius: 14, child: Text('${index + 1}')),
                  const SizedBox(width: 10),
                  Expanded(child: Text(lesson.title, style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: 8),
              Text('${lesson.vocabularyCount} слов', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(value: lesson.ratio, minHeight: 6),
              ),
              const SizedBox(height: 6),
              Text(
                lesson.completed ? '✓ Урок завершён' : (lesson.ratio > 0 ? 'Продолжить' : 'Начать урок'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: lesson.completed ? Colors.green : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
