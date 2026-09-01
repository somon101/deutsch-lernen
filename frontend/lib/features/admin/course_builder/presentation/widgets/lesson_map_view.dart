import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_tokens.dart';
import '../../data/builder_repository.dart';
import '../../domain/taxonomy_domain.dart';

/// Full-screen, read-only "Карта урока" overview (§8 of the course-builder
/// redesign, 2026-09-01) — a mirror of the verifies-links already editable
/// elsewhere, never an editor of its own ("это не редактор связей ...
/// это зеркало"). Returns the chain key ('material' / 'minitest' /
/// 'practice' / 'review') the caller should switch the rail to, or null if
/// the teacher just closed the map without picking anything.
Future<String?> showLessonConnectionsMap(
  BuildContext context, {
  required String courseId,
  required String lessonId,
  required String lessonTitle,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _LessonMapScreen(courseId: courseId, lessonId: lessonId, lessonTitle: lessonTitle),
    ),
  );
}

class _LessonMapScreen extends ConsumerStatefulWidget {
  const _LessonMapScreen({required this.courseId, required this.lessonId, required this.lessonTitle});
  final String courseId;
  final String lessonId;
  final String lessonTitle;

  @override
  ConsumerState<_LessonMapScreen> createState() => _LessonMapScreenState();
}

class _LessonMapScreenState extends ConsumerState<_LessonMapScreen> {
  late Future<LessonConnectionsMap> _future;
  // Hover-only highlight (§8: "наведение/тап ... подсвечивает его связи и
  // приглушает остальные") — separate from onTap, which navigates away.
  String? _hoverMaterialId;
  String? _hoverStage;

  @override
  void initState() {
    super.initState();
    _future = ref.read(builderRepositoryProvider).lessonConnectionsMap(widget.courseId, widget.lessonId);
  }

  void _focus(String chainKey) => Navigator.of(context).pop(chainKey);

  bool get _dimmed => _hoverMaterialId != null || _hoverStage != null;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: AdminColors.bg,
        appBar: AppBar(
          backgroundColor: AdminColors.bg,
          elevation: 0,
          foregroundColor: AdminColors.text,
          title: Text('Карта урока · ${widget.lessonTitle}', style: AdminTypography.cardTitle),
        ),
        body: FutureBuilder<LessonConnectionsMap>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Не удалось загрузить карту урока', style: AdminTypography.body.copyWith(color: AdminColors.danger)),
              );
            }
            final map = snapshot.data!;
            if (map.materials.isEmpty && map.stages.every((s) => s.blocks.every((b) => b.questions.isEmpty))) {
              return Center(child: Text('В этом уроке пока нечего показывать на карте', style: AdminTypography.caption));
            }
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 760;
                final theory = _TheoryColumn(
                  materials: map.materials,
                  hoverId: _hoverMaterialId,
                  dimmed: _dimmed,
                  onHover: (id) => setState(() => _hoverMaterialId = id),
                  onTap: (_) => _focus('material'),
                );
                final tasks = _TasksColumn(
                  stages: map.stages,
                  hoverStage: _hoverStage,
                  hoverMaterialId: _hoverMaterialId,
                  dimmed: _dimmed,
                  onHoverStage: (s) => setState(() => _hoverStage = s),
                  onTap: _focus,
                );
                final content = wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: theory),
                          const SizedBox(width: 24),
                          Container(width: 1, color: AdminColors.border),
                          const SizedBox(width: 24),
                          Expanded(child: tasks),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [theory, const SizedBox(height: AdminMetrics.sectionGap), tasks],
                      );
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: content,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(label, style: AdminTypography.fieldLabel.copyWith(letterSpacing: 1)),
  );
}

class _TheoryColumn extends StatelessWidget {
  const _TheoryColumn({required this.materials, required this.hoverId, required this.dimmed, required this.onHover, required this.onTap});
  final List<MapMaterialBlock> materials;
  final String? hoverId;
  final bool dimmed;
  final ValueChanged<String?> onHover;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const _ColumnHeader('ТЕОРИЯ'), Text('Материал ещё не добавлен', style: AdminTypography.caption)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ColumnHeader('ТЕОРИЯ'),
        for (final m in materials)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _MaterialRow(
              material: m,
              highlighted: hoverId == m.id,
              // Also lights up when the hovered stage links back to this
              // block (§8: hover picks out its own connections either way).
              dimmed: dimmed && hoverId != m.id,
              onHover: (v) => onHover(v ? m.id : null),
              onTap: () => onTap(m.id),
            ),
          ),
      ],
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({
    required this.material,
    required this.highlighted,
    required this.dimmed,
    required this.onHover,
    required this.onTap,
  });
  final MapMaterialBlock material;
  final bool highlighted;
  final bool dimmed;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: AdminMetrics.transition,
      opacity: dimmed ? 0.4 : 1,
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
          child: AdminCard(
            highlighted: highlighted,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(material.title, style: AdminTypography.body.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                if (material.hasWarning)
                  const _WarnChip('не проверяется')
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final v in material.verifiedBy) _LinkChip(v.stageLabel ?? v.blockTitle ?? '—')],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TasksColumn extends StatelessWidget {
  const _TasksColumn({
    required this.stages,
    required this.hoverStage,
    required this.hoverMaterialId,
    required this.dimmed,
    required this.onHoverStage,
    required this.onTap,
  });
  final List<MapStage> stages;
  final String? hoverStage;
  final String? hoverMaterialId;
  final bool dimmed;
  final ValueChanged<String?> onHoverStage;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final hasAny = stages.any((s) => s.blocks.any((b) => b.questions.isNotEmpty));
    if (!hasAny) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const _ColumnHeader('ЗАДАНИЯ'), Text('Вопросов пока нет', style: AdminTypography.caption)],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _ColumnHeader('ЗАДАНИЯ'),
        for (final stage in stages)
          if (stage.blocks.any((b) => b.questions.isNotEmpty)) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: Text(stage.stageLabel, style: AdminTypography.stageTitle),
            ),
            for (final block in stage.blocks)
              for (final q in block.questions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _QuestionRow(
                    question: q,
                    stage: stage.stage,
                    // Highlighted when its own stage is hovered, or when the
                    // theory block it verifies is hovered.
                    highlighted: hoverStage == stage.stage || (hoverMaterialId != null && hoverMaterialId == q.verifiesBlockId),
                    dimmed: dimmed && hoverStage != stage.stage && !(hoverMaterialId != null && hoverMaterialId == q.verifiesBlockId),
                    onHover: (v) => onHoverStage(v ? stage.stage : null),
                    onTap: () => onTap(stage.stage),
                  ),
                ),
            const SizedBox(height: 4),
          ],
      ],
    );
  }
}

