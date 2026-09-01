import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/api/api_client.dart';
import 'core/api/router_refresh.dart';
import 'core/auth/auth_state.dart';
import 'core/auth/user.dart';
import 'core/locale/locale_provider.dart';
import 'core/push/push_service.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/widgets/app_lifecycle_heartbeat.dart';
import 'l10n/app_localizations.dart';
import 'features/admin/course_builder/presentation/admin_courses_hub_screen.dart';
import 'features/admin/course_builder/presentation/builder_course_edit_screen.dart';
import 'features/admin/course_builder/presentation/builder_lesson_edit_screen.dart';
import 'features/admin/legacy_lessons/presentation/admin_lesson_edit_screen.dart';
import 'features/admin/legacy_lessons/presentation/admin_legacy_lessons_screen.dart';
import 'features/admin/users/presentation/admin_user_detail_screen.dart';
import 'features/admin/users/presentation/admin_users_all_screen.dart';
import 'features/admin/users/presentation/admin_users_screen.dart';
import 'features/auth/presentation/forbidden_screen.dart';
import 'features/auth/presentation/login_screen.dart';
import 'features/home/presentation/home_screen.dart';
import 'features/leaderboard/presentation/leaderboard_screen.dart';
import 'features/lesson_runner/presentation/lesson_runner_screen.dart';
import 'features/profile/presentation/profile_qr_screen.dart';
import 'features/profile/presentation/profile_screen.dart';
import 'features/settings/presentation/personal_details_screen.dart';
import 'features/settings/presentation/security_privacy_screen.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/shell/presentation/app_shell.dart';
import 'features/social/data/social_repository.dart';
import 'features/social/presentation/follow_list_screen.dart';
import 'features/social/presentation/user_profile_screen.dart';
import 'features/vocabulary/presentation/my_words_screen.dart';

/// Route access levels, mirroring the adminOnly/staffOnly props ProtectedRoute
/// (src/components/ProtectedRoute.tsx) is given per-route in App.tsx — kept
/// as one table here instead of scattered per-route props, since go_router's
/// redirect is centralized rather than a wrapper-per-route like React
/// Router's.
enum _Access { public, any, staffOnly, adminOnly }

