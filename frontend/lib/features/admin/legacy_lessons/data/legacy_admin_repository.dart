import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../course_builder/domain/builder_domain.dart';

/// Port of src/admin/legacyContentApi.ts + the /api/admin/content/:id GET/PUT
/// AdminLessonEditPage.tsx calls directly — legacy lessons (courseId
/// "legacy") share the builder's vocabulary/block mutations
/// (BuilderRepository) but have their own material/media endpoints since
/// they predate the course-builder schema. The content DTO itself carries
/// no title (see AdminLesson.fromLegacyJson's doc comment), so every method
/// here takes one, supplied by the caller from GET /api/content's list.
class LegacyAdminRepository {
  LegacyAdminRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/admin/content';

  Future<AdminLesson> getContent(String lessonId, String title) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(lessonId)}');
    return AdminLesson.fromLegacyJson(
      lessonId,
      title,
      res['content'] as Map<String, dynamic>,
    );
  }

  Future<AdminLesson> saveMaterialText(
    String lessonId,
    String title,
    String materialText,
  ) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(lessonId)}',
      body: {'materialText': materialText},
    );
    return AdminLesson.fromLegacyJson(
      lessonId,
      title,
      res['content'] as Map<String, dynamic>,
    );
  }

  Future<AdminLesson> uploadMedia(
    String lessonId,
    String title, {
    required String kind,
    required List<int> bytes,
    required String filename,
  }) async {
    final res = await _api.postMultipart(
      '$_base/${Uri.encodeComponent(lessonId)}/media',
      fieldName: 'file',
      bytes: bytes,
      filename: filename,
      fields: {'kind': kind},
    );
    return AdminLesson.fromLegacyJson(
      lessonId,
      title,
      res['content'] as Map<String, dynamic>,
    );
  }

  Future<AdminLesson> removeMedia(
    String lessonId,
    String title,
    String kind,
  ) async {
    final res = await _api.deleteExpectingBody(
      '$_base/${Uri.encodeComponent(lessonId)}/media?kind=${Uri.encodeComponent(kind)}',
    );
    return AdminLesson.fromLegacyJson(
      lessonId,
      title,
      res['content'] as Map<String, dynamic>,
    );
  }

  Future<AdminLesson> reuseMedia(
    String lessonId,
    String title,
    String kind,
    String url,
  ) async {
    final res = await _api.put(
      '$_base/${Uri.encodeComponent(lessonId)}/media/reuse',
      body: {'kind': kind, 'url': url},
    );
    return AdminLesson.fromLegacyJson(
      lessonId,
      title,
      res['content'] as Map<String, dynamic>,
    );
  }
}

final legacyAdminRepositoryProvider = Provider<LegacyAdminRepository>(
  (ref) => LegacyAdminRepository(ref.watch(apiClientProvider)),
);
