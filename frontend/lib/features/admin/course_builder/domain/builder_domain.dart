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
  });

  factory AdminVocabWord.fromJson(Map<String, dynamic> json) => AdminVocabWord(
    id: json['id'] as String,
    german: json['german'] as String,
    translation: json['translation'] as String,
    pronunciation: json['pronunciation'] as String? ?? '',
    audioUrl: json['audioUrl'] as String?,
    imageUrl: json['imageUrl'] as String?,
  );

  final String id;
  final String german;
  final String translation;
  final String pronunciation;
  final String? audioUrl;
  final String? imageUrl;
}

class AdminBlock {
  const AdminBlock({
    required this.id,
    required this.stage,
    required this.title,
    required this.position,
    required this.questions,
  });

  factory AdminBlock.fromJson(Map<String, dynamic> json) => AdminBlock(
    id: json['id'] as String,
    stage: json['stage'] as String,
    title: json['title'] as String,
    position: json['position'] as int,
    // The backend's own "questions" field merges real, locally-editable
    // LessonQuestion rows with reusable-pool questions placed in the same
    // block (so the STUDENT-facing quiz sees everything regardless of
    // mechanism, § approved rule 4, 2026-08-27) — this admin-only model
    // keeps just the "legacy" ones (§ course-builder redesign bugfix,
    // 2026-09-01): BlockEditor's static list is a local draft that gets
    // wholesale-replaced on "Сохранить вопросы", and a pool question
    // slipping in there would get silently duplicated into a brand new
    // LessonQuestion row on save, alongside the untouched pool original.
    // Pool questions are shown (and edited) exclusively through
    // PoolQuestionsSection, which fetches its own list directly.
    questions: (json['questions'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((q) => q['source'] != 'pool')
        .map(questionDraftFromWire)
        .toList(),
  );

  final String id;
  final String stage;
  final String title;
  final int position;
  final List<QuestionDraft> questions;
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

  List<AdminBlock> blocksFor(String stage) =>
      blocks.where((b) => b.stage == stage).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
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
  );

  final String id;
  final String title;
  final String description;
  final String? coverUrl;
  final String status;
  final int position;
  final String? levelId;
  final List<AdminLesson> lessons;
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
