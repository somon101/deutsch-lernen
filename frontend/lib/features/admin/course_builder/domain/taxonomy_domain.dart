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

class AdminMaterialBlockTranslation {
  const AdminMaterialBlockTranslation({required this.title, required this.content});

  factory AdminMaterialBlockTranslation.fromJson(Map<String, dynamic> json) =>
      AdminMaterialBlockTranslation(title: json['title'] as String, content: json['content'] as String? ?? '');

  final String title;
  final String content;
}

class AdminMaterialBlock {
  const AdminMaterialBlock({
    required this.id,
    required this.materialId,
    required this.title,
    required this.content,
    required this.position,
    this.translations = const {},
  });

  factory AdminMaterialBlock.fromJson(Map<String, dynamic> json) => AdminMaterialBlock(
        id: json['id'] as String,
        materialId: json['materialId'] as String,
        title: json['title'] as String,
        content: json['content'] as String,
        position: json['position'] as int,
        // Same shape/rationale as AdminCourse.translations (§ course content
        // language, 2026-09-04).
        translations: (json['translations'] as Map<String, dynamic>?)?.map(
              (locale, v) => MapEntry(locale, AdminMaterialBlockTranslation.fromJson(v as Map<String, dynamic>)),
            ) ??
            const {},
      );

  final String id;
  final String materialId;
  final String title;
  final String content;
  final int position;
  final Map<String, AdminMaterialBlockTranslation> translations;
}

/// One question in the reusable pool — unlike QuestionDraft (a local, unsaved
/// edit), this always has a stable `id` (the real question_id), since it's
/// only ever constructed from something the server already has.
/// One locale's variant of a pool Question's text (§ course content
/// language, 2026-09-04) — every field optional, since a given `kind` only
/// ever fills in the subset it actually uses. Mirrors backend's
/// QuestionTranslation; `data` (match pairs) isn't exposed here yet — see
/// the admin question tile's own translation section for why.
class QuestionTranslationFields {
  const QuestionTranslationFields({this.prompt, this.options, this.correctAnswer});

  factory QuestionTranslationFields.fromJson(Map<String, dynamic> json) => QuestionTranslationFields(
        prompt: json['prompt'] as String?,
        options: (json['options'] as List<dynamic>?)?.cast<String>(),
        correctAnswer: json['correctAnswer'] as String?,
      );

  final String? prompt;
  final List<String>? options;
  final String? correctAnswer;
}

class PoolQuestion {
  const PoolQuestion({
    required this.id,
    required this.topicId,
    required this.draft,
    this.placementId,
    this.topicName,
    this.verifiesBlockId,
    this.verifiesBlockTitle,
    this.placementCount = 1,
  });

  factory PoolQuestion.fromJson(Map<String, dynamic> json) => PoolQuestion(
        id: json['id'] as String,
        topicId: json['topicId'] as String?,
        draft: questionDraftFromWire(json),
        placementId: json['placementId'] as String?,
        topicName: json['topicName'] as String?,
        verifiesBlockId: json['verifiesBlockId'] as String?,
        verifiesBlockTitle: json['verifiesBlockTitle'] as String?,
        placementCount: json['placementCount'] as int? ?? 1,
      );

  final String id;
  final String? topicId;
  final QuestionDraft draft;
  // Set only when this came from listing a block's attached questions
  // (GET .../blocks/{id}/questions) — identifies the specific link so it
  // can be removed without touching the shared Question itself.
  final String? placementId;
  // Resolved Topic name — the teacher should see the actual name, not just
  // an id (§5 of the approved rule, 2026-08-27).
  final String? topicName;
  // Only meaningful for a lessonBlock-scoped listing: this quiz-stage
  // placement is optionally tagged as testing a specific reading-content
  // MaterialBlock, independent of where the question is actually shown
  // (§4). Null when no such tag was set.
  final String? verifiesBlockId;
  final String? verifiesBlockTitle;
  // How many places this Question is placed in total (§ course-builder
  // redesign, "в пуле · N мест" chip, 2026-09-01) — 1 means it only lives
  // here ("только здесь"), 2+ means it's genuinely reused elsewhere too.
  final int placementCount;
}

/// Every place one Question is actually shown to a learner, resolved to a
/// human-readable chain — GET /api/questions/{id}/placements (§5/§6/§7).
class QuestionUsage {
  const QuestionUsage({
    required this.placementId,
    required this.location,
    this.stage,
    this.stageLabel,
    this.lessonTitle,
    this.blockTitle,
    this.verifiesBlockId,
    this.setName,
  });

