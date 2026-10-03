import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api/api_client.dart';

/// Rule base: one-sentence rules per studied language (backend
/// routers/rules.py).
class RulesRepository {
  RulesRepository(this._api);

  final ApiClient _api;
  static const _base = '/api/builder/rules';

  Future<RulePage> listRules({String? languageId, String? query, int limit = 30, int offset = 0}) async {
    final res = await _api.get(_base, query: {
      'languageId': ?languageId,
      if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
      'limit': '$limit',
      'offset': '$offset',
    });
    return RulePage(
      rules: ((res['rules'] as List?) ?? const []).map((e) => AdminRule.fromJson(e as Map<String, dynamic>)).toList(),
      total: (res['total'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> createRule({required String languageId, required String text}) =>
      _api.post(_base, body: {'languageId': languageId, 'text': text});

  Future<void> updateRule(String id, String text) => _api.patch('$_base/$id', body: {'text': text});

  Future<void> deleteRule(String id) => _api.delete('$_base/$id');

  Future<({int added, int skipped})> importRules(String languageId, List<String> texts) async {
    final res = await _api.post('$_base/import', body: {
      'languageId': languageId,
      'rules': [for (final t in texts) {'text': t}],
    });
    return (added: (res['added'] as num).toInt(), skipped: (res['skipped'] as num).toInt());
  }
}

class AdminRule {
  const AdminRule({required this.id, required this.languageId, required this.text});
  factory AdminRule.fromJson(Map<String, dynamic> json) =>
      AdminRule(id: json['id'] as String, languageId: json['languageId'] as String, text: json['text'] as String);
  final String id;
  final String languageId;
  final String text;
}

class RulePage {
  const RulePage({required this.rules, required this.total});
  final List<AdminRule> rules;
  final int total;
}

final rulesRepositoryProvider = Provider<RulesRepository>((ref) => RulesRepository(ref.watch(apiClientProvider)));
