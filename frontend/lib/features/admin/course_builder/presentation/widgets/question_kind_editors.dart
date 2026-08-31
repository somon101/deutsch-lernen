import 'package:flutter/material.dart';

import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../domain/block_question.dart';

/// Per-kind field editors for the 5 question types — shared between the
/// quiz-stage block editor (block_editor.dart, still backed by the old
/// LessonQuestion/LessonBlock path) and the new reusable-question-pool flow
/// (Material/MaterialBlock questions, backed by Question/QuestionPlacement).
/// Both save through the exact same wire shape (QuestionDraft.toWire()
/// matches the backend's BlockQuestionInput either way), so the editing UI
/// itself doesn't need two copies (§47 — don't duplicate the same logic in
/// several places).

/// Full-width white "+ add" button — the one deliberate exception to the
/// "pill sized to its text" rule (Principle 2): it visually continues the
/// list above it, inviting one more row.
class AddRowButton extends StatelessWidget {
  const AddRowButton({super.key, required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: double.infinity, child: OutlinedButton(onPressed: onPressed, style: AdminButtonStyles.secondary(), child: Text(label)));
  }
}

class ChoiceEditor extends StatelessWidget {
  const ChoiceEditor({super.key, required this.draft, required this.onChanged});
  final ChoiceDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: adminInputDecoration(label: 'Вопрос'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(ChoiceDraft(prompt: v, options: draft.options, correctIndex: draft.correctIndex)),
        ),
        const SizedBox(height: 6),
        Text('Отметьте правильный вариант:', style: AdminTypography.fieldLabel),
        RadioGroup<int>(
          groupValue: draft.correctIndex,
          onChanged: (v) => onChanged(ChoiceDraft(prompt: draft.prompt, options: draft.options, correctIndex: v ?? 0)),
          child: Column(
            children: [
              for (var i = 0; i < draft.options.length; i++)
                Row(
                  children: [
                    Radio<int>(value: i),
                    Expanded(
                      child: TextField(
                        decoration: adminInputDecoration(label: 'Вариант ${i + 1}'),
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
                      color: AdminColors.danger,
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
            ],
          ),
        ),
        AddRowButton(
          label: '+ Вариант ответа',
          onPressed: () => onChanged(ChoiceDraft(prompt: draft.prompt, options: [...draft.options, ''], correctIndex: draft.correctIndex)),
        ),
      ],
    );
  }
}

/// Cloze reuses ChoiceDraft's editor UI (same options+correctIndex shape),
/// just with the cloze-specific prompt hint and blank placeholder.
class ClozeEditorAdapter extends StatelessWidget {
  const ClozeEditorAdapter({super.key, required this.draft, required this.onChanged});
  final ClozeDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: adminInputDecoration(label: 'Фраза с пропуском (отметьте его как ___)', hint: 'Ich ___ aus Deutschland.'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(ClozeDraft(prompt: v, options: draft.options, correctIndex: draft.correctIndex)),
        ),
        const SizedBox(height: 6),
        Text('Отметьте правильный вариант:', style: AdminTypography.fieldLabel),
        RadioGroup<int>(
          groupValue: draft.correctIndex,
          onChanged: (v) => onChanged(ClozeDraft(prompt: draft.prompt, options: draft.options, correctIndex: v ?? 0)),
          child: Column(
            children: [
              for (var i = 0; i < draft.options.length; i++)
                Row(
                  children: [
                    Radio<int>(value: i),
                    Expanded(
                      child: TextField(
                        decoration: adminInputDecoration(label: 'Вариант ${i + 1}'),
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
                      color: AdminColors.danger,
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
            ],
          ),
        ),
        AddRowButton(
          label: '+ Вариант ответа',
          onPressed: () => onChanged(ClozeDraft(prompt: draft.prompt, options: [...draft.options, ''], correctIndex: draft.correctIndex)),
        ),
      ],
    );
  }
}

class TrueFalseEditor extends StatelessWidget {
  const TrueFalseEditor({super.key, required this.draft, required this.onChanged});
  final TrueFalseDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: adminInputDecoration(label: 'Утверждение'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(TrueFalseDraft(prompt: v, correct: draft.correct)),
        ),
        RadioGroup<bool>(
          groupValue: draft.correct,
          onChanged: (v) => onChanged(TrueFalseDraft(prompt: draft.prompt, correct: v ?? true)),
          child: Row(
            children: const [
              Expanded(child: RadioListTile<bool>(value: true, title: Text('Верно'))),
              Expanded(child: RadioListTile<bool>(value: false, title: Text('Неверно'))),
            ],
          ),
        ),
      ],
    );
  }
}