  factory QuestionUsage.fromJson(Map<String, dynamic> json) => QuestionUsage(
        placementId: json['placementId'] as String,
        location: json['location'] as String,
        stage: json['stage'] as String?,
        stageLabel: json['stageLabel'] as String?,
        lessonTitle: json['lessonTitle'] as String?,
        blockTitle: json['blockTitle'] as String?,
        verifiesBlockId: json['verifiesBlockId'] as String?,
        setName: json['setName'] as String?,
      );

  final String placementId;
  // "material" | "lessonBlock" | "legacy"
  final String location;
  final String? stage;
  final String? stageLabel;
  final String? lessonTitle;
  final String? blockTitle;
  final String? verifiesBlockId;
  final String? setName;
}

/// One quiz-stage question that's tagged as verifying a MaterialBlock, from
/// the *material block's* point of view (§ course-builder redesign, "Проверяет
/// этот блок" section, 2026-09-01) — GET .../blocks/{id}/verifying-questions.
/// The question doesn't live here; this is purely a read-only pointer to
/// where it actually is, for the teacher to click through to it.
class VerifyingQuestion {
  const VerifyingQuestion({
    required this.placementId,
    required this.draft,
    required this.courseId,
    required this.lessonId,
    required this.blockId,
    required this.stage,
    required this.stageLabel,
    required this.lessonTitle,
    required this.blockTitle,
  });

  factory VerifyingQuestion.fromJson(Map<String, dynamic> json) => VerifyingQuestion(
        placementId: json['placementId'] as String,
        draft: questionDraftFromWire(json),
        courseId: json['courseId'] as String?,
        lessonId: json['lessonId'] as String?,
        blockId: json['blockId'] as String?,
        stage: json['stage'] as String?,
        stageLabel: json['stageLabel'] as String?,
        lessonTitle: json['lessonTitle'] as String?,
        blockTitle: json['blockTitle'] as String?,
      );

  final String placementId;
  final QuestionDraft draft;
  final String? courseId;
  final String? lessonId;
  final String? blockId;
  final String? stage;
  final String? stageLabel;
  final String? lessonTitle;
  final String? blockTitle;
}

class SimilarQuestionMatch {
  const SimilarQuestionMatch({required this.question, required this.score, this.location});
  factory SimilarQuestionMatch.fromJson(Map<String, dynamic> json) => SimilarQuestionMatch(
    question: PoolQuestion.fromJson(json['question'] as Map<String, dynamic>),
    score: json['score'] as int,
    location: json['location'] as String?,
  );
  final PoolQuestion question;
  final int score;
  // "Урок «X» → Практика" — the first place this question already lives,
  // if any (§ course-builder redesign, "Похоже на существующее задание"
  // dialog, 2026-09-01). Null for a question with no placement at all yet.
  final String? location;
}

/// Where a reusable Question is placed — mirrors the backend's
/// QuestionPlacement. Usually exactly one of materialBlockId/lessonBlockId/
/// (legacyLessonId+legacySetName) is non-null (its real home), EXCEPT a
/// quiz-stage placement (lessonBlockId set) may ALSO carry a materialBlockId
/// as its "verifies this reading block" tag (§4 of the approved rule,
/// 2026-08-27) — that combination means "shown in the lessonBlock, tagged as
/// verifying the materialBlock", never "also placed in the material".
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

/// One reading (MaterialBlock) row on the "Карта урока" overview (§8 of the
/// course-builder redesign, 2026-09-01), with every quiz question elsewhere
/// tagged as verifying it.
class MapMaterialBlock {
  const MapMaterialBlock({required this.id, required this.title, required this.verifiedBy});

