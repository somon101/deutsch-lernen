import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/back_guard.dart';
import '../../leaderboard/data/leaderboard_repository.dart';
import '../../social/data/social_repository.dart';
import '../data/profile_gamification_repository.dart';
import '../data/profile_repository.dart';
import 'profile_tokens.dart';
import 'widgets/achievement_badge.dart';
import 'widgets/avatar_viewer.dart';
import 'widgets/level_card.dart';
import 'widgets/metrics_row.dart';
import 'widgets/profile_card.dart';
import 'widgets/rank_card.dart';
import 'widgets/stat_row.dart';
import 'widgets/week_activity.dart';

/// Profile screen — real, backend-backed data (avatar editing, overall
/// lesson progress, lesson history) laid out per the gamified profile
/// mockup, plus the mockup's social/streak/level/achievements/ranking/
/// weekly-activity sections. None of the latter has a backing system yet —
/// see profile_gamification_repository.dart, which isolates every mock
/// value to one file so it's a single spot to swap once real endpoints
/// exist. Editing name/email/phone/username/bio/birth date and logout both
/// live in features/settings/presentation — this screen is read-only plus
/// the avatar.
///
/// Responsive per the design spec: <768px is one column with the app's
/// bottom tab bar (AppShell); >=768px centers content at max 900px next to
/// the existing left rail.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _avatarBusy = false;
  bool _avatarExpanded = false;

  Future<void> _pickAvatar() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _avatarBusy = true);
    try {
      final bytes = await file.readAsBytes();
      final user = await ref.read(profileRepositoryProvider).uploadAvatar(bytes: bytes, filename: file.name);
      await ref.read(authProvider.notifier).updateLocalUser(user);
    } catch (_) {
      // Avatar upload failing is non-critical to the rest of the page.
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      final user = await ref.read(profileRepositoryProvider).deleteAvatar();
      await ref.read(authProvider.notifier).updateLocalUser(user);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  /// AvatarViewer's "Изменить фото" tile — already-cropped bytes from a
  /// direct gallery pick, no bottom-sheet choice of source.
  Future<void> _uploadAvatarBytes(Uint8List bytes, String filename) async {
    setState(() => _avatarBusy = true);
    try {
      final user = await ref.read(profileRepositoryProvider).uploadAvatar(bytes: bytes, filename: filename);
      await ref.read(authProvider.notifier).updateLocalUser(user);
    } catch (_) {
      // Avatar upload failing is non-critical to the rest of the page.
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null) return const SizedBox.shrink();

    final c = context.profileColors;
    final overallProgress = ref.watch(overallProgressProvider);
    final totalTime = ref.watch(totalTimeSecondsProvider);
    final streakDays = ref.watch(streakDaysProvider);
    final weekActivity = ref.watch(weekActivityProvider);
    final myRank = ref.watch(myRankProvider);
    final myFollowStats = ref.watch(userProfileProvider(user.id));
    final overview = ref.watch(profileGamificationProvider);
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? ProfileMetrics.desktopContentMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                isWide ? ProfileMetrics.pageMarginDesktop : ProfileMetrics.pageMarginMobile,
                ProfileMetrics.pageMarginMobile,
                isWide ? ProfileMetrics.pageMarginDesktop : ProfileMetrics.pageMarginMobile,
                ProfileMetrics.pageMarginMobile + bottomBarClearance(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!_avatarExpanded) ...[
                    _Header(user: user),
                    const SizedBox(height: 20),
                  ],
                  AvatarViewer(
                    user: user,
                    avatarUrl: ref.read(apiClientProvider).assetUrl(user.avatarUrl),
                    busy: _avatarBusy,
                    onPick: _pickAvatar,
                    onPicked: _uploadAvatarBytes,
                    onDelete: _deleteAvatar,
                    isWide: isWide,
                    onExpandedChanged: (expanded) => setState(() => _avatarExpanded = expanded),
                  ),
                  const SizedBox(height: 20),
                  myFollowStats.when(
                    loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    error: (err, st) => Text('Не удалось загрузить подписки: $err', style: ProfileTypography.body(context)),
                    data: (stats) => StatRow(items: [
                      StatRowItem(value: '${stats.followersCount}', label: 'Подписчики', onTap: () => context.push('/users/${user.id}/followers')),
                      StatRowItem(value: '${stats.mutualCount}', label: 'Взаимные', onTap: () => context.push('/users/${user.id}/mutual')),
                      StatRowItem(value: '${stats.followingCount}', label: 'Подписки', onTap: () => context.push('/users/${user.id}/following')),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  if (overallProgress.isLoading || totalTime.isLoading || streakDays.isLoading || myRank.isLoading)
                    const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
                  else if (overallProgress.hasError || totalTime.hasError || streakDays.hasError || myRank.hasError)
                    Text(
                      'Не удалось загрузить прогресс: ${overallProgress.error ?? totalTime.error ?? streakDays.error ?? myRank.error}',
                      style: ProfileTypography.body(context),
                    )
                  else
                    MetricsRow(
                      progressPercent: overallProgress.value,
                      timeSeconds: totalTime.value,
                      streakDays: streakDays.value ?? 0,
                      points: myRank.value?.points ?? 0,
                    ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  LevelCard(level: overview.level),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  _MyWordsEntry(onTap: () => context.push('/my-words')),
                  const SizedBox(height: 24),
                  _SectionHeader(title: 'Достижения', onSeeAll: () {}),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: overview.achievements.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => AchievementBadge(achievement: overview.achievements[i]),
                    ),
                  ),
                  const SizedBox(height: 24),
                  myRank.when(
                    loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    error: (err, st) => Text('Не удалось загрузить рейтинг: $err', style: ProfileTypography.body(context)),
                    data: (summary) => RankCard(summary: summary),
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  weekActivity.when(
                    loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    error: (err, st) => Text('Не удалось загрузить активность: $err', style: ProfileTypography.body(context)),
                    data: (summary) => WeekActivityCard(activity: summary),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final themeMode = ref.watch(themeModeProvider);
    final canPop = Navigator.of(context).canPop();

    // A Row with an empty 40px slot on the left (for a back button that
    // usually isn't there — this is the bottom-tab root) and two full-size
    // IconButtons on the right centers the Expanded title against
    // mismatched side widths, visibly shifting it left. A Stack with the
    // title truly centered — independent of what's in the side slots —
    // fixes that regardless of which icons end up on either side.
    return SizedBox(
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('Профиль', style: ProfileTypography.sectionTitle(context)),
          if (canPop)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(icon: Icon(Icons.arrow_back, color: c.text), onPressed: () => Navigator.of(context).pop()),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: themeMode == ThemeMode.dark ? 'Светлая тема' : 'Тёмная тема',
                  icon: Icon(themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, color: c.text),
                  onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
                ),
                IconButton(
                  tooltip: 'Поделиться профилем',
                  icon: Icon(Icons.qr_code_2, color: c.text),
                  onPressed: () => context.push('/profile/qr'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Entry point into "Мои слова" (§ word cards, 2026-08-31) — the profile
/// didn't have this section before, so it's a plain new tappable card, not
/// a redesign of anything existing.
class _MyWordsEntry extends StatelessWidget {
  const _MyWordsEntry({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ProfileMetrics.cardRadius),
      child: ProfileCard(
        child: Row(
          children: [
            Icon(Icons.style_outlined, color: c.accent),
            const SizedBox(width: 12),
            Expanded(child: Text('Мои слова', style: ProfileTypography.body(context).copyWith(fontWeight: FontWeight.w600))),
            Icon(Icons.chevron_right, color: c.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onSeeAll});
  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: ProfileTypography.sectionTitle(context)),
        TextButton(
          onPressed: onSeeAll,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Все', style: ProfileTypography.body(context).copyWith(color: c.accent)),
              Icon(Icons.chevron_right, size: 18, color: c.accent),
            ],
          ),
        ),
      ],
    );
  }
}