const _kindLabels = {
  'choice': 'Выбор ответа',
  'truefalse': 'Верно / неверно',
  'cloze': 'Пропущенное слово',
  'scramble': 'Собери фразу',
  'match': 'Сопоставление',
  'auto_blank': 'Пропущенное слово (авто)',
};

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({
    required this.question,
    required this.stage,
    required this.highlighted,
    required this.dimmed,
    required this.onHover,
    required this.onTap,
  });
  final MapQuestion question;
  final String stage;
  final bool highlighted;
  final bool dimmed;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = _kindLabels[question.kind] ?? question.kind;
    return AnimatedOpacity(
      duration: AdminMetrics.transition,
      opacity: dimmed ? 0.4 : 1,
      child: MouseRegion(
        onEnter: (_) => onHover(true),
        onExit: (_) => onHover(false),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
          child: AdminCard(
            highlighted: highlighted,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text('${question.number}', style: AdminTypography.caption.copyWith(fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(
                    question.prompt.isEmpty ? label : '$label — ${question.prompt}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminTypography.body,
                  ),
                ),
                const SizedBox(width: 8),
                if (question.verifiesBlockTitle != null)
                  _LinkChip(question.verifiesBlockTitle!)
                else
                  const _WarnChip('без привязки'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Connectivity indicator — the one place the admin accent color is used
/// (§2 of the redesign: accent means "this connects to that", never a
/// button fill).
class _LinkChip extends StatelessWidget {
  const _LinkChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AdminColors.accentSoft, borderRadius: BorderRadius.circular(999)),
    child: Text(
      '→ $label',
      style: AdminTypography.caption.copyWith(color: AdminColors.accentHover, fontWeight: FontWeight.w600),
    ),
  );
}

/// Muted amber, never red (§8: "оба приглушённо-янтарные, не красные").
class _WarnChip extends StatelessWidget {
  const _WarnChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: AdminColors.warnSoft, borderRadius: BorderRadius.circular(999)),
    child: Text('⚠ $label', style: AdminTypography.caption.copyWith(color: AdminColors.warn, fontWeight: FontWeight.w600)),
  );
}

/// Course-level rollup (§8: "Карта доступна и на уровне курса — тогда
/// строки это уроки, и видно, какой урок недособран, без захода внутрь") —
/// one row per lesson, each just its warning counts. Read-only, same as
/// the lesson-level map.
void showCourseConnectionsMap(BuildContext context, {required String courseId, required String courseTitle}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _CourseMapScreen(courseId: courseId, courseTitle: courseTitle),
    ),
  );
}

class _CourseMapScreen extends ConsumerStatefulWidget {
  const _CourseMapScreen({required this.courseId, required this.courseTitle});
  final String courseId;
  final String courseTitle;

  @override
  ConsumerState<_CourseMapScreen> createState() => _CourseMapScreenState();
}

class _CourseMapScreenState extends ConsumerState<_CourseMapScreen> {
  late Future<CourseConnectionsMap> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(builderRepositoryProvider).courseConnectionsMap(widget.courseId);
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light(),
      child: Scaffold(
        backgroundColor: AdminColors.bg,
        appBar: AppBar(
          backgroundColor: AdminColors.bg,
          elevation: 0,
          foregroundColor: AdminColors.text,
          title: Text('Карта курса · ${widget.courseTitle}', style: AdminTypography.cardTitle),
        ),
        body: FutureBuilder<CourseConnectionsMap>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Не удалось загрузить карту курса', style: AdminTypography.body.copyWith(color: AdminColors.danger)),
              );
            }
            final lessons = snapshot.data!.lessons;
            if (lessons.isEmpty) {
              return Center(child: Text('В курсе пока нет уроков', style: AdminTypography.caption));
            }
            return AdminMaxWidth(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [for (final l in lessons) Padding(padding: const EdgeInsets.only(bottom: 8), child: _CourseMapRow(l))],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CourseMapRow extends StatelessWidget {
  const _CourseMapRow(this.lesson);
  final CourseMapLesson lesson;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Row(
        children: [
          Expanded(
            child: Text(lesson.title, style: AdminTypography.body.copyWith(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          if (lesson.isFullyLinked)
            const _LinkChip('всё привязано')
          else
            Wrap(
              spacing: 6,
              children: [
                if (lesson.materialWarnings > 0) _WarnChip('${lesson.materialWarnings} без проверки'),
                if (lesson.questionWarnings > 0) _WarnChip('${lesson.questionWarnings} без привязки'),
              ],
            ),
        ],
      ),
    );
  }
}
