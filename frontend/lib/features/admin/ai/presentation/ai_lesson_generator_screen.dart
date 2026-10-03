import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../admin_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/ai_repository.dart';

/// «Создать уроки с ИИ» (§ AI lesson generator, 2026-10-03): settings →
/// generation (one request per lesson, so progress is visible and no single
/// request runs too long) → read-only preview → «Сохранить в курс».
/// Nothing reaches the course before the admin presses save; the saved
/// lessons are ordinary graph lessons, editable like any other.
class AiLessonGeneratorScreen extends ConsumerStatefulWidget {
  const AiLessonGeneratorScreen({super.key, required this.courseId, required this.courseTitle});

  final String courseId;
  final String courseTitle;

  @override
  ConsumerState<AiLessonGeneratorScreen> createState() => _AiLessonGeneratorScreenState();
}

class _AiLessonGeneratorScreenState extends ConsumerState<AiLessonGeneratorScreen> {
  final _instructions = TextEditingController();
  int _count = 1;
  bool _generating = false;
  bool _saving = false;
  int _done = 0;
  String? _error;
  final List<Map<String, dynamic>> _lessons = [];
  final List<String> _warnings = [];

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
      _done = 0;
      _lessons.clear();
      _warnings.clear();
    });
    final repo = ref.read(aiRepositoryProvider);
    try {
      for (var i = 0; i < _count; i++) {
        final preview = await repo.previewLesson(
          widget.courseId,
          instructions: _instructions.text,
          previous: [for (final l in _lessons) {'title': l['title'], 'wordIds': l['wordIds']}],
        );
        if (!mounted) return;
        setState(() {
          _lessons.add(preview.lesson);
          _warnings.addAll(preview.warnings);
          _done = i + 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось сгенерировать урок'));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final ids = await ref.read(aiRepositoryProvider).applyLessons(widget.courseId, _lessons);
      if (!mounted) return;
      showSuccessSnack(context, 'Добавлено уроков: ${ids.length}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = adminErrorMessage(e, 'Не удалось сохранить уроки'));
        // Lessons saved before the failure stay in the course — say so.
        showErrorSnack(context, e, 'Не удалось сохранить уроки');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: lightTheme,
      child: Scaffold(
        backgroundColor: AdminColors.bg,
        appBar: AppBar(
          backgroundColor: AdminColors.card,
          foregroundColor: AdminColors.text,
          elevation: 0,
          title: Text('Уроки с ИИ — ${widget.courseTitle}', style: AdminTypography.pageTitle, overflow: TextOverflow.ellipsis),
          actions: [
            if (_lessons.isNotEmpty && !_generating)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: AdminButtonStyles.primary(),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(_saving ? 'Сохранение…' : 'Сохранить в курс'),
                ),
              ),
          ],
        ),
        body: AdminMaxWidth(
          maxWidth: AdminMetrics.maxContentWidth,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Что создать', style: AdminTypography.cardTitle),
                    const SizedBox(height: 4),
                    Text(
                      'ИИ берёт слова только из Словаря и фразы из базы фраз (язык курса), пишет объяснения на русском и таджикском, '
                      'вопросы к каждому блоку, текст для аудио и упражнения на закрепление. Сначала вы увидите результат — в курс он попадёт только после «Сохранить».',
                      style: AdminTypography.caption,
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    Row(
                      children: [
                        Text('Сколько уроков:', style: AdminTypography.body),
                        const SizedBox(width: 12),
                        SegmentedButton<int>(
                          segments: [for (final n in const [1, 2, 3]) ButtonSegment(value: n, label: Text('$n'))],
                          selected: {_count},
                          onSelectionChanged: _generating ? null : (v) => setState(() => _count = v.first),
                        ),
                      ],
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    TextField(
                      controller: _instructions,
                      enabled: !_generating,
                      minLines: 2,
                      maxLines: 5,
                      decoration: adminInputDecoration(
                        label: 'Пожелания (необязательно)',
                        hint: 'Например: тема — знакомство и приветствия; больше диалогов; без сложной грамматики',
                      ),
                    ),
                    const SizedBox(height: AdminMetrics.fieldGap),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _generating || _saving ? null : _generate,
                          style: AdminButtonStyles.primary(),
                          icon: const Icon(Icons.auto_awesome, size: 18),
                          label: Text(_lessons.isEmpty ? 'Сгенерировать' : 'Сгенерировать заново'),
                        ),
                        if (_generating) ...[
                          const SizedBox(width: 12),
                          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Урок ${_done + 1} из $_count… это может занять до минуты', style: AdminTypography.caption)),
                        ],
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: AdminTypography.body.copyWith(color: AdminColors.danger)),
                    ],
                  ],
                ),
              ),
              if (_warnings.isNotEmpty) ...[
                const SizedBox(height: AdminMetrics.cardGap),
                AdminCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Исправлено автоматически (${_warnings.length})', style: AdminTypography.cardTitle.copyWith(color: AdminColors.warn)),
                      const SizedBox(height: 4),
                      for (final w in _warnings) Text('• $w', style: AdminTypography.caption),
                    ],
                  ),
                ),
              ],
              for (var i = 0; i < _lessons.length; i++) ...[
                const SizedBox(height: AdminMetrics.cardGap),
                _LessonPreview(lesson: _lessons[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonPreview extends StatelessWidget {
  const _LessonPreview({required this.lesson});
  final Map<String, dynamic> lesson;

  List<Map<String, dynamic>> _list(String key) => [for (final e in (lesson[key] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];

  @override
  Widget build(BuildContext context) {
    final blocks = _list('blocks');
    final words = _list('words');
    final phrases = _list('phrases');
    final minitest = _list('minitest');
    final audio = lesson['audio'] as Map?;
    final practice = Map<String, dynamic>.from(lesson['practice'] as Map? ?? const {});
    final blankIds = ((practice['blankPhraseIds'] as List?) ?? const []).cast<String>().toSet();
    final blankPhrases = phrases.where((p) => blankIds.contains(p['id'])).toList();
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lesson['title'] as String? ?? '', style: AdminTypography.pageTitle),
          if (lesson['title_tg'] != null) Text(lesson['title_tg'] as String, style: AdminTypography.caption),
          if (lesson['topic'] != null) ...[
            const SizedBox(height: 4),
            Text('Тема: ${lesson['topic']}', style: AdminTypography.fieldLabel),
          ],
          _Section(
            icon: Icons.style_outlined,
            title: 'Слова (${words.length})',
            child: Text(words.map((w) => '${w['word']} — ${w['translation']}').join(' · '), style: AdminTypography.body),
          ),
          for (var b = 0; b < blocks.length; b++)
            _Section(
              icon: Icons.menu_book_outlined,
              title: 'Блок ${b + 1}: ${blocks[b]['title']}',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(blocks[b]['content'] as String? ?? '', style: AdminTypography.body),
                  if (blocks[b]['content_tg'] != null) ...[
                    const SizedBox(height: 6),
                    Text(blocks[b]['content_tg'] as String, style: AdminTypography.caption),
                  ],
                  for (final q in (blocks[b]['questions'] as List? ?? const [])) _QuestionLine(q: Map<String, dynamic>.from(q as Map)),
                ],
              ),
            ),
          if (audio != null)
            _Section(
              icon: Icons.headphones_outlined,
              title: 'Аудио — текст для записи',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(audio['transcript'] as String? ?? '', style: AdminTypography.body),
                  if (audio['translation_ru'] != null) Text(audio['translation_ru'] as String, style: AdminTypography.caption),
                  if (audio['translation_tg'] != null) Text(audio['translation_tg'] as String, style: AdminTypography.caption),
                ],
              ),
            ),
          _Section(
            icon: Icons.fitness_center_outlined,
            title: 'Практика',
            child: Text(
              [
                if ((practice['translateCount'] ?? 0) > 0) '«Переведи слово» × ${practice['translateCount']}',
                if ((practice['matchPairs'] ?? 0) > 0) '«Сопоставление» — ${practice['matchPairs']} пар',
                if (blankPhrases.isNotEmpty) '«Пропущенное слово» по фразам: ${blankPhrases.map((p) => p['text']).join(', ')}',
              ].join('\n'),
              style: AdminTypography.body,
            ),
          ),
          if (minitest.isNotEmpty)
            _Section(
              icon: Icons.quiz_outlined,
              title: 'Мини-тест (${minitest.length})',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final q in minitest)
                    _QuestionLine(q: q, suffix: q['verifiesBlock'] != null ? '  → проверяет блок ${(q['verifiesBlock'] as int) + 1}' : null),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.child});
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AdminMetrics.fieldGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 16, color: AdminColors.accent), const SizedBox(width: 6), Expanded(child: Text(title, style: AdminTypography.stageTitle))]),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(left: 22), child: child),
        ],
      ),
    );
  }
}

