import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../profile/data/profile_repository.dart';
import '../data/legacy_admin_repository.dart';
import '../../course_builder/domain/builder_domain.dart';

class _Row {
  const _Row({
    required this.lessonId,
    required this.title,
    required this.lesson,
  });
  final String lessonId;
  final String title;
  final AdminLesson lesson;
}

final _legacyLessonsAdminProvider = FutureProvider.autoDispose<List<_Row>>((
  ref,
) async {
  final list = await ref.watch(profileRepositoryProvider).fetchLegacyLessons();
  final repo = ref.watch(legacyAdminRepositoryProvider);
  final rows = <_Row>[];
  for (final l in list) {
    final lesson = await repo.getContent(l.lessonId, l.title);
    rows.add(_Row(lessonId: l.lessonId, title: l.title, lesson: lesson));
  }
  return rows;
});

/// Mirrors AdminLegacyLessonsPage.tsx.
class AdminLegacyLessonsScreen extends ConsumerWidget {
  const AdminLegacyLessonsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(_legacyLessonsAdminProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Немецкий с нуля'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin/courses'),
        ),
      ),
      body: rows.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) =>
            Center(child: Text('Не удалось загрузить уроки: $err')),
        data: (list) {
          if (list.isEmpty) {
            return const Center(child: Text('Уроки не найдены.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final row in list) _LessonCard(row: row)],
          );
        },
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.row});
  final _Row row;

  int _blockQuestionCount(AdminLesson lesson, String stage) =>
      lesson.blocksFor(stage).fold(0, (sum, b) => sum + b.questions.length);

  @override
  Widget build(BuildContext context) {
    final lesson = row.lesson;
    final withAudio = lesson.vocabulary.where((w) => w.audioUrl != null).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => context.go('/admin/lessons/${row.lessonId}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  _Chip(
                    'Материал: ${lesson.materialText.isNotEmpty ? "есть" : "нет"}',
                  ),
                  _Chip('Видео: ${lesson.videoUrl != null ? "есть" : "нет"}'),
                  _Chip(
                    'Аудиоурок: ${lesson.audioUrl != null ? "есть" : "нет"}',
                  ),
                  _Chip(
                    'Словарь: ${lesson.vocabulary.length} слов · озвучено $withAudio',
                  ),
                  _Chip(
                    'Мини-тест: ${_countLabel(_blockQuestionCount(lesson, "minitest"))}',
                  ),
                  _Chip(
                    'Практика: ${_countLabel(_blockQuestionCount(lesson, "practice"))}',
                  ),
                  _Chip(
                    'Закрепление: ${_countLabel(_blockQuestionCount(lesson, "review"))}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _countLabel(int n) => n > 0 ? '$n своих вопросов' : 'генерируется';
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    label: Text(label, style: const TextStyle(fontSize: 12)),
    visualDensity: VisualDensity.compact,
  );
}
