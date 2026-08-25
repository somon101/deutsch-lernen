/// Editable-draft models for the 5 question kinds a block can hold — mirrors
/// BuilderBlockEditor.tsx's EditableQuestion: the draft shape differs from
/// the wire shape for choice/cloze (tracks `correctIndex` instead of a
/// `correctAnswer` string, so the correct pick survives text edits to the
/// options) and for scramble (splits the single correct phrase from its
/// decoy words, rather than storing one flat `options` list).
sealed class QuestionDraft {
  const QuestionDraft();

  Map<String, dynamic> toWire();
}

class ChoiceDraft extends QuestionDraft {
  const ChoiceDraft({required this.prompt, required this.options, required this.correctIndex});

  factory ChoiceDraft.blank() => const ChoiceDraft(prompt: '', options: ['', ''], correctIndex: 0);

  factory ChoiceDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final index = options.indexOf(correctAnswer);
    return ChoiceDraft(prompt: json['prompt'] as String, options: options, correctIndex: index < 0 ? 0 : index);
  }

  final String prompt;
  final List<String> options;
  final int correctIndex;

  @override
  Map<String, dynamic> toWire() => {
        'kind': 'choice',
        'prompt': prompt,
        'options': options,
        'correctAnswer': options.isEmpty ? '' : options[correctIndex.clamp(0, options.length - 1)],
      };
}

class TrueFalseDraft extends QuestionDraft {
  const TrueFalseDraft({required this.prompt, required this.correct});

  factory TrueFalseDraft.blank() => const TrueFalseDraft(prompt: '', correct: true);

  factory TrueFalseDraft.fromWire(Map<String, dynamic> json) =>
      TrueFalseDraft(prompt: json['prompt'] as String, correct: json['correct'] as bool);

  final String prompt;
  final bool correct;

  @override
  Map<String, dynamic> toWire() => {'kind': 'truefalse', 'prompt': prompt, 'correct': correct};
}

class ClozeDraft extends QuestionDraft {
  const ClozeDraft({required this.prompt, required this.options, required this.correctIndex});

  factory ClozeDraft.blank() => const ClozeDraft(prompt: 'Ich ___ aus Deutschland.', options: ['', ''], correctIndex: 0);

  factory ClozeDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final index = options.indexOf(correctAnswer);
    return ClozeDraft(prompt: json['prompt'] as String, options: options, correctIndex: index < 0 ? 0 : index);
  }

  final String prompt;
  final List<String> options;
  final int correctIndex;

  @override
  Map<String, dynamic> toWire() => {
        'kind': 'cloze',
        'prompt': prompt,
        'options': options,
        'correctAnswer': options.isEmpty ? '' : options[correctIndex.clamp(0, options.length - 1)],
      };
}

class ScrambleDraft extends QuestionDraft {
  const ScrambleDraft({required this.translation, required this.correctPhrase, required this.extraWords});

  factory ScrambleDraft.blank() => const ScrambleDraft(translation: '', correctPhrase: '', extraWords: []);

  /// Reconstructs from the flat wire shape (options = [...correctTokens,
  /// ...extraWords] in that order, per toWire below) — the correct tokens
  /// are always the options list's prefix matching correctAnswer's tokens.
  factory ScrambleDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final correctTokens = correctAnswer.split(' ').where((w) => w.isNotEmpty).toList();
    final extraWords = options.length > correctTokens.length ? options.sublist(correctTokens.length) : <String>[];
    return ScrambleDraft(translation: json['prompt'] as String, correctPhrase: correctAnswer, extraWords: extraWords);
  }

  final String translation;
  final String correctPhrase;
  final List<String> extraWords;

  List<String> get correctTokens => correctPhrase.split(' ').where((w) => w.isNotEmpty).toList();

  @override
  Map<String, dynamic> toWire() => {
        'kind': 'scramble',
        'prompt': translation,
        'options': [...correctTokens, ...extraWords],
        'correctAnswer': correctTokens.join(' '),
      };
}

class MatchPairDraft {
  const MatchPairDraft({required this.left, required this.right});
  final String left;
  final String right;
}

class MatchDraft extends QuestionDraft {
  const MatchDraft({required this.prompt, required this.pairs});

  factory MatchDraft.blank() => const MatchDraft(prompt: '', pairs: [MatchPairDraft(left: '', right: ''), MatchPairDraft(left: '', right: '')]);

  factory MatchDraft.fromWire(Map<String, dynamic> json) => MatchDraft(
        prompt: json['prompt'] as String? ?? '',
        pairs: (json['pairs'] as List<dynamic>)
            .map((p) => MatchPairDraft(left: (p as Map<String, dynamic>)['left'] as String, right: p['right'] as String))
            .toList(),
      );

  final String prompt;
  final List<MatchPairDraft> pairs;

  @override
  Map<String, dynamic> toWire() => {
        'kind': 'match',
        'prompt': prompt,
        'pairs': [for (final p in pairs) {'left': p.left, 'right': p.right}],
      };
}

QuestionDraft questionDraftFromWire(Map<String, dynamic> json) => switch (json['kind'] as String) {
      'truefalse' => TrueFalseDraft.fromWire(json),
      'cloze' => ClozeDraft.fromWire(json),
      'scramble' => ScrambleDraft.fromWire(json),
      'match' => MatchDraft.fromWire(json),
      _ => ChoiceDraft.fromWire(json),
    };

String questionKindLabel(QuestionDraft d) => switch (d) {
      ChoiceDraft() => 'Вопрос с вариантами',
      TrueFalseDraft() => 'Верно / Неверно',
      ClozeDraft() => 'Пропущенное слово',
      ScrambleDraft() => 'Собери фразу',
      MatchDraft() => 'Сопоставление',
    };
