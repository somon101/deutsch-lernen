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
  const ChoiceDraft({
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });

  factory ChoiceDraft.blank() =>
      const ChoiceDraft(prompt: '', options: ['', ''], correctIndex: 0);

  factory ChoiceDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final index = options.indexOf(correctAnswer);
    return ChoiceDraft(
      prompt: json['prompt'] as String,
      options: options,
      correctIndex: index < 0 ? 0 : index,
    );
  }

  final String prompt;
  final List<String> options;
  final int correctIndex;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'choice',
    'prompt': prompt,
    'options': options,
    'correctAnswer': options.isEmpty
        ? ''
        : options[correctIndex.clamp(0, options.length - 1)],
  };
}

class TrueFalseDraft extends QuestionDraft {
  const TrueFalseDraft({required this.prompt, required this.correct});

  factory TrueFalseDraft.blank() =>
      const TrueFalseDraft(prompt: '', correct: true);

  factory TrueFalseDraft.fromWire(Map<String, dynamic> json) => TrueFalseDraft(
    prompt: json['prompt'] as String,
    correct: json['correct'] as bool,
  );

  final String prompt;
  final bool correct;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'truefalse',
    'prompt': prompt,
    'correct': correct,
  };
}

class ClozeDraft extends QuestionDraft {
  const ClozeDraft({
    required this.prompt,
    required this.options,
    required this.correctIndex,
  });

  factory ClozeDraft.blank() => const ClozeDraft(
    prompt: 'Ich ___ aus Deutschland.',
    options: ['', ''],
    correctIndex: 0,
  );

  factory ClozeDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final index = options.indexOf(correctAnswer);
    return ClozeDraft(
      prompt: json['prompt'] as String,
      options: options,
      correctIndex: index < 0 ? 0 : index,
    );
  }

  final String prompt;
  final List<String> options;
  final int correctIndex;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'cloze',
    'prompt': prompt,
    'options': options,
    'correctAnswer': options.isEmpty
        ? ''
        : options[correctIndex.clamp(0, options.length - 1)],
  };
}

class ScrambleDraft extends QuestionDraft {
  const ScrambleDraft({
    required this.translation,
    required this.correctPhrase,
    required this.extraWords,
  });

  factory ScrambleDraft.blank() =>
      const ScrambleDraft(translation: '', correctPhrase: '', extraWords: []);

  /// Reconstructs from the flat wire shape (options = [...correctTokens,
  /// ...extraWords] in that order, per toWire below) — the correct tokens
  /// are always the options list's prefix matching correctAnswer's tokens.
  factory ScrambleDraft.fromWire(Map<String, dynamic> json) {
    final options = (json['options'] as List<dynamic>).cast<String>();
    final correctAnswer = json['correctAnswer'] as String;
    final correctTokens = correctAnswer
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final extraWords = options.length > correctTokens.length
        ? options.sublist(correctTokens.length)
        : <String>[];
    return ScrambleDraft(
      translation: json['prompt'] as String,
      correctPhrase: correctAnswer,
      extraWords: extraWords,
    );
  }

  final String translation;
  final String correctPhrase;
  final List<String> extraWords;

  List<String> get correctTokens =>
      correctPhrase.split(' ').where((w) => w.isNotEmpty).toList();

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'scramble',
    'prompt': translation,
    // Auto mode (§ auto scramble, 2026-09-02): with no extra distractor
    // words there is nothing to store that the phrase doesn't already say,
    // so `options` goes over empty and the server derives the pieces from
    // `correctAnswer` at serve time. The phrase stays the single source of
    // truth, and no shuffle order is ever persisted. Extra words are not
    // derivable, so as soon as the teacher adds one the full explicit list
    // is sent instead — exactly what hand-built exercises already store.
    'options': extraWords.isEmpty ? const <String>[] : [...correctTokens, ...extraWords],
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

  factory MatchDraft.blank() => const MatchDraft(
    prompt: '',
    pairs: [
      MatchPairDraft(left: '', right: ''),
      MatchPairDraft(left: '', right: ''),
    ],
  );

  factory MatchDraft.fromWire(Map<String, dynamic> json) => MatchDraft(
    prompt: json['prompt'] as String? ?? '',
    pairs: (json['pairs'] as List<dynamic>)
        .map(
          (p) => MatchPairDraft(
            left: (p as Map<String, dynamic>)['left'] as String,
            right: p['right'] as String,
          ),
        )
        .toList(),
  );

