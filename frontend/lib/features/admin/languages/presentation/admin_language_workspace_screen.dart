import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../admin_tokens.dart';
import '../../course_builder/presentation/admin_courses_hub_screen.dart';
import '../../phrases/presentation/admin_phrases_screen.dart';
import '../../topics/presentation/admin_topics_screen.dart';
import '../../vocabulary/presentation/admin_vocabulary_screen.dart';
import 'admin_languages_screen.dart';
import 'language_api_tab.dart';

const workspaceTabs = ['courses', 'vocabulary', 'phrases', 'topics', 'api'];

/// One language's workspace: its courses, dictionary, phrases and topics,
/// each the existing screen locked to this language.
class AdminLanguageWorkspaceScreen extends ConsumerWidget {
  const AdminLanguageWorkspaceScreen({super.key, required this.languageId, this.initialTab});

  final String languageId;
  final String? initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = ref.watch(adminLanguagesProvider).value;
    final matches = languages?.where((l) => l.id == languageId);
    final language = matches == null || matches.isEmpty ? null : matches.first;
    final index = workspaceTabs.indexOf(initialTab ?? 'courses');

    return BackGuard(
      fallbackPath: '/admin/courses',
      child: Theme(
        data: lightTheme,
        child: DefaultTabController(
          length: workspaceTabs.length,
          initialIndex: index < 0 ? 0 : index,
          child: Scaffold(
            backgroundColor: AdminColors.bg,
            appBar: AppBar(
              backgroundColor: AdminColors.card,
              foregroundColor: AdminColors.text,
              elevation: 0,
              leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Все языки', onPressed: () => context.go('/admin/courses')),
              title: Row(
                children: [
                  Flexible(child: Text(language?.name ?? 'Язык', style: AdminTypography.pageTitle, overflow: TextOverflow.ellipsis)),
                  if (language != null) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: (language.isPublished ? AdminColors.success : AdminColors.warn).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        language.isPublished ? 'Опубликовано' : 'Черновик',
                        style: AdminTypography.caption.copyWith(color: language.isPublished ? AdminColors.success : AdminColors.warn, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ],
              ),
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [Tab(text: 'Курсы'), Tab(text: 'Словарь'), Tab(text: 'Фразы'), Tab(text: 'Темы'), Tab(text: 'API')],
              ),
            ),
            body: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                AdminCoursesHubScreen(languageId: languageId, languageName: language?.name),
                AdminVocabularyScreen(languageId: languageId),
                AdminPhrasesScreen(languageId: languageId),
                AdminTopicsScreen(languageId: languageId),
                LanguageApiTab(languageId: languageId),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
