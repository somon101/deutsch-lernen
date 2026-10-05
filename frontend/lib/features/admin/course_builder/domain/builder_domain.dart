import 'block_question.dart';

/// Admin-editing domain models — richer than the learner-facing DTOs in
/// features/courses/data/courses_repository.dart (those only need what a
/// learner reads; these need ids/positions/every editable field). Shared
/// between the course-builder feature and the legacy-lesson editor, since
/// both edit lessons through the exact same shapes (see the migration's
/// cross-cutting note: legacy lessons reuse the builder's own mutations).

class AdminVocabWord {
  const AdminVocabWord({
    required this.id,
    required this.german,
    required this.translation,
    required this.pronunciation,
    this.audioUrl,
    this.imageUrl,
    this.translations = const {},
    this.isNative = true,
    this.nativeLessonId,
    this.nativeCourseId,
  });

  factory AdminVocabWord.fromJson(Map<String, dynamic> json) => AdminVocabWord(
    id: json['id'] as String,
    german: json['german'] as String,
    translation: json['translation'] as String,
    pronunciation: json['pronunciation'] as String? ?? '',
    audioUrl: json['audioUrl'] as String?,
    imageUrl: json['imageUrl'] as String?,
    // {locale: translation} for every locale beyond the base `translation`
    // field above, which IS the "ru" text (§ course content language,
    // 2026-09-04) — see VocabularyTranslation's backend docstring.
    translations: (json['translations'] as Map<String, dynamic>?)?.map(
          (locale, v) => MapEntry(locale, (v as Map<String, dynamic>)['translation'] as String),
        ) ??
        const {},
    // § shared dictionary, 2026-09-14 — false means this row is only
    // REUSED into the current lesson via LessonVocabularyLink, not owned
    // by it; nativeLessonId/nativeCourseId are this word's true home
    // (defaulting to "true"/null for any older DTO shape that predates
    // this field, e.g. a cached response — that reads exactly like a
    // native word, which every word was before this feature existed).
    isNative: json['isNative'] as bool? ?? true,
    nativeLessonId: json['nativeLessonId'] as String?,
    nativeCourseId: json['nativeCourseId'] as String?,
  );

  final String id;
  final String german;
  final String translation;
  final String pronunciation;
  final String? audioUrl;
  final String? imageUrl;
  final Map<String, String> translations;
  final bool isNative;
  final String? nativeLessonId;
  final String? nativeCourseId;
}

class AdminBlock {
  const AdminBlock({
    required this.id,
    required this.stage,
    required this.title,
    required this.position,
    required this.questions,
    required this.questionSources,
  });

