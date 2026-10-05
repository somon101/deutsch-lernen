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

  /// "" restores the built-in default prompt.
  Future<AiSettings> savePrompt(String prompt) async =>
      AiSettings.fromJson((await _api.patch(_settings, body: {'systemPrompt': prompt}))['settings'] as Map<String, dynamic>);

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

  /// `used`: true = only phrases placed in a lesson, false = the rest.
  Future<PhrasePage> listPhrases({String? languageId, String? query, bool? used, int limit = 30, int offset = 0}) async {
    final res = await _api.get('/api/builder/phrases', query: {
      'languageId': ?languageId,
      if (used != null) 'used': '$used',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': limit,
      'offset': offset,
    });
    return PhrasePage(
      phrases: ((res['phrases'] as List?) ?? const []).map((e) => AdminPhrase.fromJson(e as Map<String, dynamic>)).toList(),
      total: (res['total'] as num?)?.toInt() ?? 0,
      usedCount: (res['usedCount'] as num?)?.toInt() ?? 0,
      unusedCount: (res['unusedCount'] as num?)?.toInt() ?? 0,
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

class AiModelOption {
  const AiModelOption({required this.id, required this.label, required this.description});
  factory AiModelOption.fromJson(Map<String, dynamic> json) => AiModelOption(
        id: json['id'] as String,
        label: json['label'] as String,
        description: json['description'] as String? ?? '',
      );
  final String id;
  final String label;
  final String description;
}

class AiSettings {
  const AiSettings({
    required this.model,
    required this.hasKey,
    required this.availableModels,
    this.keyHint,
    this.systemPrompt = '',
    this.defaultSystemPrompt = '',
    this.isCustomPrompt = false,
    this.outputFormatPrompt = '',
  });
  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
        model: json['model'] as String? ?? 'deepseek-chat',
        hasKey: json['hasKey'] as bool? ?? false,
        keyHint: json['keyHint'] as String?,
        availableModels: [
          for (final m in (json['availableModels'] as List<dynamic>? ?? const []))
            AiModelOption.fromJson(m as Map<String, dynamic>),
        ],
        systemPrompt: json['systemPrompt'] as String? ?? '',
        defaultSystemPrompt: json['defaultSystemPrompt'] as String? ?? '',
        isCustomPrompt: json['isCustomPrompt'] as bool? ?? false,
        outputFormatPrompt: json['outputFormatPrompt'] as String? ?? '',
      );
  final String model;
  /// The lesson-writing rules sent to the model (editable).
  final String systemPrompt;
  final String defaultSystemPrompt;
  final bool isCustomPrompt;
  /// Fixed tail always appended after the rules; shown read-only.
  final String outputFormatPrompt;
  final bool hasKey;
  final String? keyHint;
  final List<AiModelOption> availableModels;
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
  const PhrasePage({required this.phrases, required this.total, this.usedCount = 0, this.unusedCount = 0});
  final List<AdminPhrase> phrases;
  final int total;
  final int usedCount;
  final int unusedCount;
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(apiClientProvider)));