  final String prompt;
  final List<MatchPairDraft> pairs;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'match',
    'prompt': prompt,
    'pairs': [
      for (final p in pairs) {'left': p.left, 'right': p.right},
    ],
  };
}

/// Teacher enters only full sentences (§ auto blank, 2026-08-31) — no blank
/// marker, no options, no correct answer. A different kind from
/// `ClozeDraft` above, which already owns the "Пропущенное слово" label and
/// is fully author-provided; this one's label is disambiguated with
/// "(авто)" (see questionKindLabel below) since the mechanism is genuinely
/// different, not just a UI variant of cloze.
class AutoBlankDraft extends QuestionDraft {
  const AutoBlankDraft({required this.phrases});

  factory AutoBlankDraft.blank() => const AutoBlankDraft(phrases: ['']);

  factory AutoBlankDraft.fromWire(Map<String, dynamic> json) =>
      AutoBlankDraft(phrases: (json['phrases'] as List<dynamic>).cast<String>());

  final List<String> phrases;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'auto_blank',
    'phrases': phrases.where((p) => p.trim().isNotEmpty).toList(),
  };
}

/// Word sources an auto-generated exercise can draw from (§ auto translate,
/// 2026-09-02). Mirrors the server's own list; a future source (e.g. a
/// practice algorithm's prioritised words) is one more entry here and one
/// more provider there — no exercise changes.
enum WordPoolSource {
  lesson('lesson', 'Из этого урока'),
  learned('learned', 'Из изученных слов пользователя');

  const WordPoolSource(this.wire, this.label);
  final String wire;
  final String label;

  static WordPoolSource fromWire(String? v) =>
      WordPoolSource.values.firstWhere((s) => s.wire == v, orElse: () => WordPoolSource.lesson);
}

/// The teacher configures only a source and how many questions to make; the
/// words, the correct answer and the wrong options are all decided per
/// learner, per session, on the server.
class AutoTranslateDraft extends QuestionDraft {
  const AutoTranslateDraft({required this.source, required this.count});

  factory AutoTranslateDraft.blank() => const AutoTranslateDraft(source: WordPoolSource.lesson, count: 5);

  factory AutoTranslateDraft.fromWire(Map<String, dynamic> json) => AutoTranslateDraft(
        source: WordPoolSource.fromWire(json['source'] as String?),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  final WordPoolSource source;
  final int count;

  @override
  Map<String, dynamic> toWire() => {
    'kind': 'auto_translate',
    'source': source.wire,
    'count': count,
  };
}

/// The teacher configures only how many pairs to show (§ auto match,
/// 2026-09-02); the words are chosen per learner, per session, on the
/// server. Only these four counts exist — the server rejects anything else
/// regardless of what the form sends.
class AutoMatchDraft extends QuestionDraft {
  const AutoMatchDraft({required this.count});

  factory AutoMatchDraft.blank() => const AutoMatchDraft(count: 4);

  factory AutoMatchDraft.fromWire(Map<String, dynamic> json) {
    final raw = (json['count'] as num?)?.toInt() ?? 0;
    return AutoMatchDraft(count: allowedPairCounts.contains(raw) ? raw : 4);
  }

  static const allowedPairCounts = [2, 4, 6, 8];

  final int count;

  @override
  Map<String, dynamic> toWire() => {'kind': 'auto_match', 'count': count};
}

QuestionDraft questionDraftFromWire(Map<String, dynamic> json) =>
    switch (json['kind'] as String) {
      'truefalse' => TrueFalseDraft.fromWire(json),
      'cloze' => ClozeDraft.fromWire(json),
      'scramble' => ScrambleDraft.fromWire(json),
      'match' => MatchDraft.fromWire(json),
      'auto_blank' => AutoBlankDraft.fromWire(json),
      'auto_translate' => AutoTranslateDraft.fromWire(json),
      'auto_match' => AutoMatchDraft.fromWire(json),
      _ => ChoiceDraft.fromWire(json),
    };

String questionKindLabel(QuestionDraft d) => switch (d) {
  ChoiceDraft() => 'Вопрос с вариантами',
  TrueFalseDraft() => 'Верно / Неверно',
  ClozeDraft() => 'Пропущенное слово',
  ScrambleDraft() => 'Собери фразу',
  MatchDraft() => 'Сопоставление',
  AutoBlankDraft() => 'Пропущенное слово (авто)',
  AutoTranslateDraft() => 'Переведи слово (авто)',
  AutoMatchDraft() => 'Сопоставление (авто)',
};