  factory AdminBlock.fromJson(Map<String, dynamic> json) => AdminBlock(
    id: json['id'] as String,
    stage: json['stage'] as String,
    title: json['title'] as String,
    position: json['position'] as int,
    // The backend's own "questions" field merges real, locally-editable
    // LessonQuestion rows with reusable-pool questions placed in the same
    // block (so the STUDENT-facing quiz sees everything regardless of
    // mechanism, § approved rule 4, 2026-08-27) — kept as-is here
    // (unfiltered) since course-level aggregates (word/question counts in
    // builder_course_edit_screen.dart) sum this field across every block
    // and need the true total either way. Each item carries its real
    // "source" ("legacy" | "pool") for BlockEditor to filter down to just
    // the legacy ones for its own local-draft state (§ course-builder
    // redesign bugfix, 2026-09-01) — see BlockEditorState._questions.
    questions: (json['questions'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(questionDraftFromWire)
        .toList(),
    questionSources: (json['questions'] as List<dynamic>).cast<Map<String, dynamic>>().map((q) => q['source'] as String? ?? 'legacy').toList(),
  );

  final String id;
  final String stage;
  final String title;
  final int position;
  final List<QuestionDraft> questions;
  // Parallel to [questions] — same index, "legacy" or "pool" per item.
  final List<String> questionSources;
}

/// One block on a lesson's graph canvas (§ lesson graph, 2026-09-03) — wraps
/// existing content by reference (`refId` is a Material.id for "material",
/// a LessonBlock.id for minitest/practice/review; null for
/// vocabulary/video/audio). `mediaUrl` is only meaningful for video/audio.
class AdminGraphNode {
  const AdminGraphNode({
    required this.id,
    required this.type,
    required this.refId,
    required this.mediaUrl,
    required this.title,
    required this.posX,
    required this.posY,
    this.transcript,
    this.transcriptTranslations = const {},
    this.phrases = const [],
    this.aiTask,
    this.aiPending = false,
  });

  factory AdminGraphNode.fromJson(Map<String, dynamic> json) => AdminGraphNode(
    id: json['id'] as String,
    type: json['type'] as String,
    refId: json['refId'] as String?,
    mediaUrl: json['mediaUrl'] as String?,
    title: json['title'] as String,
    posX: (json['posX'] as num).toDouble(),
    posY: (json['posY'] as num).toDouble(),
    transcript: json['transcript'] as String?,
    transcriptTranslations: ((json['transcriptTranslations'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, v as String)),
    phrases: [for (final p in (json['phrases'] as List?) ?? const []) AdminNodePhrase.fromJson(p as Map<String, dynamic>)],
    aiTask: json['aiTask'] as String?,
    aiPending: json['aiPending'] as bool? ?? false,
  );

  final String id;
  final String type;
  final String? refId;
  final String? mediaUrl;
  final String title;
  final double posX;
  final double posY;
  /// Audio nodes only (§ AI lesson generator, 2026-10-03): the recording's
  /// text and its translations by content locale.
  final String? transcript;
  final Map<String, String> transcriptTranslations;
  /// "phrases" nodes only (§ course modules, 2026-10-05): the phrases from
  /// the language's phrase base, in display order.
  final List<AdminNodePhrase> phrases;
  /// An empty step waiting for the AI: what belongs here, and whether it is
  /// still hidden from learners (§ course modules, 2026-10-05).
  final String? aiTask;
  final bool aiPending;

  AdminGraphNode copyWith({double? posX, double? posY, String? title, String? mediaUrl}) => AdminGraphNode(
    id: id,
    type: type,
    refId: refId,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    title: title ?? this.title,
    posX: posX ?? this.posX,
    posY: posY ?? this.posY,
    transcript: transcript,
    transcriptTranslations: transcriptTranslations,
    phrases: phrases,
    aiTask: aiTask,
    aiPending: aiPending,
  );
}

class AdminNodePhrase {
  const AdminNodePhrase({required this.id, required this.text, required this.translation});
  factory AdminNodePhrase.fromJson(Map<String, dynamic> json) =>
      AdminNodePhrase(id: json['id'] as String, text: json['text'] as String, translation: json['translation'] as String? ?? '');
  final String id;
  final String text;
  final String translation;
}

/// A named group of lessons inside a course (§ course modules, 2026-10-05).
class AdminModule {
  const AdminModule({required this.id, required this.title, this.titleTg, this.description = '', required this.position});
  factory AdminModule.fromJson(Map<String, dynamic> json) => AdminModule(
        id: json['id'] as String,
        title: json['title'] as String,
        titleTg: json['titleTg'] as String?,
        description: json['description'] as String? ?? '',
        position: json['position'] as int? ?? 0,
      );
  final String id;
  final String title;
  final String? titleTg;
  final String description;
  final int position;
}

/// A flow connection between two nodes — the only thing that decides the
/// student's route through a graph lesson.
class AdminGraphEdge {
  const AdminGraphEdge({required this.id, required this.fromNodeId, required this.toNodeId});

  factory AdminGraphEdge.fromJson(Map<String, dynamic> json) =>
      AdminGraphEdge(id: json['id'] as String, fromNodeId: json['fromNodeId'] as String, toNodeId: json['toNodeId'] as String);

  final String id;
  final String fromNodeId;
  final String toNodeId;
}

class AdminLessonGraph {
  const AdminLessonGraph({required this.nodes, required this.edges, this.isLegacy = false});

  factory AdminLessonGraph.fromJson(Map<String, dynamic> json) => AdminLessonGraph(
    isLegacy: json['isLegacy'] as bool? ?? false,
    nodes: (json['nodes'] as List<dynamic>).map((n) => AdminGraphNode.fromJson(n as Map<String, dynamic>)).toList(),
    edges: (json['edges'] as List<dynamic>).map((e) => AdminGraphEdge.fromJson(e as Map<String, dynamic>)).toList(),
  );

  // True only for a computed PREVIEW of an unconverted lesson (from the
  // standalone GET .../graph endpoint) — never true for the graph embedded
  // in AdminLesson.graph below, which is only ever present once real.
  final bool isLegacy;
  final List<AdminGraphNode> nodes;
  final List<AdminGraphEdge> edges;
}

class AdminLessonTranslation {
  const AdminLessonTranslation({required this.title, required this.description, required this.materialText});

  factory AdminLessonTranslation.fromJson(Map<String, dynamic> json) => AdminLessonTranslation(
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    materialText: json['materialText'] as String? ?? '',
  );

  final String title;
  final String description;
  final String materialText;
}

class AdminLesson {
  const AdminLesson({
    required this.id,
    required this.title,
    required this.description,
    required this.materialText,
    required this.videoUrl,
    required this.audioUrl,
    required this.position,
    required this.vocabulary,
    required this.blocks,
    this.graph,
    this.translations = const {},
    this.moduleId,
    this.planEn,
    this.planRu,
  });

  factory AdminLesson.fromJson(Map<String, dynamic> json) => AdminLesson(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    materialText: json['materialText'] as String? ?? '',
    videoUrl: json['videoUrl'] as String?,
    audioUrl: json['audioUrl'] as String?,
    position: json['position'] as int? ?? 0,
    vocabulary: (json['vocabulary'] as List<dynamic>)
        .map((w) => AdminVocabWord.fromJson(w as Map<String, dynamic>))
        .toList(),
    blocks: (json['blocks'] as List<dynamic>)
        .map((b) => AdminBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
    // Null means this lesson is still on the old fixed 8-stage chain (never
    // converted) — see services/courses.py's lesson_dto (§ lesson graph,
    // 2026-09-03). The legacy file-based course never has this key at all,
    // which json['graph'] as Map?-cast handles the same as an explicit null.
    graph: json['graph'] != null ? AdminLessonGraph.fromJson(json['graph'] as Map<String, dynamic>) : null,
    // Same shape/rationale as AdminCourse.translations (§ course content
    // language, 2026-09-04).
    translations: (json['translations'] as Map<String, dynamic>?)?.map(
          (locale, v) => MapEntry(locale, AdminLessonTranslation.fromJson(v as Map<String, dynamic>)),
        ) ??
        const {},
    moduleId: json['moduleId'] as String?,
    planEn: json['planEn'] as String?,
    planRu: json['planRu'] as String?,
  );

  /// GET/PUT /api/admin/content/:lessonId's shape — keyed by `lessonId`
  /// instead of `id`, and has no `title`/`description` of its own (a legacy
  /// lesson's display title comes from its parsed material, supplied by the
  /// caller — see content.py's list_legacy_lessons on the backend side).
  factory AdminLesson.fromLegacyJson(
    String lessonId,
    String title,
    Map<String, dynamic> json,
  ) => AdminLesson(
    id: lessonId,
    title: title,
    description: '',
    materialText: json['materialText'] as String? ?? '',
    videoUrl: json['videoUrl'] as String?,
    audioUrl: json['audioUrl'] as String?,
    position: 0,
    vocabulary: (json['vocabulary'] as List<dynamic>)
        .map((w) => AdminVocabWord.fromJson(w as Map<String, dynamic>))
        .toList(),
    blocks: (json['blocks'] as List<dynamic>)
        .map((b) => AdminBlock.fromJson(b as Map<String, dynamic>))
        .toList(),
  );

  final String id;
  final String title;
  final String description;
  final String materialText;
  final String? videoUrl;
  final String? audioUrl;
  final int position;
  final List<AdminVocabWord> vocabulary;
  final List<AdminBlock> blocks;
  final AdminLessonGraph? graph;
  final Map<String, AdminLessonTranslation> translations;
  // § course modules, 2026-10-05: the lesson's module (null = none) and its
  // plan — English for the AI that fills it, Russian for the teacher.
  final String? moduleId;
  final String? planEn;
  final String? planRu;

  /// Steps of this lesson still waiting for the AI.
  int get pendingSteps => graph?.nodes.where((n) => n.aiPending).length ?? 0;

  List<AdminBlock> blocksFor(String stage) =>
      blocks.where((b) => b.stage == stage).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
}

class AdminCourseTranslation {
  const AdminCourseTranslation({required this.title, required this.description});

  factory AdminCourseTranslation.fromJson(Map<String, dynamic> json) =>
      AdminCourseTranslation(title: json['title'] as String, description: json['description'] as String? ?? '');

  final String title;
  final String description;
}

class AdminCourse {
  const AdminCourse({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.status,
    required this.position,
    required this.levelId,
    required this.lessons,
    this.translations = const {},
    this.modules = const [],
  });

  factory AdminCourse.fromJson(Map<String, dynamic> json) => AdminCourse(
    id: json['id'] as String,
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    coverUrl: json['coverUrl'] as String?,
    status: json['status'] as String,
    position: json['position'] as int,
    levelId: json['levelId'] as String?,
    lessons: (json['lessons'] as List<dynamic>)
        .map((l) => AdminLesson.fromJson(l as Map<String, dynamic>))
        .toList(),
    // Every locale this course already has a saved translation for (§
    // course content language, 2026-09-04) — absent for a callers that
    // predate this feature would just mean an empty map, never an error.
    translations: (json['translations'] as Map<String, dynamic>?)?.map(
          (locale, v) => MapEntry(locale, AdminCourseTranslation.fromJson(v as Map<String, dynamic>)),
        ) ??
        const {},
    modules: [for (final m in (json['modules'] as List?) ?? const []) AdminModule.fromJson(m as Map<String, dynamic>)],
  );

  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final String status;
  final int position;
  final String? levelId;
  final List<AdminLesson> lessons;
  final Map<String, AdminCourseTranslation> translations;
  final List<AdminModule> modules;
}

class AdminCourseSummary {
  const AdminCourseSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.status,
    required this.position,
    required this.lessonCount,
    required this.wordCount,
    required this.questionCount,
    required this.levelId,
  });

  factory AdminCourseSummary.fromJson(Map<String, dynamic> json) =>
      AdminCourseSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String? ?? '',
        coverUrl: json['coverUrl'] as String?,
        status: json['status'] as String,
        position: json['position'] as int,
        lessonCount: json['lessonCount'] as int,
        wordCount: json['wordCount'] as int,
        questionCount: json['questionCount'] as int,
        levelId: json['levelId'] as String?,
      );

  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final String status;
  final int position;
  final int lessonCount;
  final int wordCount;
  final int questionCount;
  final String? levelId;
}

/// A word's category (§ word cards, 2026-08-31) — the backend has had
/// get_or_create_category/list_categories since then, but no screen ever
/// called them; the "Словарь" screen (§ shared dictionary, 2026-09-14) is
/// the first real picker UI for this already-existing mechanism.
class AdminCategory {
  const AdminCategory({required this.id, required this.name});
  factory AdminCategory.fromJson(Map<String, dynamic> json) => AdminCategory(id: json['categoryId'] as String, name: json['name'] as String);
  final String id;
  final String name;
}

class WordLibraryEntry {
  const WordLibraryEntry({
    required this.id,
    required this.german,
    required this.translation,
    required this.pronunciation,
    this.imageUrl,
    required this.courseId,
    required this.lessonId,
    required this.locationLabel,
  });
  factory WordLibraryEntry.fromJson(Map<String, dynamic> json) =>
      WordLibraryEntry(
        // § shared dictionary, 2026-09-14 — the real id, so a search
        // result can actually be ATTACHED to a lesson (via
        // BuilderRepository.linkExistingWord) instead of only ever
        // copying its text into a new-word form.
        id: json['id'] as String,
        german: json['german'] as String,
        translation: json['translation'] as String,
        pronunciation: json['pronunciation'] as String? ?? '',
        imageUrl: json['imageUrl'] as String?,
        courseId: json['courseId'] as String,
        lessonId: json['lessonId'] as String,
        locationLabel: json['locationLabel'] as String,
      );
  final String id;
  final String german;
  final String translation;
  final String pronunciation;
  final String? imageUrl;
  final String courseId;
  final String lessonId;
  final String locationLabel;
}

/// One row in the admin "Словарь" screen (§ shared dictionary, 2026-09-14)
/// — shape matches services/vocabulary.py's `_word_card_dto` plus
/// `usedInLessonsCount`, distinct from AdminVocabWord's lesson-scoped shape
/// (wordId/word here vs id/german there) because this is the SAME
/// underlying word card the rest of the app already addresses by wordId
/// (exercises, "Мои слова", batch /api/words) — reusing that exact shape
/// instead of inventing a new one for just this screen.
class DictionaryWord {
  const DictionaryWord({
    required this.wordId,
    required this.word,
    required this.translation,
    this.translationTg,
    this.pronunciation,
    this.audioUrl,
    this.imageUrl,
    this.categoryId,
    this.categoryName,
    this.languageId,
    required this.lessonId,
    required this.courseId,
    required this.usedInLessonsCount,
  });

