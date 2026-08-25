import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/block_question.dart';
import '../../domain/builder_domain.dart';

/// Mirrors BuilderBlockEditor.tsx — one named block of questions (any mix
/// of the 5 kinds), fully local-editable draft state, replaced wholesale on
/// "Сохранить вопросы" (matches the backend's PUT .../blocks/:id/questions
/// full-replace contract).
class BlockEditor extends ConsumerStatefulWidget {
  const BlockEditor({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.block,
    required this.index,
    required this.total,
    required this.onMove,
    required this.onChanged,
  });

  final String courseId;
  final String lessonId;
  final AdminBlock block;
  final int index;
  final int total;
  final void Function(int delta) onMove;
  final VoidCallback onChanged;

  @override
  ConsumerState<BlockEditor> createState() => _BlockEditorState();
}

class _BlockEditorState extends ConsumerState<BlockEditor> {
  bool _open = false;
  late List<QuestionDraft> _questions = List.of(widget.block.questions);
  late final _titleController = TextEditingController(text: widget.block.title);
  bool _busy = false;

  @override
  void didUpdateWidget(covariant BlockEditor old) {
    super.didUpdateWidget(old);
    if (old.block.id != widget.block.id) {
      _questions = List.of(widget.block.questions);
      _titleController.text = widget.block.title;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    if (_titleController.text.trim().isEmpty) return;
    try {
      await ref.read(builderRepositoryProvider).renameBlock(widget.courseId, widget.lessonId, widget.block.id, _titleController.text.trim());
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось переименовать блок');
    }
  }

  Future<void> _deleteBlock() async {
    final ok = await confirmDialog(context, title: 'Удалить «${widget.block.title}» вместе с вопросами?');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).removeBlock(widget.courseId, widget.lessonId, widget.block.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить блок');
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).saveBlockQuestions(widget.courseId, widget.lessonId, widget.block.id, _questions);
      widget.onChanged();
      if (mounted) showSuccessSnack(context, 'Вопросы сохранены');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить вопросы');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addQuestion(QuestionDraft Function() blank) => setState(() => _questions = [..._questions, blank()]);
  void _replaceQuestion(int i, QuestionDraft draft) => setState(() => _questions = [..._questions]..[i] = draft);
  void _removeQuestion(int i) => setState(() => _questions = [..._questions]..removeAt(i));
  void _moveQuestion(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _questions.length) return;
    setState(() {
      final copy = [..._questions];
      final tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
      _questions = copy;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(icon: const Icon(Icons.arrow_upward), onPressed: widget.index > 0 ? () => widget.onMove(-1) : null),
                IconButton(icon: const Icon(Icons.arrow_downward), onPressed: widget.index < widget.total - 1 ? () => widget.onMove(1) : null),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _open = !_open),
                    child: Text('${widget.block.title} (${widget.block.questions.length} вопросов)', style: Theme.of(context).textTheme.titleSmall),
                  ),
                ),
                IconButton(icon: Icon(_open ? Icons.expand_less : Icons.expand_more), onPressed: () => setState(() => _open = !_open)),
                IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteBlock),
              ],
            ),
            if (_open) ...[
              const Divider(),
              Row(
                children: [
                  Expanded(child: TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Название блока'))),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _rename, child: const Text('Переименовать')),
                ],
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _questions.length; i++)
                _QuestionCard(
                  draft: _questions[i],
                  index: i,
                  total: _questions.length,
                  onChanged: (d) => _replaceQuestion(i, d),
                  onDelete: () => _removeQuestion(i),
                  onMove: (delta) => _moveQuestion(i, delta),
                ),
              _QuestionLibrarySearch(onPick: (d) => _addQuestion(() => d)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(onPressed: () => _addQuestion(ChoiceDraft.blank), child: const Text('Вопрос с вариантами')),
                  OutlinedButton(onPressed: () => _addQuestion(TrueFalseDraft.blank), child: const Text('Верно / Неверно')),
                  OutlinedButton(onPressed: () => _addQuestion(ClozeDraft.blank), child: const Text('Пропущенное слово')),
                  OutlinedButton(onPressed: () => _addQuestion(ScrambleDraft.blank), child: const Text('Собери фразу')),
                  OutlinedButton(onPressed: () => _addQuestion(MatchDraft.blank), child: const Text('Сопоставление')),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Сохраняем…' : 'Сохранить вопросы')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestionLibrarySearch extends ConsumerStatefulWidget {
  const _QuestionLibrarySearch({required this.onPick});
  final void Function(QuestionDraft) onPick;

  @override
  ConsumerState<_QuestionLibrarySearch> createState() => _QuestionLibrarySearchState();
}

class _QuestionLibrarySearchState extends ConsumerState<_QuestionLibrarySearch> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<QuestionDraft>? _results;

  @override
  void dispose() {
    _query.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(builderRepositoryProvider).searchQuestions(value.trim());
      if (mounted) setState(() => _results = results);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(controller: _query, decoration: const InputDecoration(labelText: 'Найти готовое задание в других уроках'), onChanged: _onChanged),
        if (_results != null && _results!.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final r in _results!)
                  ListTile(
                    dense: true,
                    title: Text(_previewText(r)),
                    subtitle: Text(questionKindLabel(r)),
                    onTap: () {
                      widget.onPick(r);
                      setState(() {
                        _results = null;
                        _query.clear();
                      });
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  String _previewText(QuestionDraft d) => switch (d) {
        ChoiceDraft(:final prompt) => prompt,
        TrueFalseDraft(:final prompt) => prompt,
        ClozeDraft(:final prompt) => prompt,
        ScrambleDraft(:final translation) => translation,
        MatchDraft(:final prompt) => prompt.isEmpty ? 'Сопоставление' : prompt,
      };
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.draft, required this.index, required this.total, required this.onChanged, required this.onDelete, required this.onMove});

  final QuestionDraft draft;
  final int index;
  final int total;
  final ValueChanged<QuestionDraft> onChanged;
  final VoidCallback onDelete;
  final void Function(int delta) onMove;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(questionKindLabel(draft), style: Theme.of(context).textTheme.labelMedium)),
                IconButton(icon: const Icon(Icons.arrow_upward, size: 18), onPressed: index > 0 ? () => onMove(-1) : null),
                IconButton(icon: const Icon(Icons.arrow_downward, size: 18), onPressed: index < total - 1 ? () => onMove(1) : null),
                IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: onDelete),
              ],
            ),
            _body(context),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) => switch (draft) {
        ChoiceDraft d => _ChoiceEditor(draft: d, cloze: false, onChanged: onChanged),
        ClozeDraft d => _ClozeEditorAdapter(draft: d, onChanged: onChanged),
        TrueFalseDraft d => _TrueFalseEditor(draft: d, onChanged: onChanged),
        ScrambleDraft d => _ScrambleEditor(draft: d, onChanged: onChanged),
        MatchDraft d => _MatchEditor(draft: d, onChanged: onChanged),
      };
}