_Access _accessFor(String path) {
  if (path == '/login' || path == '/403') return _Access.public;
  if (path == '/admin' || path.startsWith('/admin/users/')) return _Access.adminOnly;
  if (path.startsWith('/admin/')) return _Access.staffOnly;
  return _Access.any;
}

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = GoRouterRefreshNotifier();
  ref.listen(authProvider, (previous, next) => refreshNotifier.refresh());
  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      // Auth restore from secure storage hasn't resolved yet — don't
      // redirect mid-flight, or a real session would flash a login screen.
      if (authState.isLoading) return null;

      final user = authState.value;
      final path = state.matchedLocation;
      final access = _accessFor(path);

      if (user == null) {
        return access == _Access.public ? null : '/login';
      }
      // Already authenticated — bounce away from the login screen itself,
      // same as LoginPage.tsx's own immediate <Navigate>.
      if (path == '/login') return '/';

      if (access == _Access.adminOnly && user.role != UserRole.admin) return '/403';
      if (access == _Access.staffOnly && !user.isStaff) return '/403';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/403', builder: (context, state) => const ForbiddenScreen()),
      // Shared desktop rail chrome around the top-level sections — everything
      // else (lesson runner, detail/edit screens) stays outside it and is
      // pushed full-screen as before.
      ShellRoute(
        builder: (context, state, child) => AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
          GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
          GoRoute(path: '/leaderboard', builder: (context, state) => const LeaderboardScreen()),
          GoRoute(path: '/admin', builder: (context, state) => const AdminUsersScreen()),
          GoRoute(path: '/admin/users/all', builder: (context, state) => const AdminUsersAllScreen()),
          GoRoute(path: '/admin/courses', builder: (context, state) => const AdminCoursesHubScreen()),
        ],
      ),
      GoRoute(
        path: '/lesson/:lessonId',
        redirect: (context, state) => '/lesson/${state.pathParameters['lessonId']}/vocabulary',
      ),
      GoRoute(
        path: '/lesson/:lessonId/:stage',
        builder: (context, state) => LessonRunnerScreen(
          lessonId: state.pathParameters['lessonId']!,
          stage: state.pathParameters['stage']!,
        ),
      ),
      GoRoute(
        path: '/courses/:courseId/lesson/:lessonId/:stage',
        builder: (context, state) => LessonRunnerScreen(
          courseId: state.pathParameters['courseId'],
          lessonId: state.pathParameters['lessonId']!,
          stage: state.pathParameters['stage']!,
        ),
      ),
      GoRoute(path: '/admin/courses/legacy', builder: (context, state) => const AdminLegacyLessonsScreen()),
      GoRoute(
        path: '/admin/lessons/:lessonId',
        builder: (context, state) => AdminLessonEditScreen(lessonId: state.pathParameters['lessonId']!),
      ),
      // Old constructor list URL — kept as a redirect so existing
      // bookmarks/links still work, mirroring App.tsx's own <Navigate> for it.
      GoRoute(path: '/admin/builder', redirect: (context, state) => '/admin/courses'),
      GoRoute(
        path: '/admin/builder/:courseId',
        builder: (context, state) => BuilderCourseEditScreen(courseId: state.pathParameters['courseId']!),
      ),
      GoRoute(
        path: '/admin/builder/:courseId/lessons/:lessonId',
        builder: (context, state) => BuilderLessonEditScreen(
          courseId: state.pathParameters['courseId']!,
          lessonId: state.pathParameters['lessonId']!,
        ),
      ),
      GoRoute(
        path: '/admin/users/:id',
        builder: (context, state) => AdminUserDetailScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/profile/qr', builder: (context, state) => const ProfileQrScreen()),
      GoRoute(path: '/my-words', builder: (context, state) => const MyWordsScreen()),
      GoRoute(
        path: '/users/:id',
        builder: (context, state) => UserProfileScreen(userId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/users/:id/followers',
        builder: (context, state) => FollowListScreen(userId: state.pathParameters['id']!, kind: FollowListKind.followers),
      ),
      GoRoute(
        path: '/users/:id/following',
        builder: (context, state) => FollowListScreen(userId: state.pathParameters['id']!, kind: FollowListKind.following),
      ),
      GoRoute(
        path: '/users/:id/mutual',
        builder: (context, state) => FollowListScreen(userId: state.pathParameters['id']!, kind: FollowListKind.mutual),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/settings/personal', builder: (context, state) => const PersonalDetailsScreen()),
      GoRoute(path: '/settings/security', builder: (context, state) => const SecurityPrivacyScreen()),
    ],
  );
});

class DeutschLernenApp extends ConsumerStatefulWidget {
  const DeutschLernenApp({super.key});

  @override
  ConsumerState<DeutschLernenApp> createState() => _DeutschLernenAppState();
}

class _DeutschLernenAppState extends ConsumerState<DeutschLernenApp> {
  @override
  void initState() {
    super.initState();
    // Tapping a push notification should jump straight to the lesson it's
    // about — the GoRouter instance navigates directly, no BuildContext
    // needed. Set up once; safe to fire before the first frame since
    // GoRouter queues navigation until it's ready.
    listenForNotificationTaps((path) => ref.read(routerProvider).go(path));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    // Registers (or refreshes) this device's push token whenever a user
    // becomes available — a fresh login and a restored session both flow
    // through the same authProvider transition to non-null, so one listener
    // covers both without a separate "on login" hook.
    ref.listen<AsyncValue<AppUser?>>(authProvider, (previous, next) {
      final user = next.value;
      if (user != null) registerPushTokenIfSupported(ref.read(apiClientProvider));
    });

    return MaterialApp.router(
      title: 'Deutsch Lernen',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppLifecycleHeartbeat(child: child!),
      routerConfig: router,
    );
  }
}
