import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/back_guard.dart';
import '../../admin/admin_tokens.dart';
import '../../admin/admin_widgets.dart';
import '../../admin/widgets/admin_feedback.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/video_lessons_repository.dart';

final _videoLessonsProvider = FutureProvider.autoDispose.family<List<VideoLessonData>, String>(
  (ref, courseId) => ref.watch(videoLessonsRepositoryProvider).list(courseId),
);

/// «Видеоуроки» of one course: the list, plus create / open / delete.
class VideoLessonsListScreen extends ConsumerWidget {
  const VideoLessonsListScreen({super.key, required this.courseId});
  final String courseId;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: 'Видеоурок');
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый видеоурок'),
        content: TextField(controller: controller, autofocus: true, decoration: adminInputDecoration(label: 'Название'), onSubmitted: (v) => Navigator.pop(ctx, v)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), style: AdminButtonStyles.primary(), child: const Text('Создать')),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.trim().isEmpty) return;
    try {
      final v = await ref.read(videoLessonsRepositoryProvider).create(courseId, title.trim());
      ref.invalidate(_videoLessonsProvider(courseId));
      if (context.mounted) context.go('/admin/builder/${Uri.encodeComponent(courseId)}/videos/${v.id}');
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось создать видеоурок');
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, VideoLessonData v) async {
    final ok = await confirmDialog(context, title: 'Удалить видеоурок «${v.title}»?', confirmLabel: 'Удалить');
    if (!ok) return;
    try {
      await ref.read(videoLessonsRepositoryProvider).delete(courseId, v.id);
      ref.invalidate(_videoLessonsProvider(courseId));
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_videoLessonsProvider(courseId));
    final back = '/admin/builder/${Uri.encodeComponent(courseId)}';
    return BackGuard(
      fallbackPath: back,
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text('Видеоуроки', style: AdminTypography.pageTitle),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(back)),
            actions: [
              TextButton.icon(
                onPressed: () => _create(context, ref),
                style: AdminButtonStyles.text(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Новый видеоурок'),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: AdminMaxWidth(
            maxWidth: AdminMetrics.maxListWidth,
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(adminErrorMessage(e, 'Не удалось загрузить видеоуроки'), style: AdminTypography.body)),
              data: (items) => items.isEmpty
                  ? Center(child: Text('Видеоуроков пока нет. Нажмите «Новый видеоурок».', style: AdminTypography.body))
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16, AdminMetrics.cardGap, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
                      children: [
                        for (final v in items)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: AdminCard(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.smart_display_outlined),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(v.title, style: AdminTypography.cardTitle),
                                        Text(_statusLabel(v), style: AdminTypography.caption),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => context.go('/admin/builder/${Uri.encodeComponent(courseId)}/videos/${v.id}'),
                                    style: AdminButtonStyles.text(),
                                    child: const Text('Открыть'),
                                  ),
                                  AdminDeleteLink(onPressed: () => _delete(context, ref, v)),
                                ],
                              ),
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

String _statusLabel(VideoLessonData v) {
  final source = v.sourceType == 'text' ? 'текст' : 'аудио';
  final seconds = v.durationMs == null ? '' : ' · ${(v.durationMs! / 1000).toStringAsFixed(1)} с';
  return switch (v.status) {
    'ready' => 'Готово · $source$seconds',
    'error' => 'Ошибка: ${v.error ?? 'не удалось обработать'}',
    _ => 'Нет речи — загрузите аудио или введите текст',
  };
}
