import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/locale/content_locale.dart';
import '../../../../core/locale/locale_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../shell/presentation/graph_sidebar_controls.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/builder_repository.dart';
import '../domain/builder_domain.dart';
import '../domain/taxonomy_domain.dart';
import 'builder_course_edit_screen.dart';
import 'widgets/lesson_editor_panel.dart';
import 'widgets/lesson_graph_editor.dart';

final _levelsForLanguageProvider = FutureProvider.autoDispose<List<AdminLevel>>(
  (ref) => ref.watch(builderRepositoryProvider).listLevels(),
);

/// One lesson's editor, on its own screen (§9 of the course-builder
/// redesign, 2026-09-01: "разворот открывает не аккордеон, а переход на
/// экран урока с рельсом") — the same LessonEditorPanel the legacy-lesson
/// screen (AdminLessonEditScreen) already uses, reached via
/// BuilderCourseEditScreen's lesson list instead of expanding in place.
class BuilderLessonEditScreen extends ConsumerWidget {
  const BuilderLessonEditScreen({super.key, required this.courseId, required this.lessonId});

  final String courseId;
  final String lessonId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(builderCourseProvider(courseId));
    void reload() => ref.invalidate(builderCourseProvider(courseId));
    final lesson = course.value?.lessons.where((l) => l.id == lessonId).cast<AdminLesson?>().firstWhere((l) => l != null, orElse: () => null);
    // Course.levelId → Level.languageId (§ topic-language fix, 2026-09-01)
    // — MaterialBlockEditor needs a real Language.id to create topics
    // against; null (level not picked, or still loading) disables that
    // instead of guessing.
    final levelId = course.value?.levelId;
    final levels = ref.watch(_levelsForLanguageProvider).value;
    final languageId = levelId == null || levels == null
        ? null
        : levels.where((l) => l.id == levelId).map((l) => l.languageId).cast<String?>().firstWhere((_) => true, orElse: () => null);

    return BackGuard(
      fallbackPath: '/admin/builder/$courseId',
      // Same fixed-light-palette fix as the other admin screens (§ admin
      // light-theme fix, 2026-09-01).
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text(lesson?.title ?? 'Урок', style: AdminTypography.pageTitle),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                // Same explicit clear as _switchToLinear/_exit below (§
                // sidebar-stuck-after-exit fix, 2026-09-04) — this button
                // navigates away from the graph editor exactly like
                // LessonGraphEditor's own "Выйти" does, but through a
                // separate handler that never calls that widget's _exit(),
                // so it needs its own copy of the same defensive clear.
                try {
                  ref.read(graphSidebarActionsProvider.notifier).state = null;
                } catch (_) {}
                final nav = Navigator.of(context);
                if (nav.canPop()) {
                  nav.pop();
                } else {
                  context.go('/admin/builder/$courseId');
                }
              },
            ),
          ),
          body: course.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, st) => Center(
              child: Text('Не удалось загрузить урок: $err', style: AdminTypography.body),
            ),
            data: (c) {
              if (lesson == null) {
                return Center(child: Text('Урок не найден', style: AdminTypography.body));
              }
              // Deliberately no AdminMaxWidth here (§ builder full-width
              // layout, 2026-09-02) — the rail is a fixed 220px and the
              // working area takes everything else, so a wide monitor
              // actually buys the teacher room to edit rather than empty
              // margins.
              //
              // A Column, not a ListView: the header below is pinned and the
              // panel does its own scrolling, so that scrolling a long word
              // list never carries the lesson header and the step rail off
              // screen with it (§ pinned header + independent scroll,
              // 2026-09-02).
              // A lesson with a real graph (§ lesson graph, 2026-09-03 —
              // `lesson.graph != null`, set once a teacher explicitly
              // converts it) gets the new free-form canvas; every other
              // lesson keeps today's exact fixed 8-step rail, byte-for-byte
              // unchanged, with just a "Перевести в граф" entry point added.
              return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: _LessonContentView(
                    key: ValueKey(lesson.id),
                    courseId: courseId,
                    lesson: lesson,
                    languageId: languageId,
                    onReload: reload,
                  ),
                );
            },
          ),
        ),
      ),
    );
  }
}