  factory DictionaryWord.fromJson(Map<String, dynamic> json) => DictionaryWord(
        wordId: json['wordId'] as String,
        word: json['word'] as String,
        translation: json['translation'] as String,
        translationTg: json['translationTg'] as String?,
        pronunciation: json['pronunciation'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        languageId: json['languageId'] as String?,
        lessonId: json['lessonId'] as String,
        courseId: json['courseId'] as String,
        usedInLessonsCount: json['usedInLessonsCount'] as int,
      );

  final String wordId;
  final String word;
  final String translation;
  final String? translationTg;
  final String? pronunciation;
  final String? audioUrl;
  final String? imageUrl;
  final String? categoryId;
  final String? categoryName;
  final String? languageId;
  /// This word's native (home) lesson/course — where its own edit/delete
  /// endpoints operate, regardless of how many other lessons reuse it.
  final String lessonId;
  final String courseId;
  final int usedInLessonsCount;
}

/// One page of the "Словарь" screen's list (§ shared dictionary, 2026-09-14).
class DictionaryPage {
  const DictionaryPage({required this.words, required this.total});
  factory DictionaryPage.fromJson(Map<String, dynamic> json) => DictionaryPage(
        words: (json['words'] as List<dynamic>).map((w) => DictionaryWord.fromJson(w as Map<String, dynamic>)).toList(),
        total: json['total'] as int,
      );
  final List<DictionaryWord> words;
  final int total;
}

class MediaLibraryEntry {
  const MediaLibraryEntry({required this.url, required this.label});
  factory MediaLibraryEntry.fromJson(Map<String, dynamic> json) =>
      MediaLibraryEntry(
        url: json['url'] as String,
        label: json['label'] as String,
      );
  final String url;
  final String label;
}

class MaterialLibraryEntry {
  const MaterialLibraryEntry({
    required this.label,
    required this.snippet,
    required this.materialText,
  });
  factory MaterialLibraryEntry.fromJson(Map<String, dynamic> json) =>
      MaterialLibraryEntry(
        label: json['label'] as String,
        snippet: json['snippet'] as String,
        materialText: json['materialText'] as String,
      );
  final String label;
  final String snippet;
  final String materialText;
}

/// Preview result from POST .../vocabulary/import/preview.
class ImportPreviewItem {
  const ImportPreviewItem({
    required this.index,
    required this.original,
    required this.status,
    this.message,
  });
  factory ImportPreviewItem.fromJson(Map<String, dynamic> json) =>
      ImportPreviewItem(
        index: json['index'] as int,
        original: json['original'] as String,
        status: json['status'] as String,
        message: json['message'] as String?,
      );
  final int index;
  final String original;
  final String status;
  final String? message;
}

class ImportPreview {
  const ImportPreview({
    required this.total,
    required this.newCount,
    required this.duplicateCount,
    required this.items,
  });
  factory ImportPreview.fromJson(Map<String, dynamic> json) => ImportPreview(
    total: json['total'] as int,
    newCount: json['newCount'] as int,
    duplicateCount: json['duplicateCount'] as int,
    items: (json['items'] as List<dynamic>)
        .map((i) => ImportPreviewItem.fromJson(i as Map<String, dynamic>))
        .toList(),
  );
  final int total;
  final int newCount;
  final int duplicateCount;
  final List<ImportPreviewItem> items;
}
