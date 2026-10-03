import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';

/// AI provider connection + lesson generator + phrase base (§ AI lesson
/// generator, 2026-10-03). The API key is write-only from the client's
/// side: the server only ever reports whether one is set and its last four
/// characters.
class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;
  static const _settings = '/api/admin/ai-settings';

  Future<AiSettings> getSettings() async => AiSettings.fromJson((await _api.get(_settings))['settings'] as Map<String, dynamic>);

  Future<AiSettings> saveKey(String apiKey) async =>
      AiSettings.fromJson((await _api.patch(_settings, body: {'apiKey': apiKey}))['settings'] as Map<String, dynamic>);

  Future<AiSettings> saveModel(String model) async =>
      AiSettings.fromJson((await _api.patch(_settings, body: {'model': model}))['settings'] as Map<String, dynamic>);

  Future<void> testConnection() => _api.post('$_settings/test');

  /// One lesson per call — see services/ai_lessons.py for why. [previous]
  /// are the lessons already generated in this run, so the next one does
  /// not repeat their topic or words.
  Future<AiLessonPreview> previewLesson(String courseId, {String? instructions, List<Map<String, dynamic>> previous = const []}) async {
    final res = await _api.postSlow('/api/builder/courses/$courseId/ai/preview', body: {
      if (instructions != null && instructions.trim().isNotEmpty) 'instructions': instructions.trim(),
      'previous': previous,
    });
    return AiLessonPreview(
      lesson: res['lesson'] as Map<String, dynamic>,
      warnings: ((res['warnings'] as List?) ?? const []).cast<String>(),
    );
  }

  Future<List<String>> applyLessons(String courseId, List<Map<String, dynamic>> lessons) async {
    final res = await _api.postSlow('/api/builder/courses/$courseId/ai/apply', body: {'lessons': lessons});
    return ((res['lessonIds'] as List?) ?? const []).cast<String>();
  }

  // ---- Phrase base ----

  Future<PhrasePage> listPhrases({String? languageId, String? query, int limit = 30, int offset = 0}) async {
    final res = await _api.get('/api/builder/phrases', query: {
      'languageId': ?languageId,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': limit,
      'offset': offset,
    });
    return PhrasePage(
      phrases: ((res['phrases'] as List?) ?? const []).map((e) => AdminPhrase.fromJson(e as Map<String, dynamic>)).toList(),
      total: (res['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<AdminPhrase> createPhrase({required String languageId, required String text, required String translation, String? translationTg}) async {
    final res = await _api.post('/api/builder/phrases', body: {
      'languageId': languageId,
      'text': text,
      'translation': translation,
      'translations': {'tg': translationTg ?? ''},
    });
    return AdminPhrase.fromJson(res['phrase'] as Map<String, dynamic>);
  }

  Future<AdminPhrase> updatePhrase(String id, {required String text, required String translation, String? translationTg}) async {
    final res = await _api.patch('/api/builder/phrases/$id', body: {
      'text': text,
      'translation': translation,
      'translations': {'tg': translationTg ?? ''},
    });
    return AdminPhrase.fromJson(res['phrase'] as Map<String, dynamic>);
  }

  Future<void> deletePhrase(String id) => _api.delete('/api/builder/phrases/$id');

  Future<({int added, int skipped})> importPhrases(String languageId, List<Map<String, dynamic>> phrases) async {
    final res = await _api.post('/api/builder/phrases/import', body: {'languageId': languageId, 'phrases': phrases});
    return (added: (res['added'] as num).toInt(), skipped: (res['skipped'] as num).toInt());
  }
}

class AiSettings {
  const AiSettings({required this.model, required this.hasKey, this.keyHint});
  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        model: json['model'] as String? ?? 'deepseek-chat',
        hasKey: json['hasKey'] as bool? ?? false,
        keyHint: json['keyHint'] as String?,
      );
  final String model;
  final bool hasKey;
  final String? keyHint;
}

class AiLessonPreview {
  const AiLessonPreview({required this.lesson, required this.warnings});
  final Map<String, dynamic> lesson;
  final List<String> warnings;
}

class AdminPhrase {
  const AdminPhrase({required this.id, required this.languageId, required this.text, required this.translation, this.translationTg, this.topicName});
  factory AdminPhrase.fromJson(Map<String, dynamic> json) => AdminPhrase(
        id: json['id'] as String,
        languageId: json['languageId'] as String,
        text: json['text'] as String,
        translation: json['translation'] as String? ?? '',
        translationTg: (json['translations'] as Map?)?['tg'] as String?,
        topicName: json['topicName'] as String?,
      );
  final String id;
  final String languageId;
  final String text;
  final String translation;
  final String? translationTg;
  final String? topicName;
}

class PhrasePage {
  const PhrasePage({required this.phrases, required this.total});
  final List<AdminPhrase> phrases;
  final int total;
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(apiClientProvider)));
