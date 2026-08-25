import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kDebugMode, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/secure_storage.dart';

/// Fields that must never reach the debug log, no matter which endpoint
/// they pass through (login, create-user, reset-password, ...).
const _secretBodyKeys = {'password', 'newPassword'};

Object? _redactBody(Object? body) {
  if (body is Map) {
    return {for (final e in body.entries) e.key: _secretBodyKeys.contains(e.key) ? '***' : e.value};
  }
  if (body is FormData) return '<multipart form>';
  return body;
}

void _logDebug(String message) {
  if (kDebugMode) developer.log(message, name: 'ApiClient');
}

/// Mirrors src/auth/api.ts: a single base URL, Authorization: Bearer header
/// injected on every request, {"error": "..."} envelope on non-2xx (except
/// 422 validation errors, which the FastAPI backend renders as its native
/// structured format — see the migration plan §4's error-shape decision).
///
/// The default here is dev-only and platform-aware, since "localhost" means
/// different things on different targets:
/// - Windows desktop: localhost correctly reaches the dev machine itself.
/// - Android emulator: localhost means the EMULATOR, not the host — the
///   emulator's special alias for the host machine is 10.0.2.2.
/// - A real Android device (e.g. connected over USB): neither of the above
///   reaches the dev machine. Either run `adb reverse tcp:8000 tcp:8000`
///   (makes the device's own localhost:8000 tunnel to the host) or pass
///   --dart-define=API_URL=http://LAN_IP:8000 at build/run time.
String _defaultApiUrl() {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

const _apiUrlOverride = String.fromEnvironment('API_URL');

String get apiBaseUrl => _apiUrlOverride.isNotEmpty ? _apiUrlOverride : _defaultApiUrl();

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this._secureStorage) {
    // 60s, not 15s: free-tier hosts (e.g. Render) sleep after ~15 min idle
    // and take 30-50s to wake on the next request — a short timeout fails
    // that very first request before the server even finishes starting up.
    _dio = Dio(BaseOptions(baseUrl: apiBaseUrl, connectTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 60)));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          _logDebug(
            'REQUEST ${options.method} ${options.uri}\n'
            '  headers: ${options.headers.map((k, v) => MapEntry(k, k.toLowerCase() == 'authorization' ? 'Bearer ***' : v))}\n'
            '  body: ${_redactBody(options.data)}',
          );
          handler.next(options);
        },
        onResponse: (response, handler) {
          _logDebug('RESPONSE ${response.statusCode} ${response.requestOptions.uri}\n  body: ${response.data}');
          handler.next(response);
        },
        onError: (error, handler) {
          _logDebug(
            'ERROR ${error.type} ${error.requestOptions.method} ${error.requestOptions.uri}\n'
            '  status: ${error.response?.statusCode}\n'
            '  message: ${error.message}\n'
            '  body: ${error.response?.data}',
          );
          handler.next(_normalizeError(error));
        },
      ),
    );
  }

  final SecureStorage _secureStorage;
  late final Dio _dio;

  DioException _normalizeError(DioException error) {
    final data = error.response?.data;
    String? message;
    if (data is Map && data['error'] is String) {
      message = data['error'] as String;
    } else if (data is Map && data['detail'] != null) {
      // FastAPI's native 422 validation-error shape.
      final detail = data['detail'];
      if (detail is String) {
        message = detail;
      } else if (detail is List && detail.isNotEmpty && detail.first is Map && detail.first['msg'] != null) {
        message = detail.first['msg'] as String;
      }
    }
    // The server never answered at all — classify by *why*, so "wrong
    // password" (a real response, handled above) is never confused with
    // "couldn't even reach the server" (no response at all).
    message ??= switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout =>
        'Сервер не отвечает (превышено время ожидания). Проверьте интернет-соединение.',
      DioExceptionType.connectionError => 'Нет соединения с сервером. Проверьте интернет и адрес сервера.',
      DioExceptionType.badCertificate => 'Ошибка проверки сертификата сервера (SSL).',
      DioExceptionType.cancel => 'Запрос отменён.',
      _ => switch (error.response?.statusCode) {
          null => 'Неизвестная ошибка сети',
          >= 500 => 'Ошибка сервера. Попробуйте позже.',
          _ => 'Ошибка сети',
        },
    };
    return error.copyWith(error: ApiException(error.response?.statusCode ?? 0, message));
  }

  /// Every request funnels through here so callers only ever have to catch
  /// [ApiException] — not [DioException]. Dio's public API always throws
  /// DioException, even after the onError interceptor above has already
  /// packed the real ApiException into its `.error` field, so an `on
  /// ApiException catch` at a call site would silently never match and
  /// fall through to a generic message. This was a real, previously-
  /// unnoticed bug affecting every error message in the app (login,
  /// profile, every admin screen) — confirmed by grepping every `on
  /// ApiException catch` / `is ApiException` call site in the app and
  /// finding none of them could ever have actually matched.
  Future<T> _unwrap<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final unwrapped = e.error;
      if (unwrapped is ApiException) throw unwrapped;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) => _unwrap(() async {
        final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
        return res.data ?? {};
      });

  Future<Map<String, dynamic>> post(String path, {Object? body}) => _unwrap(() async {
        final res = await _dio.post<Map<String, dynamic>>(path, data: body ?? {});
        return res.data ?? {};
      });

  Future<Map<String, dynamic>> put(String path, {Object? body}) => _unwrap(() async {
        final res = await _dio.put<Map<String, dynamic>>(path, data: body ?? {});
        return res.data ?? {};
      });

  Future<Map<String, dynamic>> patch(String path, {Object? body}) => _unwrap(() async {
        final res = await _dio.patch<Map<String, dynamic>>(path, data: body ?? {});
        return res.data ?? {};
      });

  Future<void> delete(String path) => _unwrap(() => _dio.delete(path));

  /// Same as [delete], but for the few endpoints (e.g. DELETE
  /// /api/me/avatar) that return a body — the updated resource — instead of
  /// an empty response.
  Future<Map<String, dynamic>> deleteExpectingBody(String path) => _unwrap(() async {
        final res = await _dio.delete<Map<String, dynamic>>(path);
        return res.data ?? {};
      });

  /// Multipart file upload (avatars, word pronunciation audio, course
  /// media) — mirrors the FormData.append(...) calls the old React client
  /// makes before POSTing to the same endpoints.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
  }) =>
      _unwrap(() async {
        final form = FormData.fromMap({
          ...?fields,
          fieldName: MultipartFile.fromBytes(bytes, filename: filename),
        });
        final res = await _dio.post<Map<String, dynamic>>(path, data: form);
        return res.data ?? {};
      });

  /// Full URL for an uploaded asset path like "/uploads/avatars/x.png" —
  /// mirrors assetUrl() in src/auth/api.ts.
  String assetUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '$apiBaseUrl$path';
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(secureStorageProvider));
});
