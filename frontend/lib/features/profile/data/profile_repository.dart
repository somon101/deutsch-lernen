import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/user.dart';

/// Mirrors ProfilePage.tsx's LessonProgressSummary — the wire shape
/// GET /api/me/progress returns per lesson the learner has attempted.
class LessonProgressSummary {
  const LessonProgressSummary({
    required this.lessonId,
    required this.attempts,
    required this.bestScore,
    required this.lastScore,
    required this.lastAttemptAt,
  });

  factory LessonProgressSummary.fromJson(Map<String, dynamic> json) => LessonProgressSummary(
        lessonId: json['lessonId'] as String,
        attempts: json['attempts'] as int,
        bestScore: json['bestScore'] as int,
        lastScore: json['lastScore'] as int,
        lastAttemptAt: json['lastAttemptAt'] as String,
      );

  final String lessonId;
  final int attempts;
  final int bestScore;
  final int lastScore;
  final String lastAttemptAt;
}

class LegacyLessonSummary {
  const LegacyLessonSummary({required this.lessonId, required this.title, required this.vocabularyCount});

  factory LegacyLessonSummary.fromJson(Map<String, dynamic> json) => LegacyLessonSummary(
        lessonId: json['lessonId'] as String,
        title: json['title'] as String,
        vocabularyCount: json['vocabularyCount'] as int,
      );

  final String lessonId;
  final String title;
  final int vocabularyCount;
}

class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<List<LegacyLessonSummary>> fetchLegacyLessons() async {
    final res = await _api.get('/api/content');
    return (res['lessons'] as List<dynamic>).map((l) => LegacyLessonSummary.fromJson(l as Map<String, dynamic>)).toList();
  }

  Future<List<LessonProgressSummary>> fetchProgressSummaries() async {
    final res = await _api.get('/api/me/progress');
    return (res['progress'] as List<dynamic>).map((p) => LessonProgressSummary.fromJson(p as Map<String, dynamic>)).toList();
  }

  Future<AppUser> updateProfile({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    String? username,
    String? bio,
    DateTime? birthDate,
  }) async {
    final res = await _api.patch('/api/me/', body: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      if (username != null) 'username': username,
      if (bio != null) 'bio': bio,
      if (birthDate != null) 'birthDate': birthDate.toUtc().toIso8601String(),
    });
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AppUser> uploadAvatar({required List<int> bytes, required String filename}) async {
    final res = await _api.postMultipart('/api/me/avatar', fieldName: 'avatar', bytes: bytes, filename: filename);
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AppUser> deleteAvatar() async {
    final res = await _api.deleteExpectingBody('/api/me/avatar');
    return AppUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<void> changePassword({required String currentPassword, required String newPassword}) {
    return _api.patch('/api/me/password', body: {'currentPassword': currentPassword, 'newPassword': newPassword});
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));
