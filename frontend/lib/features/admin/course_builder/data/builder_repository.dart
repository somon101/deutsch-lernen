import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../domain/block_question.dart';
import '../domain/builder_domain.dart';

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
    return (res['courses'] as List<dynamic>).map((c) => AdminCourseSummary.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<AdminCourse> getCourse(String courseId) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(courseId)}');
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> createCourse({required String title, String? description}) async {
    final res = await _api.post(_base, body: {'title': title, if (description != null) 'description': description});
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> updateCourse(String courseId, {String? title, String? description, String? status}) async {
    final res = await _api.patch(
      '$_base/${Uri.encodeComponent(courseId)}',
      body: {if (title != null) 'title': title, if (description != null) 'description': description, if (status != null) 'status': status},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<void> deleteCourse(String courseId) async {
    await _api.delete('$_base/${Uri.encodeComponent(courseId)}');
  }

  Future<List<AdminCourseSummary>> reorderCourses(List<String> ids) async {
    final res = await _api.post('$_base/reorder', body: {'ids': ids});
    return (res['courses'] as List<dynamic>).map((c) => AdminCourseSummary.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<AdminCourse> uploadCourseCover(String courseId, {required List<int> bytes, required String filename}) async {
    final res = await _api.postMultipart('$_base/${Uri.encodeComponent(courseId)}/cover', fieldName: 'file', bytes: bytes, filename: filename);
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeCourseCover(String courseId) async {
    final res = await _api.deleteExpectingBody('$_base/${Uri.encodeComponent(courseId)}/cover');
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> addLesson(String courseId, {required String title, String? description}) async {
    final res = await _api.post(
      '$_base/${Uri.encodeComponent(courseId)}/lessons',
      body: {'title': title, if (description != null) 'description': description},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> updateLesson(String courseId, String lessonId, {String? title, String? description, String? materialText}) async {
    final res = await _api.patch(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}',
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (materialText != null) 'materialText': materialText,
      },
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeLesson(String courseId, String lessonId) async {
    await _api.delete('$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}');
    return getCourse(courseId);
  }

  Future<AdminCourse> reorderLessons(String courseId, List<String> ids) async {
    final res = await _api.post('$_base/${Uri.encodeComponent(courseId)}/lessons/reorder', body: {'ids': ids});
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> uploadLessonMedia(String courseId, String lessonId, {required String kind, required List<int> bytes, required String filename}) async {
    final res = await _api.postMultipart(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      fields: {'kind': kind},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> removeLessonMedia(String courseId, String lessonId, String kind) async {
    final res = await _api.deleteExpectingBody(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media?kind=${Uri.encodeComponent(kind)}',
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<AdminCourse> reuseLessonMedia(String courseId, String lessonId, String kind, String url) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/media/reuse',
      body: {'kind': kind, 'url': url},
    );
    return AdminCourse.fromJson(res['course'] as Map<String, dynamic>);
  }

  Future<List<WordLibraryEntry>> searchWordLibrary(String query) async {
    final res = await _api.get('/api/builder/words/search', query: {'q': query});
    return (res['words'] as List<dynamic>).map((w) => WordLibraryEntry.fromJson(w as Map<String, dynamic>)).toList();
  }

  Future<List<MediaLibraryEntry>> listMediaLibrary(String kind) async {
    final res = await _api.get('/api/builder/media/library', query: {'kind': kind});
    return (res['items'] as List<dynamic>).map((m) => MediaLibraryEntry.fromJson(m as Map<String, dynamic>)).toList();
  }

  Future<List<QuestionDraft>> searchQuestions(String query) async {
    final res = await _api.get('/api/builder/questions/search', query: {'q': query});
    return (res['questions'] as List<dynamic>).map((q) => questionDraftFromWire(q as Map<String, dynamic>)).toList();
  }

  Future<List<MaterialLibraryEntry>> searchMaterials(String query) async {
    final res = await _api.get('/api/builder/materials/search', query: {'q': query});
    return (res['materials'] as List<dynamic>).map((m) => MaterialLibraryEntry.fromJson(m as Map<String, dynamic>)).toList();
  }

  String _vocabBase(String courseId, String lessonId) =>
      '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/vocabulary';

  Future<void> addWord(String courseId, String lessonId, {required String german, required String translation, required String pronunciation}) async {
    await _api.post(_vocabBase(courseId, lessonId), body: {'german': german, 'translation': translation, 'pronunciation': pronunciation});
  }

  Future<void> updateWord(String courseId, String lessonId, String wordId, {String? german, String? translation, String? pronunciation}) async {
    await _api.patch(
      '${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}',
      body: {if (german != null) 'german': german, if (translation != null) 'translation': translation, if (pronunciation != null) 'pronunciation': pronunciation},
    );
  }

  Future<void> removeWord(String courseId, String lessonId, String wordId) async {
    await _api.delete('${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}');
  }

  Future<void> uploadWordAudio(String courseId, String lessonId, String wordId, {required List<int> bytes, required String filename}) async {
    await _api.postMultipart('${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/audio', fieldName: 'audio', bytes: bytes, filename: filename);
  }

  Future<void> removeWordAudio(String courseId, String lessonId, String wordId) async {
    await _api.delete('${_vocabBase(courseId, lessonId)}/${Uri.encodeComponent(wordId)}/audio');
  }

  Future<ImportPreview> previewVocabularyImport(String courseId, String lessonId, List<Map<String, String>> words) async {
    final res = await _api.post('${_vocabBase(courseId, lessonId)}/import/preview', body: {'words': words});
    return ImportPreview.fromJson(res['preview'] as Map<String, dynamic>);
  }

  Future<({int addedCount, List<ImportPreviewItem> skipped})> importVocabulary(String courseId, String lessonId, List<Map<String, String>> words) async {
    final res = await _api.post('${_vocabBase(courseId, lessonId)}/import', body: {'words': words});
    final skipped = (res['skipped'] as List<dynamic>).map((s) => ImportPreviewItem.fromJson(s as Map<String, dynamic>)).toList();
    return (addedCount: res['addedCount'] as int, skipped: skipped);
  }

  String _blocksBase(String courseId, String lessonId) => '$_base/${Uri.encodeComponent(courseId)}/lessons/${Uri.encodeComponent(lessonId)}/blocks';

  Future<void> addBlock(String courseId, String lessonId, String stage, String title) async {
    await _api.post(_blocksBase(courseId, lessonId), body: {'stage': stage, 'title': title});
  }

  Future<void> renameBlock(String courseId, String lessonId, String blockId, String title) async {
    await _api.patch('${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}', body: {'title': title});
  }

  Future<void> removeBlock(String courseId, String lessonId, String blockId) async {
    await _api.delete('${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}');
  }

  Future<void> reorderBlocks(String courseId, String lessonId, String stage, List<String> ids) async {
    await _api.post('${_blocksBase(courseId, lessonId)}/reorder', body: {'stage': stage, 'ids': ids});
  }

  Future<void> saveBlockQuestions(String courseId, String lessonId, String blockId, List<QuestionDraft> questions) async {
    await _api.put('${_blocksBase(courseId, lessonId)}/${Uri.encodeComponent(blockId)}/questions', body: {'questions': [for (final q in questions) q.toWire()]});
  }
}

final builderRepositoryProvider = Provider<BuilderRepository>((ref) => BuilderRepository(ref.watch(apiClientProvider)));