/// Chooses between the graph and the old rail for one lesson, and — for a
/// converted lesson — owns which of the two is currently shown
/// (§ graph/rail toggle, 2026-09-03).
///
/// An unconverted lesson (`lesson.graph == null`) has only ever had the
/// rail, so it renders unchanged: no toggle, no wrapping, full editing,
/// exactly as before this widget existed.
///
/// A converted lesson gets both views, but NOT as two equally-live editors.
/// Video/audio/material content forks the moment a graph node's own file
/// diverges from the pre-conversion lesson (LessonNode.mediaUrl is a
/// separate field from CourseLesson.videoUrl/audioUrl by design — see
/// LessonNode's own docstring — and a graph can hold more Material rows
/// than the rail's single "Материал" tab can show). Editing through the
/// rail after that would silently widen that fork rather than reveal it, so
/// the rail is READ-ONLY once a graph exists: wrapped in [IgnorePointer]
/// rather than trusting every add/edit/delete button across
/// LessonEditorPanel and its children (VocabularyEditor/
/// MaterialBlockEditor/MediaEditor/BlockEditor) to individually respect a
/// read-only flag none of them were built with. The graph stays the one
/// place that writes.
class _LessonContentView extends ConsumerStatefulWidget {
  const _LessonContentView({super.key, required this.courseId, required this.lesson, required this.languageId, required this.onReload});

  final String courseId;
  final AdminLesson lesson;
  final String? languageId;
  final VoidCallback onReload;

  @override
  ConsumerState<_LessonContentView> createState() => _LessonContentViewState();
}

class _LessonContentViewState extends ConsumerState<_LessonContentView> {
  bool _showLinearView = false;

  // Belt-and-suspenders alongside LessonGraphEditor's own dispose() (§
  // graph editor layout, 2026-09-04 verification finding: the sidebar's
  // graph tools were observed still showing after switching to this exact
  // tab) — this swap removes LessonGraphEditor from the tree via a plain
  // setState, not a route change, so its dispose() SHOULD already clear
  // this; clearing it here too costs nothing and closes the gap either way.
  void _switchToLinear() {
    // Best-effort — see LessonGraphEditor's own _clearSidebar for why a
    // disposal-timing exception here is swallowed, not surfaced.
    try {
      ref.read(graphSidebarActionsProvider.notifier).state = null;
    } catch (_) {}
    setState(() => _showLinearView = true);
  }

  @override
  Widget build(BuildContext context) {
    final graph = widget.lesson.graph;

    final panel = LessonEditorPanel(
      courseId: widget.courseId,
      lesson: widget.lesson,
      languageId: widget.languageId,
      scrollBottomInset: bottomBarClearance(context),
      libraryLoader: (kind) => ref.read(builderRepositoryProvider).listMediaLibrary(kind),
      onUploadMedia: (kind, bytes, filename) async {
        try {
          await ref.read(builderRepositoryProvider).uploadLessonMedia(widget.courseId, widget.lesson.id, kind: kind, bytes: bytes, filename: filename);
          widget.onReload();
          if (context.mounted) showSuccessSnack(context);
        } catch (e) {
          if (context.mounted) showErrorSnack(context, e, 'Не удалось загрузить файл');
        }
      },
      onRemoveMedia: (kind) async {
        try {
          await ref.read(builderRepositoryProvider).removeLessonMedia(widget.courseId, widget.lesson.id, kind);
          widget.onReload();
        } catch (e) {
          if (context.mounted) showErrorSnack(context, e, 'Не удалось удалить файл');
        }
      },
      onReuseMedia: (kind, url) async {
        try {
          await ref.read(builderRepositoryProvider).reuseLessonMedia(widget.courseId, widget.lesson.id, kind, url);
          widget.onReload();
        } catch (e) {
          if (context.mounted) showErrorSnack(context, e, 'Не удалось выбрать файл');
        }
      },
      onReload: widget.onReload,
    );

    // The lesson-name card (+ "Перевести в граф" for an unconverted lesson)
    // stays inline here exactly as before UNLESS the graph canvas itself is
    // the active view (§ graph editor layout, 2026-09-04) — in that one
    // case LessonGraphEditor shows the exact same LessonNameCard instead,
    // in a sidebar-triggered dialog, to give the canvas the screen. Linear
    // view and an unconverted lesson are both untouched, byte-for-byte.
    final showNameCardInline = graph == null || _showLinearView;
    final nameCard = showNameCardInline
        ? Padding(
            padding: const EdgeInsets.only(bottom: AdminMetrics.fieldGap),
            child: AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LessonNameCard(courseId: widget.courseId, lesson: widget.lesson),
                  if (graph == null) ...[
                    const SizedBox(height: AdminMetrics.fieldGap),
                    _ConvertToGraphRow(courseId: widget.courseId, lesson: widget.lesson, onDone: widget.onReload),
                  ],
                ],
              ),
            ),
          )
        : null;

    if (graph == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nameCard!, Expanded(child: panel)]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?nameCard,
        Row(
          children: [
            _ViewTab(label: 'Граф', selected: !_showLinearView, onTap: () => setState(() => _showLinearView = false)),
            const SizedBox(width: 8),
            _ViewTab(label: 'Линейный (просмотр)', selected: _showLinearView, onTap: _switchToLinear),
          ],
        ),
        if (_showLinearView) ...[
          const SizedBox(height: AdminMetrics.fieldGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 16, color: AdminColors.warn),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Только просмотр. Урок переведён в граф — редактируется там. '
                  'Видео, аудио и лишние блоки материала могут отличаться от графа: '
                  'у графа для них своё, отдельное хранилище.',
                  style: AdminTypography.caption.copyWith(color: AdminColors.warn),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AdminMetrics.fieldGap),
        Expanded(
          child: _showLinearView
              ? IgnorePointer(child: panel)
              : LessonGraphEditor(courseId: widget.courseId, lesson: widget.lesson, languageId: widget.languageId, onReload: widget.onReload),
        ),
      ],
    );
  }
}

