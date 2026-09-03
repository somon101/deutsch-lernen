import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/widgets/word_audio_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../../profile/presentation/widgets/profile_card.dart';
import '../data/vocabulary_repository.dart';

/// "Мои слова" (§7, § word cards, 2026-08-31) — every word the signed-in
/// user has learned (a lesson fully completed = its words are learned),
/// grouped by category. Reached with `context.push(...)` from ProfileScreen
/// (already on the Navigator stack), same pattern as `/profile/qr` and the
/// follow-list screens — Flutter's automatic back arrow just works.
class MyWordsScreen extends ConsumerWidget {
  const MyWordsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final l10n = AppLocalizations.of(context);
    final words = ref.watch(myWordsProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(l10n.myWordsTitle)),
      body: words.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text(l10n.myWordsLoadError(err), style: ProfileTypography.body(context))),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.myWordsEmpty,
                  textAlign: TextAlign.center,
                  style: ProfileTypography.body(context),
                ),
              ),
            );
          }

          final groups = <String, List<WordCard>>{};
          for (final w in list) {
            final key = w.categoryName ?? l10n.myWordsUncategorized;
            groups.putIfAbsent(key, () => []).add(w);
          }
          final categoryNames = groups.keys.toList()..sort();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myWordsProvider),
            child: ListView.builder(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomBarClearance(context)),
              itemCount: categoryNames.length,
              itemBuilder: (context, i) {
                final name = categoryNames[i];
                final categoryWords = groups[name]!;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, left: 4),
                        child: Text(name, style: ProfileTypography.sectionTitle(context)),
                      ),
                      ProfileCard(
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            for (var j = 0; j < categoryWords.length; j++) ...[
                              if (j > 0) Divider(height: 1, color: c.border),
                              _WordRow(word: categoryWords[j]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _WordRow extends ConsumerWidget {
  const _WordRow({required this.word});
  final WordCard word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final imageUrl = ref.read(apiClientProvider).assetUrl(word.imageUrl);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          if (imageUrl.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(imageUrl, width: 40, height: 40, fit: BoxFit.cover),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(word.word, style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600)),
                    WordAudioButton(word: word.word, audioUrl: word.audioUrl, size: 16),
                  ],
                ),
                if (word.pronunciation != null && word.pronunciation!.isNotEmpty)
                  Text('[${word.pronunciation}]', style: ProfileTypography.caption(context)),
                Text(word.translation, style: ProfileTypography.caption(context).copyWith(color: c.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
