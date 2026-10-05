import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';

/// Topics of a studied language — the same Topic rows the lesson editor's
/// material picker lists, managed from the language workspace «Темы» tab
/// (backend routers/topics_admin.py).
class TopicsRepository {
  TopicsRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/builder/topics';

  /// `used`: true = only topics in use, false = only unused, null = all.
  Future<TopicPage> listTopics({String? languageId, String? query, bool? used, int limit = 30, int offset = 0}) async {
    final res = await _api.get(_base, query: {
      'languageId': ?languageId,
      if (used != null) 'used': '$used',
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': '$limit',
      'offset': '$offset',
    });
    return TopicPage(
      topics: ((res['topics'] as List?) ?? const []).map((e) => AdminTopicEntry.fromJson(e as Map<String, dynamic>)).toList(),
      total: (res['total'] as num?)?.toInt() ?? 0,
      usedCount: (res['usedCount'] as num?)?.toInt() ?? 0,
      unusedCount: (res['unusedCount'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> createTopic({required String languageId, required String name}) => _api.post(_base, body: {'languageId': languageId, 'name': name});

  Future<void> renameTopic(String id, String name) => _api.patch('$_base/$id', body: {'name': name});

  Future<void> deleteTopic(String id) => _api.delete('$_base/$id');

  Future<({int added, int skipped})> importTopics(String languageId, List<String> names) async {
    final res = await _api.post('$_base/import', body: {
      'languageId': languageId,
      'topics': [for (final n in names) {'name': n}],
    });
    return (added: (res['added'] as num).toInt(), skipped: (res['skipped'] as num).toInt());
  }
}

class AdminTopicEntry {
  const AdminTopicEntry({required this.id, required this.languageId, required this.name, this.usage = 0});
  factory AdminTopicEntry.fromJson(Map<String, dynamic> json) => AdminTopicEntry(
        id: json['id'] as String,
        languageId: json['languageId'] as String,
        name: json['name'] as String,
        usage: (json['usage'] as num?)?.toInt() ?? 0,
      );
  final String id;
  final String languageId;
  final String name;
  /// How many materials, questions and phrases are tagged with this topic.
  final int usage;
}

class TopicPage {
  const TopicPage({required this.topics, required this.total, this.usedCount = 0, this.unusedCount = 0});
  final List<AdminTopicEntry> topics;
  final int total;
  /// For the same language and search, regardless of the used filter.
  final int usedCount;
  final int unusedCount;
}

final topicsRepositoryProvider = Provider<TopicsRepository>((ref) => TopicsRepository(ref.watch(apiClientProvider)));
