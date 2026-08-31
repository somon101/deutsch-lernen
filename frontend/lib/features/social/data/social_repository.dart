import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../leaderboard/data/leaderboard_repository.dart';
import '../../profile/data/profile_repository.dart';

/// A public-safe view of one user (§ subscriptions, 2026-08-30) — never
/// includes email/phone/birthDate, unlike AppUser's own full shape, since
/// this is what gets shown about OTHER people. `isFollowing`/`isSelf` are
/// always relative to whoever is asking (the signed-in caller).
class UserProfile {
  const UserProfile({
    required this.id,
    required this.publicId,
    required this.firstName,
    required this.lastName,
    required this.username,
    required this.avatarUrl,
    required this.selectedLanguageId,
    required this.followersCount,
    required this.followingCount,
    required this.mutualCount,
    required this.isSelf,
    required this.isFollowing,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        publicId: json['publicId'] as String,
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        username: json['username'] as String,
        avatarUrl: json['avatarUrl'] as String?,
        selectedLanguageId: json['selectedLanguageId'] as String?,
        followersCount: json['followersCount'] as int,
        followingCount: json['followingCount'] as int,
        mutualCount: json['mutualCount'] as int,
        isSelf: json['isSelf'] as bool,
        isFollowing: json['isFollowing'] as bool,
      );

  final String id;
  final String publicId;
  final String firstName;
  final String lastName;
  final String username;
  final String? avatarUrl;
  final String? selectedLanguageId;
  final int followersCount;
  final int followingCount;
  final int mutualCount;
  final bool isSelf;
  final bool isFollowing;
}

/// The same real stats a user sees about their own profile (§ subscriptions
/// follow-up, 2026-08-30: "должен увидеть всю статистику как у себя") —
/// reuses MyRankSummary/WeekActivitySummary as-is so RankCard/WeekActivityCard
/// work unmodified for someone else's id too.
class UserStats {
  const UserStats({
    required this.streakDays,
    required this.overallProgressPercent,
    required this.totalTimeSeconds,
    required this.rank,
    required this.weekActivity,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
        streakDays: json['streakDays'] as int,
        overallProgressPercent: json['overallProgressPercent'] as int?,
        totalTimeSeconds: json['totalTimeSeconds'] as int?,
        rank: MyRankSummary.fromJson(json['rank'] as Map<String, dynamic>),
        weekActivity: WeekActivitySummary.fromJson(json['weekActivity'] as Map<String, dynamic>),
      );

  final int streakDays;
  final int? overallProgressPercent;
  final int? totalTimeSeconds;
  final MyRankSummary rank;
  final WeekActivitySummary weekActivity;
}

class SocialRepository {
  SocialRepository(this._api);

  final ApiClient _api;

  Future<UserProfile> fetchUserProfile(String userId) async {
    final res = await _api.get('/api/users/${Uri.encodeComponent(userId)}/profile');
    return UserProfile.fromJson(res);
  }

  /// Idempotent on the server — calling this again on someone already
  /// followed just returns the current state, never a duplicate or an error.
  Future<UserProfile> followUser(String userId) async {
    final res = await _api.post('/api/users/${Uri.encodeComponent(userId)}/follow');
    return UserProfile.fromJson(res);
  }

  /// Idempotent, mirroring followUser — unfollowing someone already not
  /// followed just returns the current state, never an error.
  Future<UserProfile> unfollowUser(String userId) async {
    final res = await _api.deleteExpectingBody('/api/users/${Uri.encodeComponent(userId)}/follow');
    return UserProfile.fromJson(res);
  }

  Future<List<UserProfile>> fetchFollowers(String userId) async {
    final res = await _api.get('/api/users/${Uri.encodeComponent(userId)}/followers');
    return (res['users'] as List<dynamic>).map((u) => UserProfile.fromJson(_withDefaults(u as Map<String, dynamic>))).toList();
  }

  Future<List<UserProfile>> fetchFollowing(String userId) async {
    final res = await _api.get('/api/users/${Uri.encodeComponent(userId)}/following');
    return (res['users'] as List<dynamic>).map((u) => UserProfile.fromJson(_withDefaults(u as Map<String, dynamic>))).toList();
  }

  Future<List<UserProfile>> fetchMutual(String userId) async {
    final res = await _api.get('/api/users/${Uri.encodeComponent(userId)}/mutual');
    return (res['users'] as List<dynamic>).map((u) => UserProfile.fromJson(_withDefaults(u as Map<String, dynamic>))).toList();
  }

  Future<UserStats> fetchUserStats(String userId, {String? languageId}) async {
    final res = await _api.get(
      '/api/users/${Uri.encodeComponent(userId)}/stats',
      query: languageId == null ? null : {'languageId': languageId},
    );
    return UserStats.fromJson(res);
  }

  Future<List<UserProfile>> searchUsers(String query) async {
    final res = await _api.get('/api/users/search', query: {'q': query});
    return (res['users'] as List<dynamic>).map((u) => UserProfile.fromJson(_withDefaults(u as Map<String, dynamic>))).toList();
  }

  /// Search results don't carry follow counts/isFollowing (a lightweight
  /// list, not a full profile fetch) — fill in safe defaults so the same
  /// UserProfile shape can represent a search row too, without a second
  /// model just for that.
  Map<String, dynamic> _withDefaults(Map<String, dynamic> json) => {
        ...json,
        'followersCount': json['followersCount'] ?? 0,
        'followingCount': json['followingCount'] ?? 0,
        'mutualCount': json['mutualCount'] ?? 0,
        'isSelf': json['isSelf'] ?? false,
        'isFollowing': json['isFollowing'] ?? false,
      };
}

final socialRepositoryProvider = Provider<SocialRepository>((ref) => SocialRepository(ref.watch(apiClientProvider)));

final userProfileProvider = FutureProvider.autoDispose.family<UserProfile, String>((ref, userId) {
  return ref.watch(socialRepositoryProvider).fetchUserProfile(userId);
});

/// Stats for the given user id, scoped to whichever language is "in effect"
/// for THAT user — their own `selectedLanguageId`, falling back (same rule
/// `effectiveLanguageProvider` uses for "me") to the one language with
/// published content when there's only one and they haven't picked one.
final userStatsProvider = FutureProvider.autoDispose.family<UserStats, String>((ref, userId) async {
  final profile = await ref.watch(userProfileProvider(userId).future);
  final languages = await ref.watch(availableLanguagesProvider.future);
  final languageId = profile.selectedLanguageId ?? (languages.length == 1 ? languages.single.id : null);
  return ref.watch(socialRepositoryProvider).fetchUserStats(userId, languageId: languageId);
});

/// Which of a user's three real follow lists to show (§ subscriptions
/// follow-up, 2026-08-31 — tapping Подписки/Подписчики/Взаимные).
enum FollowListKind { followers, following, mutual }

final followListProvider = FutureProvider.autoDispose.family<List<UserProfile>, (FollowListKind, String)>((ref, args) {
  final (kind, userId) = args;
  final repo = ref.watch(socialRepositoryProvider);
  return switch (kind) {
    FollowListKind.followers => repo.fetchFollowers(userId),
    FollowListKind.following => repo.fetchFollowing(userId),
    FollowListKind.mutual => repo.fetchMutual(userId),
  };
});
