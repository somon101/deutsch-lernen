import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'user.dart';

/// Mirrors src/auth/tokenStore.ts's localStorage-backed store — same
/// {token, user} pair, same "load once at startup" contract — but using
/// flutter_secure_storage so it works identically on both Android and
/// Windows (tokenStore.ts had only one platform to support; this needs two).
class SecureStorage {
  SecureStorage() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _tokenKey = 'deutsch_lernen_token';
  static const _userKey = 'deutsch_lernen_user';
  static const _themeKey = 'deutsch_lernen_theme';

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<AppUser?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null) return null;
    try {
      return AppUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveAuth(String token, AppUser user) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<void> clearAuth() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  Future<String?> readTheme() => _storage.read(key: _themeKey);

  Future<void> saveTheme(String value) => _storage.write(key: _themeKey, value: value);
}

final secureStorageProvider = Provider<SecureStorage>((ref) => SecureStorage());