class _ViewTab extends StatelessWidget {
  const _ViewTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `onPressed: onTap` even while selected, deliberately not null: a
    // FilledButton with a null onPressed renders in its DISABLED colors
    // (AdminButtonStyles.primary()'s 40%-alpha accent), which would make
    // the active tab look the faded one — backwards for a selector. Tapping
    // the already-selected tab just re-sets the same value, harmless.
    return selected
        ? FilledButton(style: AdminButtonStyles.primary(), onPressed: onTap, child: Text(label))
        : OutlinedButton(style: AdminButtonStyles.secondary(), onPressed: onTap, child: Text(label));
  }
}

/// Rename/re-describe a lesson — unchanged content, just relocated from the
/// old inline accordion onto this lesson's own screen.
class LessonNameCard extends ConsumerStatefulWidget {
  const LessonNameCard({super.key, required this.courseId, required this.lesson});
  final String courseId;
  final AdminLesson lesson;

  @override
  ConsumerState<LessonNameCard> createState() => _LessonNameCardState();
}

class _LessonNameCardState extends ConsumerState<LessonNameCard> {
  late final _title = TextEditingController(text: widget.lesson.title);
  late final _description = TextEditingController(text: widget.lesson.description);
  bool _busy = false;
  // Collapsed by default (§ pinned header + independent scroll, 2026-09-02).
  // This card is pinned above the working area now, so every pixel it takes
  // is a pixel the word/question list never gets back — the teacher comes
  // here to edit content, not to re-read the lesson's own description. Same
  // collapse pattern as the course screen's own settings section.
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
      await ref.read(builderRepositoryProvider).updateLesson(widget.courseId, widget.lesson.id, title: _title.text.trim(), description: _description.text.trim());
      ref.invalidate(builderCourseProvider(widget.courseId));
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить название');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: AdminColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _expanded ? 'Название и описание' : widget.lesson.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AdminTypography.cardTitle,
                ),
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _title, decoration: adminInputDecoration(label: 'Название урока')),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _description, decoration: adminInputDecoration(label: 'Описание')),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _save,
              style: AdminButtonStyles.text(),
              child: const Text('Сохранить название'),
            ),
          ),
          const SizedBox(height: AdminMetrics.cardGap),
          _LessonTranslationsSection(courseId: widget.courseId, lesson: widget.lesson),
        ],
      ],
    );
  }
}

