import 'cache_store.dart';

/// true if two JSON-safe values (Map/List/String/num/bool/null — exactly
/// what jsonDecode ever produces) are structurally equal. Dart's built-in
/// `==` on Map/List is reference equality, which is useless for comparing
/// "did the server's response actually change" — this is the one thing
/// cachedJsonStream needs that isn't already free.
bool jsonValuesEqual(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonValuesEqual(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonValuesEqual(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// The shared stale-while-revalidate mechanism (caching plan, 2026-08-29):
/// operates on raw JSON (`Map<String, dynamic>`), not parsed domain models,
/// so it works the same way for courses, lessons, progress, and any future
/// section — no per-feature caching code, no toJson needed on domain types.
///
/// Behavior:
/// 1. If a cached copy of [key] exists, it's yielded immediately — the UI
///    has something to show before any network call finishes.
/// 2. If [fetchVersion] is given and a cached copy exists, it's checked
///    first: an unchanged version skips [fetchFresh] entirely (no
///    re-download of unchanged content).
/// 3. Otherwise [fetchFresh] runs, and its result is yielded ONLY if it
///    actually differs from what was cached (or there was nothing cached) —
///    so an unchanged-but-not-version-checked response never causes an
///    unnecessary rebuild/flicker.
///
/// Any failure from [fetchVersion] or [fetchFresh] after a cached value was
/// already yielded is swallowed: the learner keeps seeing the last-known
/// content rather than an error screen, exactly like a normal transient
/// network hiccup should behave once something is already on screen.
Stream<Map<String, dynamic>> cachedJsonStream({
  required String key,
  required Future<Map<String, dynamic>> Function() fetchFresh,
  Future<String?> Function()? fetchVersion,
}) async* {
  final store = CacheStore.instance;
  final cached = await store.read(key);
  final cachedData = cached?['data'] as Map<String, dynamic>?;
  final cachedVersion = cached?['version'] as String?;
  final hadCache = cachedData != null;
  if (cachedData != null) yield cachedData;

  try {
    String? freshVersion;
    if (fetchVersion != null) {
      freshVersion = await fetchVersion();
      if (hadCache && freshVersion != null && freshVersion == cachedVersion) {
        return; // confirmed unchanged — no need to re-download anything
      }
    }

    final fresh = await fetchFresh();
    final changed = !hadCache || !jsonValuesEqual(fresh, cachedData);
    await store.write(key, {'data': fresh, 'version': freshVersion});
    if (changed) yield fresh;
  } catch (e) {
    if (!hadCache) rethrow; // nothing to show — surface the error as before
    // Had something on screen already: keep showing it rather than erroring.
  }
}
