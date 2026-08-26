import 'exercise.dart';

List<Exercise> _blockQuestions(dynamic json) => ((json as List<dynamic>?) ?? const [])
    .cast<Map<String, dynamic>>()
    .map((q) => QuestionDto.fromJson(q))
    .map((q) => toExercise(q, q.id!))
    .toList();

/// Mirrors src/content/types.ts's VocabularyEntry.
class VocabularyEntry {
  const VocabularyEntry({required this.id, required this.german, required this.translation, this.pronunciation, this.audioUrl});

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) => VocabularyEntry(
        id: json['id'] as String,
        german: json['german'] as String,
        translation: json['translation'] as String,
        pronunciation: json['pronunciation'] as String?,
        audioUrl: json['audioUrl'] as String?,
      );

  final String id;
  final String german;
  final String translation;
  final String? pronunciation;
  final String? audioUrl;
}

/// Mirrors src/content/types.ts's LessonBlock discriminated union — one
/// entry per source line, never merged or reworded, exactly as the backend
/// (app/services/material.py, itself a port of parseLessonText.ts) emits.
sealed class MaterialBlock {
  const MaterialBlock();

  factory MaterialBlock.fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'title':
        return MaterialTitleBlock(json['text'] as String);
      case 'step':
        return MaterialStepBlock(number: json['number'] as int, title: json['title'] as String);
      case 'subheading':
        return MaterialSubheadingBlock(icon: json['icon'] as String?, text: json['text'] as String);
      case 'phrase':
        return MaterialPhraseBlock(
          icon: json['icon'] as String?,
          german: json['german'] as String,
          pronunciation: json['pronunciation'] as String?,
          translation: json['translation'] as String,
        );
      case 'block':
        return MaterialGenericBlock(
          id: json['id'] as String,
          title: json['title'] as String,
          content: json['content'] as String,
          questions: _blockQuestions(json['questions']),
        );
      case 'line':
      default:
        return MaterialLineBlock(text: json['text'] as String, tight: json['tight'] as bool? ?? false);
    }
  }
}

/// A teacher-authored block from the block-based material editor
/// (content-taxonomy plan, 2026-08-26) — replaces the free-text parser's
/// output entirely for any lesson that has been opened in that editor (see
/// app/services/material.py's get_new_material_blocks).
class MaterialGenericBlock extends MaterialBlock {
  const MaterialGenericBlock({required this.id, required this.title, required this.content, this.questions = const []});
  final String id;
  final String title;
  final String content;
  final List<Exercise> questions;
}

class MaterialTitleBlock extends MaterialBlock {
  const MaterialTitleBlock(this.text);
  final String text;
}

class MaterialStepBlock extends MaterialBlock {
  const MaterialStepBlock({required this.number, required this.title});
  final int number;
  final String title;
}

class MaterialSubheadingBlock extends MaterialBlock {
  const MaterialSubheadingBlock({this.icon, required this.text});
  final String? icon;
  final String text;
}

class MaterialPhraseBlock extends MaterialBlock {
  const MaterialPhraseBlock({this.icon, required this.german, this.pronunciation, required this.translation});
  final String? icon;
  final String german;
  final String? pronunciation;
  final String translation;
}

class MaterialLineBlock extends MaterialBlock {
  const MaterialLineBlock({required this.text, this.tight = false});
  final String text;
  final bool tight;
}

/// Mirrors src/content/types.ts's PhraseEntry.
class PhraseEntry {
  const PhraseEntry({required this.id, required this.german, this.pronunciation, required this.translation});

  factory PhraseEntry.fromJson(Map<String, dynamic> json) => PhraseEntry(
        id: json['id'] as String,
        german: json['german'] as String,
        pronunciation: json['pronunciation'] as String?,
        translation: json['translation'] as String,
      );

  final String id;
  final String german;
  final String? pronunciation;
  final String translation;
}

/// One resolved lesson's full content — assembled from either
/// GET /api/content/:lessonId (legacy) or a lesson entry inside
/// GET /api/courses/:courseId (builder), which return the same shape.
class LessonContentData {
  const LessonContentData({
    required this.lessonId,
    required this.title,
    required this.vocabulary,
    required this.newVocabulary,
    required this.material,
    required this.phrases,
    required this.videoUrl,
    required this.audioUrl,
    required this.blocks,
  });

  final String lessonId;
  final String title;
  final List<VocabularyEntry> vocabulary;
  final List<VocabularyEntry> newVocabulary;
  final List<MaterialBlock> material;
  final List<PhraseEntry> phrases;
  final String? videoUrl;
  final String? audioUrl;
  final List<QuestionBlock> blocks;

  List<Exercise> exercisesFor(String stage) => exercisesForStage(blocks, stage);

  static List<VocabularyEntry> _vocabList(dynamic json) =>
      (json as List<dynamic>).map((v) => VocabularyEntry.fromJson(v as Map<String, dynamic>)).toList();

  static List<MaterialBlock> _materialList(dynamic json) =>
      (json as List<dynamic>).map((b) => MaterialBlock.fromJson(b as Map<String, dynamic>)).toList();

  static List<PhraseEntry> _phraseList(dynamic json) =>
      (json as List<dynamic>).map((p) => PhraseEntry.fromJson(p as Map<String, dynamic>)).toList();

  static List<QuestionBlock> _blockList(dynamic json) =>
      (json as List<dynamic>).map((b) => QuestionBlock.fromJson(b as Map<String, dynamic>)).toList();

  /// From GET /api/content/:lessonId's {content: {...}} — the legacy shape.
  factory LessonContentData.fromLegacyJson(String lessonId, Map<String, dynamic> json) => LessonContentData(
        lessonId: lessonId,
        title: _titleFromMaterial(_materialList(json['material'] ?? [])) ?? lessonId,
        vocabulary: _vocabList(json['vocabulary'] ?? []),
        newVocabulary: _vocabList(json['newVocabulary'] ?? []),
        material: _materialList(json['material'] ?? []),
        phrases: _phraseList(json['phrases'] ?? []),
        videoUrl: json['videoUrl'] as String?,
        audioUrl: json['audioUrl'] as String?,
        blocks: _blockList(json['blocks'] ?? []),
      );

  /// From one lesson entry inside GET /api/courses/:courseId — the builder
  /// shape (same field names, just nested one level differently server-side
  /// — see courses.py's lesson_dto()). Unlike the legacy shape, `title` is
  /// always a real, admin-set CourseLesson field — no material-block
  /// fallback needed.
  factory LessonContentData.fromBuilderJson(Map<String, dynamic> json) => LessonContentData(
        lessonId: json['id'] as String,
        title: json['title'] as String,
        vocabulary: _vocabList(json['vocabulary'] ?? []),
        newVocabulary: _vocabList(json['newVocabulary'] ?? []),
        material: _materialList(json['material'] ?? []),
        phrases: _phraseList(json['phrases'] ?? []),
        videoUrl: json['videoUrl'] as String?,
        audioUrl: json['audioUrl'] as String?,
        blocks: _blockList(json['blocks'] ?? []),
      );

  static String? _titleFromMaterial(List<MaterialBlock> blocks) {
    for (final b in blocks) {
      if (b is MaterialTitleBlock) return b.text;
    }
    return null;
  }
}
