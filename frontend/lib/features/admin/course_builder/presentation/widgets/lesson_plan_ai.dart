import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../admin_tokens.dart';
import '../../../ai/data/ai_repository.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';

// § course modules, 2026-10-05: the lesson plan, «Заполнить с ИИ», the
// «Фразы» step's picker and the «ждёт ИИ» switch of any step.

/// The lesson plan: English for the AI that fills the lesson, Russian for
/// the teacher. Returns true when saved.
Future<bool> showLessonPlanDialog(BuildContext context, WidgetRef ref, {required String courseId, required AdminLesson lesson}) async {
  final en = TextEditingController(text: lesson.planEn ?? '');
  final ru = TextEditingController(text: lesson.planRu ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => _PlanDialog(courseId: courseId, lesson: lesson, en: en, ru: ru),
  );
  en.dispose();
  ru.dispose();
  return saved == true;
}

class _PlanDialog extends ConsumerStatefulWidget {
  const _PlanDialog({required this.courseId, required this.lesson, required this.en, required this.ru});
  final String courseId;
  final AdminLesson lesson;
  final TextEditingController en;
  final TextEditingController ru;

  @override
  ConsumerState<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends ConsumerState<_PlanDialog> {
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).updateLesson(widget.courseId, widget.lesson.id, planEn: widget.en.text, planRu: widget.ru.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить план');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('План урока «${widget.lesson.title}»'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Для ИИ (на английском) — по нему ИИ заполняет шаги «ждёт ИИ».', style: AdminTypography.caption),
              const SizedBox(height: 6),
              TextField(controller: widget.en, minLines: 6, maxLines: 16, decoration: adminInputDecoration(hint: 'Goal, rule, examples, what each step must contain…')),
              const SizedBox(height: AdminMetrics.fieldGap),
              Text('Для преподавателя (на русском).', style: AdminTypography.caption),
              const SizedBox(height: 6),
              TextField(controller: widget.ru, minLines: 6, maxLines: 16, decoration: adminInputDecoration(hint: 'Цель урока, правило, примеры, что в каждом шаге…')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _save, style: AdminButtonStyles.primary(), child: const Text('Сохранить план')),
      ],
    );
  }
}

/// Asks for optional wishes, runs «Заполнить с ИИ» and shows what happened.
/// Returns true when anything was filled (the caller reloads the lesson).
Future<bool> runAiFill(BuildContext context, WidgetRef ref, {required String courseId, required AdminLesson lesson}) async {
  final hasPlan = (lesson.planEn ?? '').trim().isNotEmpty || (lesson.planRu ?? '').trim().isNotEmpty;
  if (!hasPlan) {
    showErrorSnack(context, const Object(), 'Сначала напишите план урока — ИИ заполняет урок по нему');
    return false;
  }
  final wishes = TextEditingController();
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Заполнить урок с ИИ'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ИИ заполнит шаги, которые ждут ИИ (${lesson.pendingSteps}), по плану урока, его словам и фразам. '
              'Структура урока не меняется, уже заполненные шаги не трогаются. Это займёт до пары минут.',
              style: AdminTypography.body,
            ),
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: wishes, minLines: 2, maxLines: 5, decoration: adminInputDecoration(label: 'Пожелания (необязательно)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          style: AdminButtonStyles.primary(),
          icon: const Icon(Icons.auto_awesome, size: 16),
          label: const Text('Заполнить'),
        ),
      ],
    ),
  );
  final text = wishes.text;
  wishes.dispose();
  if (go != true || !context.mounted) return false;

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Expanded(child: Text('ИИ заполняет урок…'))]),
    ),
  ));
  try {
    final result = await ref.read(builderRepositoryProvider).aiFillLesson(courseId, lesson.id, instructions: text);
    navigator.pop();
    if (!context.mounted) return result.filled > 0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Заполнено шагов: ${result.filled}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.waiting > 0) Text('Ещё ждут: ${result.waiting}', style: AdminTypography.body),
                if (result.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Замечания:', style: AdminTypography.fieldLabel),
                  for (final w in result.warnings) Text('• $w', style: AdminTypography.caption),
                ],
                const SizedBox(height: 8),
                Text('Проверьте содержимое шагов — его можно править как обычно.', style: AdminTypography.caption),
              ],
            ),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), style: AdminButtonStyles.primary(), child: const Text('Готово'))],
      ),
    );
    return result.filled > 0;
  } catch (e) {
    navigator.pop();
    if (context.mounted) showErrorSnack(context, e, 'ИИ не смог заполнить урок');
    return false;
  }
}

