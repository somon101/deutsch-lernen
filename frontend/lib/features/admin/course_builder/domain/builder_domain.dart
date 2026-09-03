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
  );

  final String id;
  final String german;
  final String translation;
  final String pronunciation;
  final String? audioUrl;
  final String? imageUrl;
  final Map<String, String> translations;
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
  });

  factory AdminGraphNode.fromJson(Map<String, dynamic> json) => AdminGraphNode(
    id: json['id'] as String,
    type: json['type'] as String,
    refId: json['refId'] as String?,
    mediaUrl: json['mediaUrl'] as String?,
    title: json['title'] as String,
    posX: (json['posX'] as num).toDouble(),
    posY: (json['posY'] as num).toDouble(),
  );

  final String id;
  final String type;
  final String? refId;
  final String? mediaUrl;
  final String title;
  final double posX;
  final double posY;

  AdminGraphNode copyWith({double? posX, double? posY, String? title, String? mediaUrl}) => AdminGraphNode(
    id: id,
    type: type,
    refId: refId,
    mediaUrl: mediaUrl ?? this.mediaUrl,
    title: title ?? this.title,
    posX: posX ?? this.posX,
    posY: posY ?? this.posY,
  );
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

class WordLibraryEntry {
  const WordLibraryEntry({
    required this.german,
    required this.translation,
    required this.pronunciation,
  });
  factory WordLibraryEntry.fromJson(Map<String, dynamic> json) =>
      WordLibraryEntry(
        german: json['german'] as String,
        translation: json['translation'] as String,
        pronunciation: json['pronunciation'] as String? ?? '',
      );
  final String german;
  final String translation;
  final String pronunciation;
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
