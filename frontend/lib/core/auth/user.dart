/// Mirrors StoredAuthUser in src/auth/tokenStore.ts field-for-field.
enum UserRole { admin, teacher, user }

enum UserStatus { active, blocked }

UserRole _roleFromJson(String value) => switch (value) {
      'ADMIN' => UserRole.admin,
      'TEACHER' => UserRole.teacher,
      _ => UserRole.user,
    };

String _roleToJson(UserRole role) => switch (role) {
      UserRole.admin => 'ADMIN',
      UserRole.teacher => 'TEACHER',
      UserRole.user => 'USER',
    };

class AppUser {
  const AppUser({
    required this.id,
    required this.publicId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.username,
    required this.role,
    required this.status,
    required this.avatarUrl,
    required this.bio,
    required this.birthDate,
    required this.canEditProfile,
    required this.lastLoginAt,
    required this.lastActiveAt,
    this.selectedLanguageId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        // Falls back to '' rather than throwing if an older backend
        // deploy hasn't rolled out the publicId migration yet — the UI
        // must never fall back to showing `id` (the raw UUID) instead.
        publicId: json['publicId'] as String? ?? '',
        firstName: json['firstName'] as String,
        lastName: json['lastName'] as String,
        email: json['email'] as String,
        username: json['username'] as String,
        role: _roleFromJson(json['role'] as String),
        status: (json['status'] as String) == 'BLOCKED' ? UserStatus.blocked : UserStatus.active,
        avatarUrl: json['avatarUrl'] as String?,
        bio: json['bio'] as String?,
        birthDate: json['birthDate'] as String?,
        canEditProfile: json['canEditProfile'] as bool? ?? true,
        lastLoginAt: json['lastLoginAt'] as String?,
        lastActiveAt: json['lastActiveAt'] as String?,
        selectedLanguageId: json['selectedLanguageId'] as String?,
      );

  final String id;
  final String publicId;
  final String firstName;
  final String lastName;
  final String email;
  final String username;
  final UserRole role;
  final UserStatus status;
  final String? avatarUrl;
  final String? bio;
  final String? birthDate;
  final bool canEditProfile;
  final String? lastLoginAt;
  final String? lastActiveAt;
  final String? selectedLanguageId;

  bool get isStaff => role == UserRole.admin || role == UserRole.teacher;
  bool get isAdmin => role == UserRole.admin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'publicId': publicId,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'username': username,
        'role': _roleToJson(role),
        'status': status == UserStatus.blocked ? 'BLOCKED' : 'ACTIVE',
        'avatarUrl': avatarUrl,
        'bio': bio,
        'birthDate': birthDate,
        'canEditProfile': canEditProfile,
        'lastLoginAt': lastLoginAt,
        'lastActiveAt': lastActiveAt,
        'selectedLanguageId': selectedLanguageId,
      };
}
