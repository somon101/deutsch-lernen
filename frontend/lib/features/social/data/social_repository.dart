import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

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
  final int followersCount;
  final int followingCount;
  final int mutualCount;
  final bool isSelf;
  final bool isFollowing;
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
