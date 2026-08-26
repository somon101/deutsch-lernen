import 'block_question.dart';

/// Domain models for the Language/Level/Topic/Material/MaterialBlock/
/// reusable-Question layer added on top of the existing course-builder
/// models in builder_domain.dart (Course/CourseLesson/LessonBlock/
/// LessonQuestion, all untouched and still fully working).

class AdminLanguage {
  const AdminLanguage({required this.id, required this.name});
  factory AdminLanguage.fromJson(Map<String, dynamic> json) => AdminLanguage(id: json['id'] as String, name: json['name'] as String);
  final String id;
  final String name;
}

class AdminLevel {
  const AdminLevel({required this.id, required this.languageId, required this.code, required this.name, required this.position});
  factory AdminLevel.fromJson(Map<String, dynamic> json) => AdminLevel(
        id: json['id'] as String,
        languageId: json['languageId'] as String,
        code: json['code'] as String,
        name: json['name'] as String,
        position: json['position'] as int,
      );
  final String id;
  final String languageId;
  final String code;
  final String name;
  final int position;
}

class AdminTopic {
  const AdminTopic({required this.id, required this.languageId, required this.name});
  factory AdminTopic.fromJson(Map<String, dynamic> json) =>
      AdminTopic(id: json['id'] as String, languageId: json['languageId'] as String, name: json['name'] as String);
  final String id;
  final String languageId;
  final String name;
}

class AdminMaterial {
  const AdminMaterial({
    required this.id,
    required this.courseId,
    required this.lessonId,
    required this.materialType,
    required this.title,
    required this.topicId,
    required this.position,
  });

  factory AdminMaterial.fromJson(Map<String, dynamic> json) => AdminMaterial(
        id: json['id'] as String,
        courseId: json['courseId'] as String,
        lessonId: json['lessonId'] as String,
        materialType: json['materialType'] as String,
        title: json['title'] as String,
        topicId: json['topicId'] as String?,
        position: json['position'] as int,
      );

  final String id;
  final String courseId;
  final String lessonId;
  final String materialType;
  final String title;
  final String? topicId;
  final int position;
}

class AdminMaterialBlock {
  const AdminMaterialBlock({required this.id, required this.materialId, required this.title, required this.content, required this.position});

  factory AdminMaterialBlock.fromJson(Map<String, dynamic> json) => AdminMaterialBlock(
        id: json['id'] as String,
        materialId: json['materialId'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        position: json['position'] as int,
      );

  final String id;
  final String materialId;
  final String title;
  final String content;
  final int position;
}

/// One question in the reusable pool — unlike QuestionDraft (a local, unsaved
/// edit), this always has a stable `id` (the real question_id), since it's
/// only ever constructed from something the server already has.
class PoolQuestion {
  const PoolQuestion({required this.id, required this.topicId, required this.draft, this.placementId});

  factory PoolQuestion.fromJson(Map<String, dynamic> json) => PoolQuestion(
        id: json['id'] as String,
        topicId: json['topicId'] as String?,
        draft: questionDraftFromWire(json),
        placementId: json['placementId'] as String?,
      );

  final String id;
  final String? topicId;
  final QuestionDraft draft;
  // Set only when this came from listing a MaterialBlock's attached
  // questions (GET .../blocks/{id}/questions) — identifies the specific
  // link so it can be removed without touching the shared Question itself.
  final String? placementId;
}

class SimilarQuestionMatch {
  const SimilarQuestionMatch({required this.question, required this.score});
  factory SimilarQuestionMatch.fromJson(Map<String, dynamic> json) =>
      SimilarQuestionMatch(question: PoolQuestion.fromJson(json['question'] as Map<String, dynamic>), score: json['score'] as int);
  final PoolQuestion question;
  final int score;
}

/// Where a reusable Question is placed — exactly one of materialBlockId/
/// lessonBlockId/(legacyLessonId+legacySetName) is non-null, mirroring the
/// backend's QuestionPlacement.
class AdminQuestionPlacement {
  const AdminQuestionPlacement({
    required this.id,
    required this.questionId,
    required this.materialBlockId,
    required this.lessonBlockId,
    required this.legacyLessonId,
    required this.legacySetName,
    required this.position,
  });

  factory AdminQuestionPlacement.fromJson(Map<String, dynamic> json) => AdminQuestionPlacement(
        id: json['id'] as String,
        questionId: json['questionId'] as String,
        materialBlockId: json['materialBlockId'] as String?,
        lessonBlockId: json['lessonBlockId'] as String?,
        legacyLessonId: json['legacyLessonId'] as String?,
        legacySetName: json['legacySetName'] as String?,
        position: json['position'] as int,
      );

  final String id;
  final String questionId;
  final String? materialBlockId;
  final String? lessonBlockId;
  final String? legacyLessonId;
  final String? legacySetName;
  final int position;
}
