import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';

/// A word card (§ word cards, 2026-08-31) — the same shape the backend's
/// `_word_card_dto` returns everywhere a wordId is looked up (single,
/// batch, or "Мои слова"), so one model covers all three call sites.
class WordCard {
  const WordCard({
    required this.wordId,
    required this.word,
    required this.translation,
    required this.pronunciation,
    required this.audioUrl,
    required this.imageUrl,
    required this.categoryId,
    required this.categoryName,
    required this.languageId,
  });

  factory WordCard.fromJson(Map<String, dynamic> json) => WordCard(
        wordId: json['wordId'] as String,
        word: json['word'] as String,
        translation: json['translation'] as String,
        pronunciation: json['pronunciation'] as String?,
        audioUrl: json['audioUrl'] as String?,
        imageUrl: json['imageUrl'] as String?,
        categoryId: json['categoryId'] as String?,
        categoryName: json['categoryName'] as String?,
        languageId: json['languageId'] as String?,
      );

  final String wordId;
  final String word;
  final String translation;
  final String? pronunciation;
  final String? audioUrl;
  final String? imageUrl;
  final String? categoryId;
  final String? categoryName;
  final String? languageId;
}

class VocabularyRepository {
  VocabularyRepository(this._api);

  final ApiClient _api;

  /// "Мои слова" — every word the signed-in user has learned.
  Future<List<WordCard>> fetchMyWords() async {
    final res = await _api.get('/api/me/words');
    return (res['words'] as List<dynamic>).map((w) => WordCard.fromJson(w as Map<String, dynamic>)).toList();
  }

  Future<WordCard?> fetchWord(String wordId) async {
    try {
      final res = await _api.get('/api/words/${Uri.encodeComponent(wordId)}');
      return WordCard.fromJson(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<WordCard>> fetchWords(List<String> wordIds) async {
    if (wordIds.isEmpty) return [];
    final res = await _api.get('/api/words/', query: {'ids': wordIds.join(',')});
    return (res['words'] as List<dynamic>).map((w) => WordCard.fromJson(w as Map<String, dynamic>)).toList();
  }
}

final vocabularyRepositoryProvider = Provider<VocabularyRepository>((ref) => VocabularyRepository(ref.watch(apiClientProvider)));

final myWordsProvider = FutureProvider.autoDispose<List<WordCard>>((ref) {
  return ref.watch(vocabularyRepositoryProvider).fetchMyWords();
});
