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

  /// One locale's variant of a course's title/description (§ course content
  /// language, 2026-09-04) — a full replace of that locale's row, matching
  /// backend/app/schemas/course.py's CourseTranslationInput.
  Future<AdminCourse> setCourseTranslation(String courseId, String locale, {required String title, required String description}) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(courseId)}/translations/${Uri.encodeComponent(locale)}',
      body: {'title': title, 'description': description},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  /// Same for a lesson's title/description/materialText.
  Future<AdminCourse> setLessonTranslation(
    String courseId,
    String lessonId,
    String locale, {
    required String title,
    required String description,
    required String materialText,
  }) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/translations/${Uri.encodeComponent(locale)}',
      body: {'title': title, 'description': description, 'materialText': materialText},
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

  /// Every category that already exists (§ word cards, 2026-08-31) — for
  /// a "pick an existing one, or type a new name" category field.
  Future<List<AdminCategory>> listCategories() async {
    final res = await _api.get('/api/builder/vocabulary/categories');
    return (res['categories'] as List<dynamic>).map((c) => AdminCategory.fromJson(c as Map<String, dynamic>)).toList();
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

  /// Returns the new word's id (§ shared dictionary, 2026-09-14) — added
  /// so a caller that just created a word (e.g. the "Словарь" screen's own
  /// create form) can act on it further (upload an image) without a
  /// second round-trip to find it again. Every existing caller that never
  /// used the old `Future<void>` return value keeps working unchanged.
  Future<String> addWord(
    String courseId,
    String lessonId, {
    required String german,
    required String translation,
    required String pronunciation,
    String? categoryName,
    String? imageUrl,
  }) async {
    final res = await _api.post(
      _vocabBase(courseId, lessonId),
      body: {
        'german': german,
        'translation': translation,
        'pronunciation': pronunciation,
        'categoryName': ?categoryName,
        'imageUrl': ?imageUrl,
      },
    );
    return res['id'] as String;
  }

  Future<void> updateWord(
    String courseId,
    String lessonId,
    String wordId, {
    String? german,
    String? translation,
    String? pronunciation,
    String? categoryName,
  }) async {
    await _api.patch(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}',
      body: {
        'german': ?german,
        'translation': ?translation,
        'pronunciation': ?pronunciation,
        'categoryName': ?categoryName,
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

  /// Attaches an EXISTING word (picked via the dictionary search) to this
  /// lesson without copying it (§ shared dictionary, 2026-09-14) — the
  /// "выбрать существующее слово" half of the constructor's word picker.
  Future<void> linkExistingWord(
    String courseId,
    String lessonId,
    String wordId,
  ) async {
    await _api.post(
      '${_vocabBase(courseId, lessonId)}/link',
      body: {'wordId': wordId},
    );
  }

  /// A word added straight to the «Словарь» of a studied language, with no
  /// course or lesson. Returns its id and the scope to use as course/lesson
  /// for its own edit/photo/audio endpoints.
  Future<({String id, String courseId, String lessonId})> addDictionaryWord({
    required String languageId,
    required String german,
    required String translation,
    required String translationTg,
    String pronunciation = '',
    String? categoryName,
  }) async {
    final res = await _api.post('/api/builder/vocabulary', body: {
      'languageId': languageId,
      'german': german,
      'translation': translation,
      'translationTg': translationTg,
      'pronunciation': pronunciation,
      'categoryName': ?categoryName,
    });
    return (id: res['id'] as String, courseId: res['courseId'] as String, lessonId: res['lessonId'] as String);
  }

  /// Bulk add to the «Словарь» of a language; words already present in that
  /// language (or repeated in the file) are skipped, never overwritten.
  Future<({int addedCount, List<ImportPreviewItem> skipped})> importDictionaryWords(String languageId, List<Map<String, String>> words) async {
    final res = await _api.post('/api/builder/vocabulary/import', body: {'languageId': languageId, 'words': words});
    final skipped = (res['skipped'] as List<dynamic>).map((s) => ImportPreviewItem.fromJson(s as Map<String, dynamic>)).toList();
    return (addedCount: res['addedCount'] as int, skipped: skipped);
  }

  /// Every word in the system, browsable/searchable regardless of which
  /// lesson it lives in (§ shared dictionary, 2026-09-14) — the admin
  /// "Словарь" screen's data source.
  Future<DictionaryPage> listDictionaryWords({
    String? query,
    String? languageId,
    String? categoryId,
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _api.get(
      '/api/builder/vocabulary',
      query: {
        'q': ?query,
        'languageId': ?languageId,
        'categoryId': ?categoryId,
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    return DictionaryPage.fromJson(res);
  }

  /// Removes a word from the dictionary entirely, regardless of which
  /// lesson(s) it's placed in (§ shared dictionary, 2026-09-14) — unlike
  /// [removeWord] above (which only ever detaches from ONE lesson and
  /// refuses if the word is still used elsewhere), this is the "Словарь"
  /// screen's own deliberate, explicit delete. Without `force`, the server
  /// refuses with a 409 (surfaced as ApiException) naming how many lessons/
  /// learners are affected — the caller shows that as a real confirmation
  /// and retries with `force: true` if the admin still wants to proceed.
  Future<void> deleteWordGlobally(String wordId, {bool force = false}) async {
    await _api.delete(
      '/api/builder/vocabulary/${Uri.encodeComponent(wordId)}${force ? '?force=true' : ''}',
    );
  }

  /// One locale's variant of a word's translation (§ course content
  /// language, 2026-09-04) — `german`/`pronunciation` are never part of
  /// this, see VocabularyTranslation's backend docstring for why.
  Future<void> setVocabularyTranslation(String courseId, String lessonId, String wordId, String locale, String translation) async {
    await _api.put(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/translations/${Uri.encodeComponent(locale)}',
      body: {'translation': translation},
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

  Future<AdminLanguage> updateLanguage(String id, {String? name, String? status, String? alphabet}) async {
    final res = await _api.patch('/api/languages/${Uri.encodeComponent(id)}', body: {
      'name': ?name,
      'status': ?status,
      'alphabet': ?alphabet,
    });
    return AdminLanguage.fromJson(res['language'] as Map<String, dynamic>);
  }

  /// Fails with 409 (and a message naming what's inside) unless the
  /// language has no courses, words, phrases or rules.
  Future<void> deleteLanguage(String id) => _api.delete('/api/languages/${Uri.encodeComponent(id)}');

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

  /// One locale's variant of a MaterialBlock's title/content (§ course
  /// content language, 2026-09-04).
  Future<AdminMaterialBlock> setMaterialBlockTranslation(String blockId, String locale, {required String title, required String content}) async {
    final res = await _api.put(
      '/api/materials/blocks/${Uri.encodeComponent(blockId)}/translations/${Uri.encodeComponent(locale)}',
      body: {'title': title, 'content': content},
    );
    return AdminMaterialBlock.fromJson(res['block'] as Map<String, dynamic>);
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

  /// How this learner's auto-match pool splits between "learned today and
  /// not yet claimed by «Переведи слово»" and everything earlier (§ auto
  /// match, 2026-09-02) — a builder hint only; the server decides the real
  /// selection.
  Future<({int todayFree, int total})> matchPoolBreakdown({required String lessonId}) async {
    final res = await _api.get('/api/word-pools/match-breakdown?lessonId=${Uri.encodeComponent(lessonId)}');
    return (
      todayFree: (res['todayUnusedByTranslateWord'] as num).toInt(),
      total: (res['total'] as num).toInt(),
    );
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

  /// {locale: {prompt, options, correctAnswer}} (§ course content language,
  /// 2026-09-04) — fetched lazily, same as listQuestionPlacements above.
  Future<Map<String, QuestionTranslationFields>> getQuestionTranslations(String questionId) async {
    final res = await _api.get('/api/questions/${Uri.encodeComponent(questionId)}/translations');
    return (res['translations'] as Map<String, dynamic>).map(
      (locale, v) => MapEntry(locale, QuestionTranslationFields.fromJson(v as Map<String, dynamic>)),
    );
  }

  Future<Map<String, QuestionTranslationFields>> setQuestionTranslation(
    String questionId,
    String locale, {
    String? prompt,
    List<String>? options,
    String? correctAnswer,
  }) async {
    final res = await _api.put(
      '/api/questions/${Uri.encodeComponent(questionId)}/translations/${Uri.encodeComponent(locale)}',
      body: {'prompt': ?prompt, 'options': ?options, 'correctAnswer': ?correctAnswer},
    );
    return (res['translations'] as Map<String, dynamic>).map(
      (loc, v) => MapEntry(loc, QuestionTranslationFields.fromJson(v as Map<String, dynamic>)),
    );
  }

  // ---------------------------------------------------------------------
  // Lesson graph (§ lesson graph, 2026-09-03)
  // ---------------------------------------------------------------------

  String _graphBase(String courseId, String lessonId) =>
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/graph';

  /// Real graph for a converted lesson, or a computed PREVIEW
  /// (`isLegacy: true`) of what converting it would look like — never
  /// writes anything.
  Future<AdminLessonGraph> getLessonGraph(String courseId, String lessonId) async {
    final res = await _api.get(_graphBase(courseId, lessonId));
    return AdminLessonGraph.fromJson(res);
  }

  /// One-time "Перевести в граф" conversion — persists the preview
  /// [getLessonGraph] already showed as real LessonNode/LessonEdge rows.
  /// Throws if the lesson already has a real graph.
  Future<AdminLessonGraph> materializeLessonGraph(String courseId, String lessonId) async {
    final res = await _api.post('${_graphBase(courseId, lessonId)}/materialize');
    return AdminLessonGraph.fromJson(res);
  }

  Future<AdminGraphNode> addGraphNode(
    String courseId,
    String lessonId, {
    required String type,
    String? title,
    required double posX,
    required double posY,
  }) async {
    final res = await _api.post(
      '${_graphBase(courseId, lessonId)}/nodes',
      body: {'type': type, 'title': ?title, 'posX': posX, 'posY': posY},
    );
    return AdminGraphNode.fromJson(res['node'] as Map<String, dynamic>);
  }

  Future<AdminGraphNode> updateGraphNode(
    String courseId,
    String lessonId,
    String nodeId, {
    double? posX,
    double? posY,
    String? title,
    String? transcript,
    Map<String, String>? transcriptTranslations,
  }) async {
    final res = await _api.patch(
      '${_graphBase(courseId, lessonId)}/nodes/${Uri.encodeComponent(nodeId)}',
      body: {'posX': ?posX, 'posY': ?posY, 'title': ?title, 'transcript': ?transcript, 'transcriptTranslations': ?transcriptTranslations},
    );
    return AdminGraphNode.fromJson(res['node'] as Map<String, dynamic>);
  }

  Future<AdminGraphNode> uploadGraphNodeMedia(
    String courseId,
    String lessonId,
    String nodeId, {
    required List<int> bytes,
    required String filename,
  }) async {
    final res = await _api.postMultipart(
      '${_graphBase(courseId, lessonId)}/nodes/${Uri.encodeComponent(nodeId)}/media',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
    );
    return AdminGraphNode.fromJson(res['node'] as Map<String, dynamic>);
  }

  Future<AdminGraphNode> removeGraphNodeMedia(String courseId, String lessonId, String nodeId) async {
    final res = await _api.deleteExpectingBody('${_graphBase(courseId, lessonId)}/nodes/${Uri.encodeComponent(nodeId)}/media');
    return AdminGraphNode.fromJson(res['node'] as Map<String, dynamic>);
  }

  Future<AdminGraphNode> reuseGraphNodeMedia(String courseId, String lessonId, String nodeId, String url) async {
    final res = await _api.put('${_graphBase(courseId, lessonId)}/nodes/${Uri.encodeComponent(nodeId)}/media/reuse', body: {'url': url});
    return AdminGraphNode.fromJson(res['node'] as Map<String, dynamic>);
  }

  Future<void> deleteGraphNode(String courseId, String lessonId, String nodeId) async {
    await _api.delete('${_graphBase(courseId, lessonId)}/nodes/${Uri.encodeComponent(nodeId)}');
  }

  Future<AdminGraphEdge> addGraphEdge(String courseId, String lessonId, String fromNodeId, String toNodeId) async {
    final res = await _api.post(
      '${_graphBase(courseId, lessonId)}/edges',
      body: {'fromNodeId': fromNodeId, 'toNodeId': toNodeId},
    );
    return AdminGraphEdge.fromJson(res['edge'] as Map<String, dynamic>);
  }

  Future<void> deleteGraphEdge(String courseId, String lessonId, String edgeId) async {
    await _api.delete('${_graphBase(courseId, lessonId)}/edges/${Uri.encodeComponent(edgeId)}');
  }
}

final builderRepositoryProvider = Provider<BuilderRepository>(
  (ref) => BuilderRepository(ref.watch(apiClientProvider)),
);
