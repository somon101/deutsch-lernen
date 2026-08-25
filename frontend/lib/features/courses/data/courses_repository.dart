import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// Mirrors content/learnerCourses.ts's BuilderCourseSummary — one card per
/// published builder course on the courses hub.
class BuilderCourseSummary {
  const BuilderCourseSummary({
    required this.id,
    required this.title,
    required this.description,
    required this.coverUrl,
    required this.lessonCount,
  });

  factory BuilderCourseSummary.fromJson(Map<String, dynamic> json) => BuilderCourseSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        coverUrl: json['coverUrl'] as String?,
        lessonCount: json['lessonCount'] as int,
      );

  final String id;
  final String title;
  final String? description;
  final String? coverUrl;
  final int lessonCount;
}

class BuilderCourseLessonSummary {
  const BuilderCourseLessonSummary({required this.id, required this.title, required this.vocabularyCount});

  factory BuilderCourseLessonSummary.fromJson(Map<String, dynamic> json) => BuilderCourseLessonSummary(
        id: json['id'] as String,
        title: json['title'] as String,
        vocabularyCount: (json['vocabulary'] as List<dynamic>? ?? const []).length,
      );

  final String id;
  final String title;
  final int vocabularyCount;
}

class BuilderCourseDetail {
  const BuilderCourseDetail({required this.id, required this.title, required this.description, required this.lessons});

  factory BuilderCourseDetail.fromJson(Map<String, dynamic> json) => BuilderCourseDetail(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        lessons: (json['lessons'] as List<dynamic>).map((l) => BuilderCourseLessonSummary.fromJson(l as Map<String, dynamic>)).toList(),
      );

  final String id;
  final String title;
  final String? description;
  final List<BuilderCourseLessonSummary> lessons;
}

/// Mirrors content/learnerCourses.ts — published-course listing/detail, the
/// learner-facing counterpart of the admin builder's own course CRUD.
class CoursesRepository {
  CoursesRepository(this._api);

  final ApiClient _api;

  Future<List<BuilderCourseSummary>> fetchPublishedCourses() async {
    final res = await _api.get('/api/courses/');
    return (res['courses'] as List<dynamic>).map((c) => BuilderCourseSummary.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<BuilderCourseDetail> fetchCourse(String courseId) async {
    final res = await _api.get('/api/courses/${Uri.encodeComponent(courseId)}');
    return BuilderCourseDetail.fromJson(res['course'] as Map<String, dynamic>);
  }
}

final coursesRepositoryProvider = Provider<CoursesRepository>((ref) => CoursesRepository(ref.watch(apiClientProvider)));
