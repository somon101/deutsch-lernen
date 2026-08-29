import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/theme/theme_provider.dart';
import '../../courses/presentation/courses_overview.dart';
import '../../courses/presentation/widgets/lesson_grid_card.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_tokens.dart';

/// Which language the lesson list below is showing — deliberately
/// independent of the profile's own progress-language preference
/// (AppUser.selectedLanguageId / effectiveLanguageProvider, §4, 2026-08-29):
/// switching this here never touches the backend and never changes what
/// language the profile's "Прогресс" number is for. Resets to "no override"
/// (auto-pick) every cold start/screen rebuild — nothing asked for this to
/// survive a restart.
final homeLanguageIdProvider = StateProvider.autoDispose<String?>((ref) => null);

/// The app's landing screen: a language switcher plus a flat list of that
/// language's lessons (no course/level grouping — levels stay hidden from
/// learners, per the approved Home redesign). Replaces the old placeholder
/// menu (Курсы/Профиль/... nav cards) now that the "Курсы" section itself is
/// gone; every one of those destinations is still reachable from the
/// bottom bar/rail or from Settings (logout included).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  DateTime? _lastBackPress;

  void _handleBack() {
    final now = DateTime.now();
    if (_lastBackPress != null && now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Нажмите ещё раз для выхода'), duration: Duration(seconds: 2)),
    );
  }

  Future<void> _pickLanguage(List<LanguageOption> languages, String current) async {
    final c = context.profileColors;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius), border: Border.all(color: c.border)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(alignment: Alignment.centerLeft, child: Text('Язык', style: ProfileTypography.sectionTitle(sheetContext))),
              ),
              for (final lang in languages)
                ListTile(
                  title: Text(lang.name, style: ProfileTypography.body(sheetContext)),
                  trailing: lang.id == current ? Icon(Icons.check, color: c.accent) : null,
                  onTap: () => Navigator.of(sheetContext).pop(lang.id),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    if (picked != null) ref.read(homeLanguageIdProvider.notifier).state = picked;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    final languagesAsync = ref.watch(availableLanguagesProvider);
    final override = ref.watch(homeLanguageIdProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Deutsch Lernen'),
          actions: [
            IconButton(
              tooltip: themeMode == ThemeMode.dark ? 'Светлая тема' : 'Тёмная тема',
              icon: Icon(themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            ),
          ],
        ),
        body: languagesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(child: Text('Не удалось загрузить языки: $err')),
          data: (languages) {
            if (languages.isEmpty) {
              return const Center(child: Text('Курсы пока не опубликованы'));
            }
            final selectedId = languages.any((l) => l.id == override) ? override! : languages.first.id;
            final selected = languages.firstWhere((l) => l.id == selectedId);
            final lessonsAsync = ref.watch(homeLessonsProvider((id: selected.id, name: selected.name)));

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (user != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Text('Привет, ${user.firstName}!', style: Theme.of(context).textTheme.titleLarge),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: languages.length > 1 ? () => _pickLanguage(languages, selected.id) : null,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(selected.name, style: Theme.of(context).textTheme.titleMedium)),
                          if (languages.length > 1) const Icon(Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: lessonsAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, st) => Center(child: Text('Не удалось загрузить уроки: $err')),
                    data: (lessons) {
                      if (lessons.isEmpty) {
                        return const Center(child: Text('Уроков пока нет'));
                      }
                      return RefreshIndicator(
                        onRefresh: () async => ref.invalidate(homeLessonsProvider((id: selected.id, name: selected.name))),
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomBarClearance(context)),
                          children: [
                            for (var i = 0; i < lessons.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: LessonGridCard(
                                  index: i,
                                  lesson: lessons[i],
                                  onTap: () => context.go(
                                    lessons[i].courseId != null
                                        ? '/courses/${lessons[i].courseId}/lesson/${lessons[i].lessonId}/${lessons[i].targetStage.name}'
                                        : '/lesson/${lessons[i].lessonId}/${lessons[i].targetStage.name}',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
