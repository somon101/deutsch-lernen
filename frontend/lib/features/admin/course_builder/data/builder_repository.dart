import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../domain/block_question.dart';
import '../domain/builder_domain.dart';
import '../domain/taxonomy_domain.dart';

/// Port of src/admin/builderApi.ts — full CRUD surface for the course
/// builder (courses/lessons/vocabulary/blocks/library search/media), plus
/// the two "run mutation, get the whole course back" call sites the UI
/// always re-fetches through.
class BuilderRepository {
  BuilderRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/builder/courses';

  Future<List<AdminCourseSummary>> listCourses() async {
    final res = await _api.get(_base);
    return (res['courses'] as List<dynamic>)
        .map((c) => AdminCourseSummary.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<AdminCourse> getCourse(String courseId) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(courseId)}');
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> createCourse({
    required String title,
    String? description,
    String? levelId,
  }) async {
    final res = await _api.post(
      _base,
      body: {'title': title, 'description': ?description, 'levelId': ?levelId},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> updateCourse(
    String courseId, {
    String? title,
    String? description,
    String? status,
    String? levelId,
  }) async {
    final res = await _api.patch(
      '$_base/${Uri.encodeComponent(courseId)}',
      body: {'title': ?title, 'description': ?description, 'status': ?status, 'levelId': ?levelId},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<void> deleteCourse(String courseId) async {
    await _api.delete('$_base/${Uri.encodeComponent(courseId)}');
  }

  Future<List<AdminCourseSummary>> reorderCourses(List<String> ids) async {
    final res = await _api.post('$_base/reorder', body: {'ids': ids});
    return (res['courses'] as List<dynamic>)
        .map((c) => AdminCourseSummary.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<AdminCourse> uploadCourseCover(
    String courseId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final res = await _api.postMultipart(
      '$_base/${Uri.encodeComponent(courseId)}/cover',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeCourseCover(String courseId) async {
    final res = await _api.deleteExpectingBody(
      '$_base/${Uri.encodeComponent(courseId)}/cover',
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> addLesson(
    String courseId, {
    required String title,
    String? description,
  }) async {
    final res = await _api.post(
      '$_base/${Uri.encodeComponent(courseId)}/lessons',
      body: {'title': title, 'description': ?description},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> updateLesson(
    String courseId,
    String lessonId, {
    String? title,
    String? description,
    String? materialText,
  }) async {
    final res = await _api.patch(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}',
      body: {
        'title': ?title,
        'description': ?description,
        'materialText': ?materialText,
      },
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeLesson(String courseId, String lessonId) async {
    await _api.delete(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}',
    );
    return getCourse(courseId);
  }

  /// Manual "Отправить уведомление" — sends regardless of the auto-send
  /// setting (see NotificationSettingsRepository for that toggle).
  Future<void> notifyLessonCreated(String courseId, String lessonId) async {
    await _api.post(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/notify',
    );
  }

  Future<AdminCourse> reorderLessons(String courseId, List<String> ids) async {
    final res = await _api.post(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/reorder',
      body: {'ids': ids},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> uploadLessonMedia(
    String courseId,
    String lessonId, {
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    final res = await _api.postMultipart(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      fields: {'kind': kind},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeLessonMedia(
    String courseId,
    String lessonId,
    String kind,
  ) async {
    final res = await _api.deleteExpectingBody(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media?kind=${Uri.encodeComponent(kind)}',
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> reuseLessonMedia(
    String courseId,
    String lessonId,
    String kind,
    String url,
  ) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media/reuse',
      body: {'kind': kind, 'url': url},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<List<WordLibraryEntry>> searchWordLibrary(String query) async {
    final res = await _api.get(
      '/api/builder/words/search',
      query: {'q': query},
    );
    return (res['words'] as List<dynamic>)
        .map((w) => WordLibraryEntry.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  Future<List<MediaLibraryEntry>> listMediaLibrary(String kind) async {
    final res = await _api.get(
      '/api/builder/media/library',
      query: {'kind': kind},
    );
    return (res['items'] as List<dynamic>)
        .map((m) => MediaLibraryEntry.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<QuestionDraft>> searchQuestions(String query) async {
    final res = await _api.get(
      '/api/builder/questions/search',
      query: {'q': query},
    );
    return (res['questions'] as List<dynamic>)
        .map((q) => questionDraftFromWire(q as Map<String, dynamic>))
        .toList();
  }

  Future<List<MaterialLibraryEntry>> searchMaterials(String query) async {
    final res = await _api.get(
      '/api/builder/materials/search',
      query: {'q': query},
    );
    return (res['materials'] as List<dynamic>)
        .map((m) => MaterialLibraryEntry.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  String _vocabBase(String courseId, String lessonId) =>
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/vocabulary';

  Future<void> addWord(
    String courseId,
    String lessonId, {
    required String german,
    required String translation,
    required String pronunciation,
  }) async {
    await _api.post(
      _vocabBase(courseId, lessonId),
      body: {
        'german': german,
        'translation': translation,
        'pronunciation': pronunciation,
      },
    );
  }

  Future<void> updateWord(
    String courseId,
    String lessonId,
    String wordId, {
    String? german,
    String? translation,
    String? pronunciation,
  }) async {
    await _api.patch(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}',
      body: {
        'german': ?german,
        'translation': ?translation,
        'pronunciation': ?pronunciation,
      },
    );
  }

  Future<void> removeWord(
    String courseId,
    String lessonId,
    String wordId,
  ) async {
    await _api.delete(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}',
    );
  }

  Future<void> uploadWordAudio(
    String courseId,
    String lessonId,
    String wordId, {
    required List<int> bytes,
    required String filename,
  }) async {
    await _api.postMultipart(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/audio',
      fieldName: 'audio',
      bytes: bytes,
      filename: filename,
    );
  }

  Future<void> removeWordAudio(
    String courseId,
    String lessonId,
    String wordId,
  ) async {
    await _api.delete(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/audio',
    );
  }

  /// Mirrors uploadWordAudio/removeWordAudio above one-for-one (§ word
  /// cards, 2026-08-31) — a word's photo.
  Future<void> uploadWordImage(
    String courseId,
    String lessonId,
    String wordId, {
    required List<int> bytes,
    required String filename,
  }) async {
    await _api.postMultipart(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/image',
      fieldName: 'image',
      bytes: bytes,
      filename: filename,
    );
  }

  Future<void> removeWordImage(
    String courseId,
    String lessonId,
    String wordId,
  ) async {
    await _api.delete(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/image',
    );
  }

  Future<ImportPreview> previewVocabularyImport(
    String courseId,
    String lessonId,
    List<Map<String, String>> words,
  ) async {
    final res = await _api.post(
      '${_vocabBase(courseId, lessonId)}/import/preview',
      body: {'words': words},
    );
    return ImportPreview.fromJson(res['preview'] as Map<String, dynamic>);
  }

  Future<({int addedCount, List<ImportPreviewItem> skipped})> importVocabulary(
    String courseId,
    String lessonId,
    List<Map<String, String>> words,
  ) async {
    final res = await _api.post(
      '${_vocabBase(courseId, lessonId)}/import',
      body: {'words': words},
    );
    final skipped = (res['skipped'] as List<dynamic>)
        .map((s) => ImportPreviewItem.fromJson(s as Map<String, dynamic>))
        .toList();
    return (addedCount: res['addedCount'] as int, skipped: skipped);
  }

  String _blocksBase(String courseId, String lessonId) =>
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/blocks';

  Future<void> addBlock(
    String courseId,
    String lessonId,
    String stage,
    String title,
  ) async {
    await _api.post(
      _blocksBase(courseId, lessonId),
      body: {'stage': stage, 'title': title},
    );
  }

  Future<void> renameBlock(
    String courseId,
    String lessonId,
    String blockId,
    String title,
  ) async {
    await _api.patch(
      '${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}',
      body: {'title': title},
    );
  }

  Future<void> removeBlock(
    String courseId,
    String lessonId,
    String blockId,
  ) async {
    await _api.delete(
      '${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}',
    );
  }

  Future<void> reorderBlocks(
    String courseId,
    String lessonId,
    String stage,
    List<String> ids,
  ) async {
    await _api.post(
      '${_blocksBase(courseId, lessonId)}/reorder',
      body: {'stage': stage, 'ids': ids},
    );
  }

  Future<void> saveBlockQuestions(
    String courseId,
    String lessonId,
    String blockId,
    List<QuestionDraft> questions,
  ) async {
    await _api.put(
      '${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}/questions',
      body: {
        'questions': [for (final q in questions) q.toWire()],
      },
    );
  }

  // ---------------------------------------------------------------------
  // Language / Level / Topic
  // ---------------------------------------------------------------------

  Future<List<AdminLanguage>> listLanguages() async {
    final res = await _api.get('/api/languages');
    return (res['languages'] as List<dynamic>).map((l) => AdminLanguage.fromJson(l as Map<String, dynamic>)).toList();
  }

  /// Returns (language, existing) — `existing` is true when the server
  /// found and returned an already-there Language with the same name
  /// instead of creating a duplicate, same convention as createTopic below.
  Future<(AdminLanguage, bool)> createLanguage(String name, {bool force = false}) async {
    final res = await _api.post('/api/languages', body: {'name': name, 'force': force});
    return (AdminLanguage.fromJson(res['language'] as Map<String, dynamic>), res['existing'] as bool);
  }

  Future<List<AdminLevel>> listLevels({String? languageId}) async {
    final res = await _api.get('/api/levels', query: {'languageId': ?languageId});
    return (res['levels'] as List<dynamic>).map((l) => AdminLevel.fromJson(l as Map<String, dynamic>)).toList();
  }

  Future<AdminLevel> createLevel(String languageId, String code, String name, {int position = 0}) async {
    final res = await _api.post('/api/levels', body: {'languageId': languageId, 'code': code, 'name': name, 'position': position});
    return AdminLevel.fromJson(res['level'] as Map<String, dynamic>);
  }

  Future<List<AdminTopic>> listTopics({String? languageId}) async {
    final res = await _api.get('/api/topics', query: {'languageId': ?languageId});
    return (res['topics'] as List<dynamic>).map((t) => AdminTopic.fromJson(t as Map<String, dynamic>)).toList();
  }

  /// Returns (topic, existing) — `existing` is true when the server found
  /// and returned an already-there Topic with the same name instead of
  /// creating a duplicate (§32).
  Future<(AdminTopic, bool)> createTopic(String languageId, String name, {bool force = false}) async {
    final res = await _api.post('/api/topics', body: {'languageId': languageId, 'name': name, 'force': force});
    return (AdminTopic.fromJson(res['topic'] as Map<String, dynamic>), res['existing'] as bool);
  }

  /// Deletes the tag itself — Materials/Questions that had it keep existing,
  /// their topicId just goes back to null (server-side FK is ON DELETE SET
  /// NULL).
  Future<void> deleteTopic(String topicId) async {
    await _api.delete('/api/topics/${Uri.encodeComponent(topicId)}');
  }

  // ---------------------------------------------------------------------
  // Material / MaterialBlock
  // ---------------------------------------------------------------------

  Future<List<AdminMaterial>> listMaterials(String lessonId) async {
    final res = await _api.get('/api/materials', query: {'lessonId': lessonId});
    return (res['materials'] as List<dynamic>).map((m) => AdminMaterial.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<AdminMaterial> createMaterial({
    required String courseId,
    required String lessonId,
    required String materialType,
    required String title,
    String? topicId,
  }) async {
    final res = await _api.post(
      '/api/materials',
      body: {'courseId': courseId, 'lessonId': lessonId, 'materialType': materialType, 'title': title, 'topicId': ?topicId},
    );
    return AdminMaterial.fromJson(res['material'] as Map<String, dynamic>);
  }

  Future<AdminMaterial> updateMaterial(String materialId, {String? title, String? topicId}) async {
    final res = await _api.patch('/api/materials/${Uri.encodeComponent(materialId)}', body: {'title': ?title, 'topicId': topicId});
    return AdminMaterial.fromJson(res['material'] as Map<String, dynamic>);
  }

  Future<void> deleteMaterial(String materialId) async {
    await _api.delete('/api/materials/${Uri.encodeComponent(materialId)}');
  }

  Future<List<AdminMaterialBlock>> listMaterialBlocks(String materialId) async {
    final res = await _api.get('/api/materials/${Uri.encodeComponent(materialId)}/blocks');
    return (res['blocks'] as List<dynamic>).map((b) => AdminMaterialBlock.fromJson(b as Map<String, dynamic>)).toList();
  }

  Future<AdminMaterialBlock> addMaterialBlock(String materialId, {required String title, required String content}) async {
    final res = await _api.post('/api/materials/${Uri.encodeComponent(materialId)}/blocks', body: {'title': title, 'content': content});
    return AdminMaterialBlock.fromJson(res['block'] as Map<String, dynamic>);
  }

  Future<AdminMaterialBlock> updateMaterialBlock(String blockId, {required String title, required String content}) async {
    final res = await _api.patch('/api/materials/blocks/${Uri.encodeComponent(blockId)}', body: {'title': title, 'content': content});
    return AdminMaterialBlock.fromJson(res['block'] as Map<String, dynamic>);
  }

  Future<void> deleteMaterialBlock(String blockId) async {
    await _api.delete('/api/materials/blocks/${Uri.encodeComponent(blockId)}');
  }

  Future<void> reorderMaterialBlocks(String materialId, List<String> blockIds) async {
    await _api.put('/api/materials/${Uri.encodeComponent(materialId)}/blocks/reorder', body: {'blockIds': blockIds});
  }

  /// Every reusable question already attached to this block — was missing
  /// entirely before (teachers could only add/search, never see what a
  /// block already had). Works for either a MaterialBlock (pass
  /// `materialBlockId`) or a quiz LessonBlock — minitest/practice/review —
  /// (pass `lessonBlockId`); exactly one must be given, matching the
  /// backend's two equivalent endpoints.
  Future<List<PoolQuestion>> listBlockQuestions({String? materialBlockId, String? lessonBlockId}) async {
    final path = materialBlockId != null
        ? '/api/materials/blocks/${Uri.encodeComponent(materialBlockId)}/questions'
        : '/api/lesson-blocks/${Uri.encodeComponent(lessonBlockId!)}/questions';
    final res = await _api.get(path);
    return (res['questions'] as List<dynamic>).map((q) => PoolQuestion.fromJson(q as Map<String, dynamic>)).toList();
  }

  /// The reverse of [listBlockQuestions]'s materialBlockId case (§
  /// course-builder redesign, "Проверяет этот блок" section, 2026-09-01):
  /// quiz-stage questions elsewhere that are tagged as verifying this
  /// reading block, not actually placed here.
  Future<List<VerifyingQuestion>> listVerifyingQuestions(String materialBlockId) async {
    final res = await _api.get('/api/materials/blocks/${Uri.encodeComponent(materialBlockId)}/verifying-questions');
    return (res['questions'] as List<dynamic>).map((q) => VerifyingQuestion.fromJson(q as Map<String, dynamic>)).toList();
  }

  /// How many distinct words a word-pool source can currently offer for
  /// this lesson (§ auto translate, 2026-09-02) — shown in the builder as
  /// the ceiling for "Количество вопросов". Advisory: the server validates
  /// the count on save and applies the real cap when generating.
  Future<int> wordPoolSize({required String source, required String lessonId}) async {
    final res = await _api.get('/api/word-pools/size?source=${Uri.encodeComponent(source)}&lessonId=${Uri.encodeComponent(lessonId)}');
    return (res['size'] as num).toInt();
  }

  /// Read-only overview for the "Карта урока" screen (§8, 2026-09-01).
  Future<LessonConnectionsMap> lessonConnectionsMap(String courseId, String lessonId) async {
    final res = await _api.get('/api/courses/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/connections-map');
    return LessonConnectionsMap.fromJson(res);
  }

  /// Course-level rollup — one row per lesson (§8, 2026-09-01).
  Future<CourseConnectionsMap> courseConnectionsMap(String courseId) async {
    final res = await _api.get('/api/courses/${Uri.encodeComponent(courseId)}/connections-map');
    return CourseConnectionsMap.fromJson(res);
  }

  /// Sets/changes/clears the "verifies this reading block" tag on an
  /// already-attached quiz-stage question (§ course-builder redesign, "+
  /// привязать" chip, 2026-09-01) — pass null to clear.
  Future<void> setPlacementVerifiesBlock(String placementId, String? materialBlockId) async {
    await _api.patch('/api/placements/${Uri.encodeComponent(placementId)}/verifies-block', body: {'materialBlockId': materialBlockId});
  }

  /// Unlinks a question from one placement — the shared Question (and any
  /// other placement of it) is untouched.
  Future<void> removePlacement(String placementId) async {
    await _api.delete('/api/placements/${Uri.encodeComponent(placementId)}');
  }

  // ---------------------------------------------------------------------
  // Reusable question pool
  // ---------------------------------------------------------------------

  Future<List<SimilarQuestionMatch>> checkQuestionSimilarity(QuestionDraft draft, {String? topicId, String? materialId}) async {
    final res = await _api.post(
      '/api/questions/similarity-check',
      body: {'question': draft.toWire(), 'topicId': ?topicId, 'materialId': ?materialId},
    );
    return (res['similar'] as List<dynamic>).map((s) => SimilarQuestionMatch.fromJson(s as Map<String, dynamic>)).toList();
  }

  Future<List<PoolQuestion>> searchQuestionPool({String query = '', String? topicId, String? kind}) async {
    final res = await _api.get('/api/questions/search', query: {'query': query, 'topicId': ?topicId, 'kind': ?kind});
    return (res['questions'] as List<dynamic>).map((q) => PoolQuestion.fromJson(q as Map<String, dynamic>)).toList();
  }

  /// Creates a new reusable Question and places it in one call. `force:
  /// true` skips the server's own similarity check (used when the teacher
  /// already saw the warning from [checkQuestionSimilarity] and chose to
  /// create anyway).
  Future<PoolQuestion> createPoolQuestion(
    QuestionDraft draft, {
    String? topicId,
    String? materialBlockId,
    String? lessonBlockId,
    String? legacyLessonId,
    String? legacySetName,
    bool force = false,
  }) async {
    final res = await _api.post(
      '/api/questions',
      body: {
        'question': draft.toWire(),
        'topicId': ?topicId,
        'materialBlockId': ?materialBlockId,
        'lessonBlockId': ?lessonBlockId,
        'legacyLessonId': ?legacyLessonId,
        'legacySetName': ?legacySetName,
        'force': force,
      },
    );
    return PoolQuestion.fromJson(res['question'] as Map<String, dynamic>);
  }

  /// Attaches an EXISTING question by reference — no copy, no new
  /// question_id (§16/§17).
  Future<AdminQuestionPlacement> reusePoolQuestion(
    String questionId, {
    String? materialBlockId,
    String? lessonBlockId,
    String? legacyLessonId,
    String? legacySetName,
  }) async {
    final res = await _api.post(
      '/api/questions/reuse',
      body: {
        'questionId': questionId,
        'materialBlockId': ?materialBlockId,
        'lessonBlockId': ?lessonBlockId,
        'legacyLessonId': ?legacyLessonId,
        'legacySetName': ?legacySetName,
      },
    );
    return AdminQuestionPlacement.fromJson(res['placement'] as Map<String, dynamic>);
  }

  /// Full "where is this actually shown" chain for one Question, wherever
  /// it was placed — regardless of where it was first created (§5/§6/§7 of
  /// the approved rule, 2026-08-27).
  Future<List<QuestionUsage>> listQuestionPlacements(String questionId) async {
    final res = await _api.get('/api/questions/${Uri.encodeComponent(questionId)}/placements');
    return (res['placements'] as List<dynamic>).map((p) => QuestionUsage.fromJson(p as Map<String, dynamic>)).toList();
  }
}

final builderRepositoryProvider = Provider<BuilderRepository>(
  (ref) => BuilderRepository(ref.watch(apiClientProvider)),
);
