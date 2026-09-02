import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Downloads a lesson's word photos to disk before the lesson opens
/// (§ pre-download word photos, 2026-09-02).
///
/// Uses the same [DefaultCacheManager] that avatars already cache through —
/// and that Settings' "Очистить кэш" already empties — so photos land in the
/// one cache the app has, not a second one beside it. Files survive an app
/// restart, which is the whole point: the second pass through a lesson reads
/// from disk and shows instantly, offline included.
///
/// Nothing here decides WHEN to prefetch; the caller does. This only answers
/// "get these URLs onto disk, and tell me how it's going".
class ImagePrefetcher {
  ImagePrefetcher({BaseCacheManager? cacheManager}) : _cache = cacheManager ?? DefaultCacheManager();

  final BaseCacheManager _cache;

  /// True when this URL is already on disk, so the caller can skip the
  /// progress UI entirely for a lesson that has been opened before.
  Future<bool> isCached(String url) async {
    if (url.isEmpty) return false;
    try {
      return await _cache.getFileFromCache(url) != null;
    } catch (_) {
      // A cache that can't be read is treated as a cache miss, never as an
      // error — the image still loads over the network afterwards.
      return false;
    }
  }

  Future<List<String>> missing(Iterable<String> urls) async {
    final result = <String>[];
    for (final url in urls.toSet()) {
      if (url.isEmpty) continue;
      if (!await isCached(url)) result.add(url);
    }
    return result;
  }

  /// Downloads [urls], reporting `(done, total)` after each one.
  ///
  /// Failures are counted as done rather than thrown: one unreachable photo
  /// must not keep a learner out of the lesson. Whatever failed simply loads
  /// (or shows its placeholder) the normal way once inside.
  Future<int> download(
    List<String> urls, {
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    var done = 0;
    var failed = 0;
    onProgress?.call(0, urls.length);
    for (final url in urls) {
      if (isCancelled?.call() ?? false) break;
      try {
        await _cache.downloadFile(url);
      } catch (e) {
        failed++;
        debugPrint('Не удалось предзагрузить изображение: $url ($e)');
      }
      done++;
      onProgress?.call(done, urls.length);
    }
    return failed;
  }
}