class _ChoiceEditor extends StatelessWidget {
  const _ChoiceEditor({required this.draft, required this.cloze, required this.onChanged});
  final ChoiceDraft draft;
  final bool cloze;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Вопрос'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(ChoiceDraft(prompt: v, options: draft.options, correctIndex: draft.correctIndex)),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < draft.options.length; i++)
          Row(
            children: [
              Radio<int>(value: i, groupValue: draft.correctIndex, onChanged: (v) => onChanged(ChoiceDraft(prompt: draft.prompt, options: draft.options, correctIndex: v ?? 0))),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(labelText: 'Вариант ${i + 1}'),
                  controller: TextEditingController(text: draft.options[i])..selection = TextSelection.collapsed(offset: draft.options[i].length),
                  onChanged: (v) {
                    final opts = [...draft.options];
                    opts[i] = v;
                    onChanged(ChoiceDraft(prompt: draft.prompt, options: opts, correctIndex: draft.correctIndex));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: draft.options.length <= 2
                    ? null
                    : () {
                        final opts = [...draft.options]..removeAt(i);
                        var correct = draft.correctIndex;
                        if (i == draft.correctIndex) {
                          correct = 0;
                        } else if (i < draft.correctIndex) {
                          correct -= 1;
                        }
                        onChanged(ChoiceDraft(prompt: draft.prompt, options: opts, correctIndex: correct));
                      },
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(ChoiceDraft(prompt: draft.prompt, options: [...draft.options, ''], correctIndex: draft.correctIndex)),
          child: const Text('+ Вариант ответа'),
        ),
      ],
    );
  }
}

/// Cloze reuses ChoiceDraft's editor UI (same options+correctIndex shape),
/// just with the cloze-specific prompt hint and blank placeholder.
class _ClozeEditorAdapter extends StatelessWidget {
  const _ClozeEditorAdapter({required this.draft, required this.onChanged});
  final ClozeDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Фраза с пропуском (отметьте его как ___)', hintText: 'Ich ___ aus Deutschland.'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(ClozeDraft(prompt: v, options: draft.options, correctIndex: draft.correctIndex)),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < draft.options.length; i++)
          Row(
            children: [
              Radio<int>(value: i, groupValue: draft.correctIndex, onChanged: (v) => onChanged(ClozeDraft(prompt: draft.prompt, options: draft.options, correctIndex: v ?? 0))),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(labelText: 'Вариант ${i + 1}'),
                  controller: TextEditingController(text: draft.options[i])..selection = TextSelection.collapsed(offset: draft.options[i].length),
                  onChanged: (v) {
                    final opts = [...draft.options];
                    opts[i] = v;
                    onChanged(ClozeDraft(prompt: draft.prompt, options: opts, correctIndex: draft.correctIndex));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: draft.options.length <= 2
                    ? null
                    : () {
                        final opts = [...draft.options]..removeAt(i);
                        var correct = draft.correctIndex;
                        if (i == draft.correctIndex) {
                          correct = 0;
                        } else if (i < draft.correctIndex) {
                          correct -= 1;
                        }
                        onChanged(ClozeDraft(prompt: draft.prompt, options: opts, correctIndex: correct));
                      },
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(ClozeDraft(prompt: draft.prompt, options: [...draft.options, ''], correctIndex: draft.correctIndex)),
          child: const Text('+ Вариант ответа'),
        ),
      ],
    );
  }
}

