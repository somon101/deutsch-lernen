import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Generic, file-based persistent cache for small JSON payloads — the
/// storage half of the stale-while-revalidate pattern (see cached_json.dart)
/// shared by courses, lessons, and progress, and meant to be reused by any
/// future section (stats, messages, ...) without a new caching system.
///
/// Not for video/audio: this is for lightweight structured data. Media
/// keeps streaming directly from the network, same as before.
class CacheStore {
  CacheStore._();
  static final CacheStore instance = CacheStore._();

  Directory? _dir;

  Future<Directory> _directory() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/data_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  String _fileName(String key) => '${key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json';

  Future<Map<String, dynamic>?> read(String key) async {
    try {
      final dir = await _directory();
      final file = File('${dir.path}/${_fileName(key)}');
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt or unreadable — treat as "no cache" rather than crashing;
      // the caller always falls back to a normal network fetch.
      return null;
    }
  }

  Future<void> write(String key, Map<String, dynamic> value) async {
    try {
      final dir = await _directory();
      final file = File('${dir.path}/${_fileName(key)}');
      await file.writeAsString(jsonEncode(value));
    } catch (_) {
      // Best-effort — a failed cache write must never break the caller.
    }
  }

  Future<void> remove(String key) async {
    try {
      final dir = await _directory();
      final file = File('${dir.path}/${_fileName(key)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// "Очистить кэш" in Settings — wipes every cached entry this store has
  /// ever written. Auth (secure_storage) and app settings (shared_preferences)
  /// live elsewhere and are untouched.
  Future<void> clearAll() async {
    try {
      final dir = await _directory();
      if (await dir.exists()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {}
  }
}
