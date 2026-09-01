import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/user.dart';
import '../../../profile/data/profile_repository.dart';

class AdminUser {
  const AdminUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.username,
    required this.role,
    required this.status,
    required this.avatarUrl,
    required this.canEditProfile,
    required this.lastLoginAt,
    required this.lastActiveAt,
    required this.online,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
    id: json['id'] as String,
    firstName: json['firstName'] as String,
    lastName: json['lastName'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String?,
    username: json['username'] as String,
    role: json['role'] as String,
    status: json['status'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    canEditProfile: json['canEditProfile'] as bool,
    lastLoginAt: json['lastLoginAt'] as String?,
    lastActiveAt: json['lastActiveAt'] as String?,
    online: json['online'] as bool,
  );

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String username;
  final String role;
  final String status;
  final String? avatarUrl;
  final bool canEditProfile;
  final String? lastLoginAt;
  final String? lastActiveAt;
  final bool online;
}

/// Real-activity order (§ admin users expanded list, 2026-09-01): online
/// users first, then everyone else by how recently they were last active —
/// "1 минуту назад, 2 минуты назад…" — with users who were never active
/// sorted last. `online` is itself derived server-side from `lastActiveAt`
/// (within a 5-minute window, see with_online_status in serialize.py), so
/// sorting by `online` first and `lastActiveAt` second never contradicts
/// itself — it just makes the intent explicit instead of relying on that
/// coincidence.
List<AdminUser> sortUsersByActivity(List<AdminUser> users) {
  final sorted = [...users];
  sorted.sort((a, b) {
    if (a.online != b.online) return a.online ? -1 : 1;
    final at = a.lastActiveAt == null ? null : DateTime.tryParse(a.lastActiveAt!);
    final bt = b.lastActiveAt == null ? null : DateTime.tryParse(b.lastActiveAt!);
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return sorted;
}

class LoginEventRow {
  const LoginEventRow({required this.id, required this.createdAt});
  factory LoginEventRow.fromJson(Map<String, dynamic> json) => LoginEventRow(
    id: json['id'] as String,
    createdAt: json['createdAt'] as String,
  );
  final String id;
  final String createdAt;
}

/// Port of AdminUsersPage.tsx/AdminUserDetailPage.tsx's API calls
/// (/api/admin/users*).
class AdminUsersRepository {
  AdminUsersRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/admin/users';

  Future<List<AdminUser>> listUsers() async {
    final res = await listUsersRaw();
    return res.map(AdminUser.fromJson).toList();
  }

  /// Raw-JSON variant for the caching layer (see cached_json.dart).
  Future<List<Map<String, dynamic>>> listUsersRaw() async {
    final res = await _api.get(_base);
    return (res['users'] as List<dynamic>).cast<Map<String, dynamic>>();
  }

  Future<AdminUser> getUser(String id) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(id)}');
    return AdminUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AdminUser> createUser({
    required String firstName,
    required String lastName,
    required String email,
    String? phone,
    required String username,
    required String password,
    required UserRole role,
    required bool canEditProfile,
  }) async {
    final res = await _api.post(
      _base,
      body: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
        'username': username,
        'password': password,
        'role': _roleWire(role),
        'canEditProfile': canEditProfile,
      },
    );
    return AdminUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<AdminUser> updateUser(
    String id, {
    String? firstName,
    String? lastName,
    String? email,
    String? phone,
    String? username,
    UserRole? role,
    bool? canEditProfile,
    String? status,
  }) async {
    final res = await _api.patch(
      '$_base/${Uri.encodeComponent(id)}',
      body: {
        'firstName': ?firstName,
        'lastName': ?lastName,
        'email': ?email,
        'phone': ?phone,
        'username': ?username,
        if (role != null) 'role': _roleWire(role),
        'canEditProfile': ?canEditProfile,
        'status': ?status,
      },
    );
    return AdminUser.fromJson(res['user'] as Map<String, dynamic>);
  }

  Future<void> resetPassword(String id, String newPassword) async {
    await _api.post(
      '$_base/${Uri.encodeComponent(id)}/reset-password',
      body: {'newPassword': newPassword},
    );
  }

  /// One ad-hoc push straight to this user's device (§ individual push,
  /// 2026-08-30) — not saved as message history anywhere. Returns whether
  /// at least one of their devices was actually delivered to (they may have
  /// no push token registered at all, in which case this is still a
  /// successful call, just nothing arrived).
  Future<bool> notifyUser(String id, String message) async {
    final res = await _api.post('$_base/${Uri.encodeComponent(id)}/notify', body: {'message': message});
    return res['delivered'] as bool;
  }

  Future<List<LoginEventRow>> loginHistory(String id) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(id)}/logins');
    return (res['logins'] as List<dynamic>)
        .map((l) => LoginEventRow.fromJson(l as Map<String, dynamic>))
        .toList();
  }

  Future<List<LessonProgressSummary>> userProgress(String id) async {
    final res = await _api.get('$_base/${Uri.encodeComponent(id)}/progress');
    return (res['progress'] as List<dynamic>)
        .map((p) => LessonProgressSummary.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  String _roleWire(UserRole role) => switch (role) {
    UserRole.admin => 'ADMIN',
    UserRole.teacher => 'TEACHER',
    UserRole.user => 'USER',
  };
}

final adminUsersRepositoryProvider = Provider<AdminUsersRepository>(
  (ref) => AdminUsersRepository(ref.watch(apiClientProvider)),
);