/// «Сбросить заполнение ИИ» for a whole lesson (nodeId null) or one step.
/// Asks first — whatever was written in those steps, by the AI or by hand,
/// is deleted. Returns true when something was reset.
Future<bool> runAiReset(BuildContext context, WidgetRef ref, {required String courseId, required String lessonId, String? nodeId, String? stepTitle}) async {
  final ok = await confirmDialog(
    context,
    title: nodeId == null ? 'Сбросить заполнение ИИ во всём уроке?' : 'Сбросить шаг «${stepTitle ?? ''}»?',
    message: nodeId == null
        ? 'Все шаги с заданием для ИИ станут пустыми и снова будут ждать ИИ: объяснения, вопросы, тексты аудио и видео удалятся — '
            'в том числе ваши правки в этих шагах. Слова, фразы, маршрут, план и загруженные файлы останутся.'
        : 'Содержимое шага удалится — в том числе ваши правки, — и шаг снова будет ждать ИИ.',
    confirmLabel: 'Сбросить',
  );
  if (!ok) return false;
  try {
    final n = await ref.read(builderRepositoryProvider).aiResetLesson(courseId, lessonId, nodeId: nodeId);
    if (context.mounted) showSuccessSnack(context, 'Сброшено шагов: $n — можно заполнить заново');
    return n > 0;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, e, 'Не удалось сбросить');
    return false;
  }
}

/// Steps the AI can fill, for the «Пустой шаг для ИИ» dialog.
const aiFillableTypes = {
  'material': 'Материал (объяснение)',
  'practice': 'Практика',
  'minitest': 'Мини-тест',
  'review': 'Закрепление',
  'audio': 'Аудио (текст записи)',
  'video': 'Видео (текст для персонажа)',
  'mediatest': 'Тест по аудио / видео',
};

/// Asks for the type, title and task of a new empty step for the AI.
Future<({String type, String? title, String task, String taskRu, String? forNodeId})?> askEmptyAiStep(
  BuildContext context, {
  List<AdminGraphNode> mediaSteps = const [],
}) async {
  var type = 'practice';
  String? forNodeId = mediaSteps.isEmpty ? null : mediaSteps.first.id;
  final title = TextEditingController();
  final task = TextEditingController();
  final taskRu = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Пустой шаг для ИИ'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: adminInputDecoration(label: 'Что это за шаг'),
                items: [
                  for (final e in aiFillableTypes.entries)
                    if (e.key != 'mediatest' || mediaSteps.isNotEmpty) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setLocal(() => type = v ?? type),
              ),
              if (type == 'mediatest') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: forNodeId,
                  decoration: adminInputDecoration(label: 'По какому аудио / видео'),
                  items: [for (final m in mediaSteps) DropdownMenuItem(value: m.id, child: Text('${m.type == 'video' ? 'Видео' : 'Аудио'}: ${m.title}'))],
                  onChanged: (v) => setLocal(() => forNodeId = v),
                ),
              ],
              const SizedBox(height: 8),
              TextField(controller: title, decoration: adminInputDecoration(label: 'Название шага (необязательно)')),
              const SizedBox(height: 8),
              TextField(
                controller: task,
                minLines: 3,
                maxLines: 8,
                decoration: adminInputDecoration(label: 'Задание для ИИ', hint: 'Например: 6 questions on am/is/are, choice + cloze, use lesson words'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: taskRu,
                minLines: 2,
                maxLines: 6,
                decoration: adminInputDecoration(label: 'Задание по-русски (для проверки)', hint: 'Например: 6 вопросов на am/is/are'),
              ),
              const SizedBox(height: 6),
              Text('Ученики не увидят этот шаг, пока его не заполнят.', style: AdminTypography.caption),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: AdminButtonStyles.primary(), child: const Text('Добавить')),
        ],
      ),
    ),
  );
  final isTest = type == 'mediatest';
  final result = ok == true
      ? (
          type: isTest ? 'practice' : type,
          title: title.text.trim().isEmpty ? (isTest ? 'Тест по ${mediaSteps.firstWhere((m) => m.id == forNodeId, orElse: () => mediaSteps.first).type == 'video' ? 'видео' : 'аудио'}' : null) : title.text.trim(),
          task: task.text.trim().isEmpty && isTest ? '4-5 comprehension questions about this text' : task.text.trim(),
          taskRu: taskRu.text.trim(),
          forNodeId: isTest ? forNodeId : null,
        )
      : null;
  title.dispose();
  task.dispose();
  taskRu.dispose();
  return result;
}

/// «Ждёт ИИ» switch and the AI task of any step.
class AiTaskEditor extends ConsumerStatefulWidget {
  const AiTaskEditor({super.key, required this.courseId, required this.lessonId, required this.node, required this.onSaved, this.testOfTitle});
  final String courseId;
  final String lessonId;
  final AdminGraphNode node;
  final VoidCallback onSaved;
  /// «Тест по аудио/видео»: the title of the step it tests.
  final String? testOfTitle;

  @override
  ConsumerState<AiTaskEditor> createState() => _AiTaskEditorState();
}

class _AiTaskEditorState extends ConsumerState<AiTaskEditor> {
  late final _task = TextEditingController(text: widget.node.aiTask ?? '');
  late final _taskRu = TextEditingController(text: widget.node.aiTaskRu ?? '');
  late bool _pending = widget.node.aiPending;
  bool _busy = false;