  factory MapMaterialBlock.fromJson(Map<String, dynamic> json) => MapMaterialBlock(
        id: json['id'] as String,
        title: json['title'] as String,
        verifiedBy: (json['verifiedBy'] as List<dynamic>)
            .map((e) => MapVerifyingRef.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  final String id;
  final String title;
  final List<MapVerifyingRef> verifiedBy;

  bool get hasWarning => verifiedBy.isEmpty;
}

class MapVerifyingRef {
  const MapVerifyingRef({
    required this.questionId,
    required this.stage,
    required this.stageLabel,
    required this.blockId,
    required this.blockTitle,
  });

  factory MapVerifyingRef.fromJson(Map<String, dynamic> json) => MapVerifyingRef(
        questionId: json['questionId'] as String,
        stage: json['stage'] as String?,
        stageLabel: json['stageLabel'] as String?,
        blockId: json['blockId'] as String?,
        blockTitle: json['blockTitle'] as String?,
      );

  final String questionId;
  final String? stage;
  final String? stageLabel;
  final String? blockId;
  final String? blockTitle;
}

/// One quiz question row on the map — the running 1..N number matches what
/// the teacher already sees inside the block's own editor.
class MapQuestion {
  const MapQuestion({
    required this.id,
    required this.number,
    required this.kind,
    required this.prompt,
    required this.source,
    required this.verifiesBlockId,
    required this.verifiesBlockTitle,
  });

  factory MapQuestion.fromJson(Map<String, dynamic> json) => MapQuestion(
        id: json['id'] as String,
        number: json['number'] as int,
        kind: json['kind'] as String,
        prompt: json['prompt'] as String? ?? '',
        source: json['source'] as String,
        verifiesBlockId: json['verifiesBlockId'] as String?,
        verifiesBlockTitle: json['verifiesBlockTitle'] as String?,
      );

  final String id;
  final int number;
  final String kind;
  final String prompt;
  final String source;
  final String? verifiesBlockId;
  final String? verifiesBlockTitle;

  bool get hasWarning => verifiesBlockId == null;
}

class MapQuizBlock {
  const MapQuizBlock({required this.id, required this.title, required this.questions});

  factory MapQuizBlock.fromJson(Map<String, dynamic> json) => MapQuizBlock(
        id: json['id'] as String,
        title: json['title'] as String,
        questions: (json['questions'] as List<dynamic>).map((e) => MapQuestion.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final String id;
  final String title;
  final List<MapQuestion> questions;
}

class MapStage {
  const MapStage({required this.stage, required this.stageLabel, required this.blocks});

  factory MapStage.fromJson(Map<String, dynamic> json) => MapStage(
        stage: json['stage'] as String,
        stageLabel: json['stageLabel'] as String,
        blocks: (json['blocks'] as List<dynamic>).map((e) => MapQuizBlock.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final String stage;
  final String stageLabel;
  final List<MapQuizBlock> blocks;
}

/// The full "Карта урока" read-only overview for one lesson (§8).
class LessonConnectionsMap {
  const LessonConnectionsMap({required this.materials, required this.stages});

  factory LessonConnectionsMap.fromJson(Map<String, dynamic> json) => LessonConnectionsMap(
        materials: (json['materials'] as List<dynamic>).map((e) => MapMaterialBlock.fromJson(e as Map<String, dynamic>)).toList(),
        stages: (json['stages'] as List<dynamic>).map((e) => MapStage.fromJson(e as Map<String, dynamic>)).toList(),
      );

  final List<MapMaterialBlock> materials;
  final List<MapStage> stages;
}

/// One row of the course-level map (§8: "строки это уроки, и видно, какой
/// урок недособран, без захода внутрь").
class CourseMapLesson {
  const CourseMapLesson({
    required this.id,
    required this.title,
    required this.materialCount,
    required this.materialWarnings,
    required this.questionCount,
    required this.questionWarnings,
  });

  factory CourseMapLesson.fromJson(Map<String, dynamic> json) => CourseMapLesson(
        id: json['id'] as String,
        title: json['title'] as String,
        materialCount: json['materialCount'] as int,
        materialWarnings: json['materialWarnings'] as int,
        questionCount: json['questionCount'] as int,
        questionWarnings: json['questionWarnings'] as int,
      );

  final String id;
  final String title;
  final int materialCount;
  final int materialWarnings;
  final int questionCount;
  final int questionWarnings;

  bool get isFullyLinked => materialWarnings == 0 && questionWarnings == 0;
}

class CourseConnectionsMap {
  const CourseConnectionsMap({required this.lessons});
  factory CourseConnectionsMap.fromJson(Map<String, dynamic> json) => CourseConnectionsMap(
        lessons: (json['lessons'] as List<dynamic>).map((e) => CourseMapLesson.fromJson(e as Map<String, dynamic>)).toList(),
      );
  final List<CourseMapLesson> lessons;
}
