import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/secure_storage.dart';

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
  if (Platform.isAndroid) return 'http://10.0.2.2:8000';
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
    _dio = Dio(BaseOptions(baseUrl: apiBaseUrl, connectTimeout: const Duration(seconds: 15)));
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _secureStorage.readToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) => handler.next(_normalizeError(error)),
      ),
    );
  }

  final SecureStorage _secureStorage;
  late final Dio _dio;

  DioException _normalizeError(DioException error) {
    final data = error.response?.data;
    String message = 'Ошибка сети';
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
    return error.copyWith(error: ApiException(error.response?.statusCode ?? 0, message));
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> post(String path, {Object? body}) async {
    final res = await _dio.post<Map<String, dynamic>>(path, data: body ?? {});
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> put(String path, {Object? body}) async {
    final res = await _dio.put<Map<String, dynamic>>(path, data: body ?? {});
    return res.data ?? {};
  }

  Future<Map<String, dynamic>> patch(String path, {Object? body}) async {
    final res = await _dio.patch<Map<String, dynamic>>(path, data: body ?? {});
    return res.data ?? {};
  }

  Future<void> delete(String path) async {
    await _dio.delete(path);
  }

  /// Same as [delete], but for the few endpoints (e.g. DELETE
  /// /api/me/avatar) that return a body — the updated resource — instead of
  /// an empty response.
  Future<Map<String, dynamic>> deleteExpectingBody(String path) async {
    final res = await _dio.delete<Map<String, dynamic>>(path);
    return res.data ?? {};
  }

  /// Multipart file upload (avatars, word pronunciation audio, course
  /// media) — mirrors the FormData.append(...) calls the old React client
  /// makes before POSTing to the same endpoints.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    Map<String, String>? fields,
  }) async {
    final form = FormData.fromMap({
      ...?fields,
      fieldName: MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post<Map<String, dynamic>>(path, data: form);
    return res.data ?? {};
  }

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