class ScrambleEditor extends StatelessWidget {
  const ScrambleEditor({super.key, required this.draft, required this.onChanged});
  final ScrambleDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: adminInputDecoration(label: 'Перевод / инструкция'),
          controller: TextEditingController(text: draft.translation)..selection = TextSelection.collapsed(offset: draft.translation.length),
          onChanged: (v) => onChanged(ScrambleDraft(translation: v, correctPhrase: draft.correctPhrase, extraWords: draft.extraWords)),
        ),
        const SizedBox(height: 6),
        TextField(
          decoration: adminInputDecoration(label: 'Правильная фраза'),
          controller: TextEditingController(text: draft.correctPhrase)..selection = TextSelection.collapsed(offset: draft.correctPhrase.length),
          onChanged: (v) => onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: v, extraWords: draft.extraWords)),
        ),
        if (draft.correctTokens.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Слова из фразы: ${draft.correctTokens.join(', ')} (ученик увидит их вперемешку)', style: AdminTypography.caption),
          ),
        for (var i = 0; i < draft.extraWords.length; i++)
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: adminInputDecoration(label: 'Лишнее слово'),
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
                color: AdminColors.danger,
                onPressed: () {
                  final words = [...draft.extraWords]..removeAt(i);
                  onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: draft.correctPhrase, extraWords: words));
                },
              ),
            ],
          ),
        AddRowButton(
          label: '+ Лишнее слово',
          onPressed: () => onChanged(ScrambleDraft(translation: draft.translation, correctPhrase: draft.correctPhrase, extraWords: [...draft.extraWords, ''])),
        ),
      ],
    );
  }
}

/// The teacher enters ONLY full sentences (§ auto blank, 2026-08-31) — no
/// blank marker, no options, no correct-answer picker anywhere in this
/// form; the system decides all of that per learner at lesson time.
class AutoBlankEditor extends StatelessWidget {
  const AutoBlankEditor({super.key, required this.draft, required this.onChanged});
  final AutoBlankDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Введите полную фразу (количество не ограничено):', style: AdminTypography.fieldLabel),
        for (var i = 0; i < draft.phrases.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: adminInputDecoration(label: 'Фраза ${i + 1}', hint: 'I am from Tajikistan.'),
                    controller: TextEditingController(text: draft.phrases[i])..selection = TextSelection.collapsed(offset: draft.phrases[i].length),
                    onChanged: (v) {
                      final phrases = [...draft.phrases];
                      phrases[i] = v;
                      onChanged(AutoBlankDraft(phrases: phrases));
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: AdminColors.danger,
                  onPressed: draft.phrases.length <= 1
                      ? null
                      : () {
                          final phrases = [...draft.phrases]..removeAt(i);
                          onChanged(AutoBlankDraft(phrases: phrases));
                        },
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        AddRowButton(label: '+ Добавить фразу', onPressed: () => onChanged(AutoBlankDraft(phrases: [...draft.phrases, '']))),
      ],
    );
  }
}

class MatchEditor extends StatelessWidget {
  const MatchEditor({super.key, required this.draft, required this.onChanged});
  final MatchDraft draft;
  final ValueChanged<QuestionDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: adminInputDecoration(label: 'Инструкция (необязательно)'),
          controller: TextEditingController(text: draft.prompt)..selection = TextSelection.collapsed(offset: draft.prompt.length),
          onChanged: (v) => onChanged(MatchDraft(prompt: v, pairs: draft.pairs)),
        ),
        const SizedBox(height: 6),
        Text('Пары (количество не ограничено, минимум 2):', style: AdminTypography.fieldLabel),
        for (var i = 0; i < draft.pairs.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: adminInputDecoration(label: 'Немецкий'),
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
                    decoration: adminInputDecoration(label: 'Перевод'),
                    controller: TextEditingController(text: draft.pairs[i].right)..selection = TextSelection.collapsed(offset: draft.pairs[i].right.length),
                    onChanged: (v) {
                      final pairs = [...draft.pairs];
                      pairs[i] = MatchPairDraft(left: pairs[i].left, right: v);
                      onChanged(MatchDraft(prompt: draft.prompt, pairs: pairs));
                    },
                  ),
                ),
                AdminDeleteLink(
                  label: 'Удалить',
                  onPressed: draft.pairs.length <= 2
                      ? null
                      : () {
                          final pairs = [...draft.pairs]..removeAt(i);
                          onChanged(MatchDraft(prompt: draft.prompt, pairs: pairs));
                        },
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        AddRowButton(
          label: '+ Пара',
          onPressed: () => onChanged(MatchDraft(prompt: draft.prompt, pairs: [...draft.pairs, const MatchPairDraft(left: '', right: '')])),
        ),
      ],
    );
  }
}