const _kindLabels = {
  'choice': 'Выбор',
  'truefalse': 'Верно/неверно',
  'cloze': 'Пропуск',
  'scramble': 'Собери фразу',
  'match': 'Сопоставление',
};

class _QuestionLine extends StatelessWidget {
  const _QuestionLine({required this.q, this.suffix});
  final Map<String, dynamic> q;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    final question = Map<String, dynamic>.from(q['question'] as Map? ?? const {});
    final kind = question['kind'] as String? ?? '';
    final String answer = switch (kind) {
      'truefalse' => question['correct'] == true ? 'верно' : 'неверно',
      'match' => (question['pairs'] as List? ?? const []).map((p) => '${(p as Map)['left']}=${p['right']}').join(', '),
      _ => question['correctAnswer'] as String? ?? '',
    };
    final options = (question['options'] as List?)?.cast<String>() ?? const [];
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${_kindLabels[kind] ?? kind}: ', style: AdminTypography.fieldLabel),
            TextSpan(text: question['prompt'] as String? ?? '', style: AdminTypography.body),
            if (options.isNotEmpty) TextSpan(text: '  [${options.join(' / ')}]', style: AdminTypography.caption),
            TextSpan(text: '  ✓ $answer', style: AdminTypography.caption.copyWith(color: AdminColors.success)),
            if (suffix != null) TextSpan(text: suffix, style: AdminTypography.caption.copyWith(color: AdminColors.accent)),
          ],
        ),
      ),
    );
  }
}