  @override
  void dispose() {
    _task.dispose();
    _taskRu.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    final done = await runAiReset(context, ref, courseId: widget.courseId, lessonId: widget.lessonId, nodeId: widget.node.id, stepTitle: widget.node.title);
    if (mounted) setState(() => _busy = false);
    if (done) widget.onSaved();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(builderRepositoryProvider)
          .updateGraphNode(widget.courseId, widget.lessonId, widget.node.id, aiTask: _task.text, aiTaskRu: _taskRu.text, aiPending: _pending);
      widget.onSaved();
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fillable = aiFillableTypes.containsKey(widget.node.type);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _pending ? const Color(0xFFFFF6E0) : AdminColors.bg,
        borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
        border: Border.all(color: _pending ? const Color(0xFFE0A526) : AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _pending,
            onChanged: _busy ? null : (v) => setState(() => _pending = v),
            title: Text('Ждёт ИИ', style: AdminTypography.fieldLabel),
            subtitle: Text(
              fillable
                  ? 'Ученики не видят шаг, пока он ждёт. «Заполнить с ИИ» заполнит его по заданию и плану урока.'
                  : 'ИИ не заполняет этот тип шага — заполните его сами и выключите «Ждёт ИИ».',
              style: AdminTypography.caption,
            ),
          ),
          if (widget.testOfTitle != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('Тест по шагу «${widget.testOfTitle}»: вопросы составляются по его тексту и привязываются к нему.', style: AdminTypography.caption),
            ),
          TextField(
            controller: _task,
            minLines: 2,
            maxLines: 6,
            decoration: adminInputDecoration(label: 'Задание для ИИ', hint: 'What exactly belongs in this step'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _taskRu,
            minLines: 2,
            maxLines: 6,
            decoration: adminInputDecoration(label: 'Задание по-русски (для проверки)'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if ((widget.node.aiTask ?? '').isNotEmpty && !widget.node.aiPending)
                TextButton.icon(
                  onPressed: _busy ? null : _reset,
                  style: AdminButtonStyles.dangerText(),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Сбросить шаг'),
                ),
              const Spacer(),
              TextButton(onPressed: _busy ? null : _save, style: AdminButtonStyles.text(), child: const Text('Сохранить')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Content of a «Фразы» step: phrases picked from the language's phrase
/// base (never copied), in the order learners see them.
class PhrasesNodeEditor extends ConsumerStatefulWidget {
  const PhrasesNodeEditor({super.key, required this.courseId, required this.lessonId, required this.node, required this.languageId, required this.onChanged});
  final String courseId;
  final String lessonId;
  final AdminGraphNode node;
  final String? languageId;
  final VoidCallback onChanged;

  @override
  ConsumerState<PhrasesNodeEditor> createState() => _PhrasesNodeEditorState();
}

class _PhrasesNodeEditorState extends ConsumerState<PhrasesNodeEditor> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<AdminPhrase> _results = const [];
  bool _busy = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (q.trim().isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      try {
        final page = await ref.read(aiRepositoryProvider).listPhrases(languageId: widget.languageId, query: q, limit: 15);
        if (mounted) setState(() => _results = page.phrases);
      } catch (_) {}
    });
  }

  Future<void> _save(List<String> ids) async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).updateGraphNode(widget.courseId, widget.lessonId, widget.node.id, phraseIds: ids);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить фразы');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ids = [for (final p in widget.node.phrases) p.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Фразы шага (${ids.length})', style: AdminTypography.fieldLabel),
        const SizedBox(height: 6),
        if (ids.isEmpty) Text('Фраз пока нет — найдите их в базе фраз ниже.', style: AdminTypography.caption),
        for (var i = 0; i < widget.node.phrases.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(widget.node.phrases[i].text, style: AdminTypography.body),
            subtitle: Text(widget.node.phrases[i].translation, style: AdminTypography.caption),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Выше',
                  icon: const Icon(Icons.arrow_upward, size: 16),
                  onPressed: _busy || i == 0 ? null : () => _save([...ids]..insert(i - 1, ids[i])..removeAt(i + 1)),
                ),
                IconButton(
                  tooltip: 'Убрать из шага',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: _busy ? null : () => _save([...ids]..removeAt(i)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AdminMetrics.fieldGap),
        TextField(
          controller: _query,
          onChanged: _search,
          decoration: adminInputDecoration(label: 'Найти фразу в базе', hint: 'Начните вводить фразу или перевод'),
        ),
        for (final p in _results.where((p) => !ids.contains(p.id)))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(p.text, style: AdminTypography.body),
            subtitle: Text(p.translation, style: AdminTypography.caption),
            trailing: IconButton(
              tooltip: 'Добавить',
              icon: const Icon(Icons.add_circle_outline, size: 20, color: AdminColors.accent),
              onPressed: _busy ? null : () => _save([...ids, p.id]),
            ),
          ),
      ],
    );
  }
}