class _TrueFalseEditor extends StatelessWidget {
  const _TrueFalseEditor({required this.draft, required this.onChanged});
  final TrueFalseDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Утверждение'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(TrueFalseDraft(prompt: v, correct: draft.correct)),
        ),
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                value: true,
                groupValue: draft.correct,
                title: const Text('Верно'),
                onChanged: (v) => onChanged(TrueFalseDraft(prompt: draft.prompt, correct: v ?? true)),
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                value: false,
                groupValue: draft.correct,
                title: const Text('Неверно'),
                onChanged: (v) => onChanged(TrueFalseDraft(prompt: draft.prompt, correct: v ?? false)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScrambleEditor extends StatelessWidget {
  const _ScrambleEditor({required this.draft, required this.onChanged});
  final ScrambleDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Перевод / инструкция'),
          controller: TextEditingController(text: draft.translation)..selection = TextSelection.collapsed(offset: draft.translation.length),
          onChanged: (v) => onChanged(ScrambleDraft(translation: v, correctPhrase: draft.correctPhrase, extraWords: draft.extraWords)),
        ),
        const SizedBox(height: 6),
        TextField(
          decoration: const InputDecoration(labelText: 'Правильная фраза'),
          controller: TextEditingController(text: draft.correctPhrase)..selection = TextSelection.collapsed(offset: draft.correctPhrase.length),
          onChanged: (v) => onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: v, extraWords: draft.extraWords)),
        ),
        if (draft.correctTokens.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Слова из фразы: ${draft.correctTokens.join(', ')} (ученик увидит их вперемешку)', style: Theme.of(context).textTheme.bodySmall),
          ),
        for (var i = 0; i < draft.extraWords.length; i++)
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Лишнее слово'),
                  controller: TextEditingController(text: draft.extraWords[i])..selection = TextSelection.collapsed(offset: draft.extraWords[i].length),
                  onChanged: (v) {
                    final words = [...draft.extraWords];
                    words[i] = v;
                    onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: draft.correctPhrase, extraWords: words));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () {
                  final words = [...draft.extraWords]..removeAt(i);
                  onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: draft.correctPhrase, extraWords: words));
                },
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: draft.correctPhrase, extraWords: [...draft.extraWords, ''])),
          child: const Text('+ Лишнее слово'),
        ),
      ],
    );
  }
}

class _MatchEditor extends StatelessWidget {
  const _MatchEditor({required this.draft, required this.onChanged});
  final MatchDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: const InputDecoration(labelText: 'Инструкция (необязательно)'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(MatchDraft(prompt: v, pairs: draft.pairs)),
        ),
        const SizedBox(height: 6),
        for (var i = 0; i < draft.pairs.length; i++)
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Немецкий'),
                  controller: TextEditingController(text: draft.pairs[i].left)..selection = TextSelection.collapsed(offset: draft.pairs[i].left.length),
                  onChanged: (v) {
                    final pairs = [...draft.pairs];
                    pairs[i] = MatchPairDraft(left: v, right: pairs[i].right);
                    onChanged(MatchDraft(prompt: draft.prompt, pairs: pairs));
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Перевод'),
                  controller: TextEditingController(text: draft.pairs[i].right)..selection = TextSelection.collapsed(offset: draft.pairs[i].right.length),
                  onChanged: (v) {
                    final pairs = [...draft.pairs];
                    pairs[i] = MatchPairDraft(left: pairs[i].left, right: v);
                    onChanged(MatchDraft(prompt: draft.prompt, pairs: pairs));
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: draft.pairs.length <= 2
                    ? null
                    : () {
                        final pairs = [...draft.pairs]..removeAt(i);
                        onChanged(MatchDraft(prompt: draft.prompt, pairs: pairs));
                      },
              ),
            ],
          ),
        TextButton(
          onPressed: () => onChanged(MatchDraft(prompt: draft.prompt, pairs: [...draft.pairs, const MatchPairDraft(left: '', right: '')])),
          child: const Text('+ Пара'),
        ),
      ],
    );
  }
}