/// Lesson-level counterpart of _CourseTranslationsSection in
/// builder_course_edit_screen.dart (§ course content language, 2026-09-04,
/// spec §5) — same locale-tab pattern, plus the lesson's material text.
/// Only meaningful for a lesson still on its flat fields, or a converted
/// graph lesson's legacy rollback copy (see CourseLessonTranslation's
/// docstring) — a graph lesson's real material-node content is localized
/// through its own MaterialBlock editors instead, not built yet.
class _LessonTranslationsSection extends ConsumerStatefulWidget {
  const _LessonTranslationsSection({required this.courseId, required this.lesson});
  final String courseId;
  final AdminLesson lesson;

  @override
  ConsumerState<_LessonTranslationsSection> createState() => _LessonTranslationsSectionState();
}

class _LessonTranslationsSectionState extends ConsumerState<_LessonTranslationsSection> {
  String _locale = supportedContentLocales.first;
  late final _title = TextEditingController(text: widget.lesson.translations[_locale]?.title ?? '');
  late final _description = TextEditingController(text: widget.lesson.translations[_locale]?.description ?? '');
  late final _materialText = TextEditingController(text: widget.lesson.translations[_locale]?.materialText ?? '');
  bool _busy = false;

  void _switchLocale(String locale) {
    final t = widget.lesson.translations[locale];
    setState(() {
      _locale = locale;
      _title.text = t?.title ?? '';
      _description.text = t?.description ?? '';
      _materialText.text = t?.materialText ?? '';
    });
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).setLessonTranslation(
            widget.courseId,
            widget.lesson.id,
            _locale,
            title: _title.text.trim(),
            description: _description.text.trim(),
            materialText: _materialText.text,
          );
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
    _materialText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(AdminMetrics.blockRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Языковые версии урока', style: AdminTypography.cardTitle),
          const SizedBox(height: 4),
          Row(
            children: [
              for (final locale in supportedContentLocales)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      '${localeDisplayName(Locale(locale))}${widget.lesson.translations.containsKey(locale) ? '' : ' — нет перевода'}',
                    ),
                    selected: _locale == locale,
                    onSelected: (_) => _switchLocale(locale),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _title, decoration: adminInputDecoration(label: 'Название урока')),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _description, decoration: adminInputDecoration(label: 'Описание')),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _materialText, maxLines: 8, decoration: adminInputDecoration(label: 'Текст урока (materialText)')),
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

/// One-time "Перевести в граф" entry point (§ lesson graph, 2026-09-03) —
/// shown only for a lesson still on the old fixed 8-stage chain. Fetches the
/// computed preview first (what the conversion would produce, from the
/// lesson's CURRENT content) so the teacher confirms an actual plan rather
/// than a blind action; the conversion itself references existing
/// Material/LessonBlock/vocabulary rows, it never duplicates content.
class _ConvertToGraphRow extends ConsumerStatefulWidget {
  const _ConvertToGraphRow({required this.courseId, required this.lesson, required this.onDone});
  final String courseId;
  final AdminLesson lesson;
  final VoidCallback onDone;

  @override
  ConsumerState<_ConvertToGraphRow> createState() => _ConvertToGraphRowState();
}

class _ConvertToGraphRowState extends ConsumerState<_ConvertToGraphRow> {
  bool _busy = false;

  Future<void> _convert() async {
    setState(() => _busy = true);
    try {
      final repo = ref.read(builderRepositoryProvider);
      final preview = await repo.getLessonGraph(widget.courseId, widget.lesson.id);
      if (!mounted) return;
      final chain = preview.nodes.map((n) => n.title).join(' → ');
      final ok = await confirmDialog(
        context,
        title: 'Перевести урок в граф?',
        message: preview.nodes.isEmpty
            ? 'В уроке пока нет содержимого — граф начнётся пустым, добавляйте блоки сами.'
            : 'Текущий порядок станет графом:\n$chain\n\nСодержимое (материалы, вопросы, слова) не удаляется и не копируется — блоки графа будут ссылаться на него. Это действие необратимо.',
        confirmLabel: 'Перевести в граф',
      );
      if (!ok) return;
      await repo.materializeLessonGraph(widget.courseId, widget.lesson.id);
      widget.onDone();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось перевести урок в граф');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Свободный граф блоков вместо фиксированной цепочки этапов.',
            style: AdminTypography.caption,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          onPressed: _busy ? null : _convert,
          style: AdminButtonStyles.secondary(),
          icon: const Icon(Icons.hub_outlined, size: 16),
          label: const Text('Перевести в граф'),
        ),
      ],
    );
  }
}
