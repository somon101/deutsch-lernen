import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/theme/theme_provider.dart';
import '../data/profile_gamification_repository.dart';
import '../data/profile_repository.dart';
import 'profile_history.dart';
import 'profile_tokens.dart';
import 'widgets/achievement_badge.dart';
import 'widgets/avatar_viewer.dart';
import 'widgets/level_card.dart';
import 'widgets/menu_list.dart';
import 'widgets/metric_card.dart';
import 'widgets/profile_card.dart';
import 'widgets/qr_modal.dart';
import 'widgets/rank_card.dart';
import 'widgets/stat_row.dart';
import 'widgets/week_activity.dart';

/// Profile screen — real, backend-backed data (avatar editing, overall
/// lesson progress, lesson history) laid out per the gamified profile
/// mockup, plus the mockup's social/streak/level/achievements/ranking/
/// weekly-activity sections. None of the latter has a backing system yet —
/// see profile_gamification_repository.dart, which isolates every mock
/// value to one file so it's a single spot to swap once real endpoints
/// exist. Editing name/email/phone/username/bio/birth date lives in
/// features/settings/presentation/personal_details_screen.dart, reached via
/// the "Настройки" menu item below.
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
  bool _showHistory = false;

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
    final history = ref.watch(profileHistoryProvider);
    final overview = ref.watch(profileGamificationProvider);
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    return Scaffold(
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
                  _Header(user: user),
                  const SizedBox(height: 20),
                  AvatarViewer(
                    user: user,
                    avatarUrl: ref.read(apiClientProvider).assetUrl(user.avatarUrl),
                    busy: _avatarBusy,
                    onPick: _pickAvatar,
                    onPicked: _uploadAvatarBytes,
                    onDelete: _deleteAvatar,
                    isWide: isWide,
                  ),
                  const SizedBox(height: 20),
                  StatRow(items: [
                    StatRowItem(value: '${overview.social.followers}', label: 'Подписчики'),
                    StatRowItem(value: '${overview.social.mutual}', label: 'Взаимные'),
                    StatRowItem(value: '${overview.social.following}', label: 'Подписки'),
                  ]),
                  const SizedBox(height: 20),
                  history.when(
                    loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                    error: (err, st) => Text('Не удалось загрузить прогресс: $err', style: ProfileTypography.body(context)),
                    data: (data) => _MetricsRow(overview: overview, progressPercent: data.overallProgressPercent),
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  LevelCard(level: overview.level),
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
                  RankCard(rank: overview.rank),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  WeekActivityCard(activity: overview.weeklyActivity),
                  const SizedBox(height: 24),
                  Text('Разделы', style: ProfileTypography.sectionTitle(context)),
                  const SizedBox(height: 12),
                  MenuList(items: [
                    MenuListItem(icon: Icons.menu_book_outlined, label: 'Мои курсы', onTap: () => context.go('/courses')),
                    MenuListItem(icon: Icons.bookmark_border, label: 'Словарь', onTap: () {}),
                    MenuListItem(icon: Icons.star_border, label: 'Избранное', onTap: () {}),
                    MenuListItem(icon: Icons.history, label: 'История занятий', onTap: () => setState(() => _showHistory = !_showHistory)),
                    MenuListItem(icon: Icons.settings_outlined, label: 'Настройки', onTap: () => context.go('/settings')),
                  ]),
                  if (_showHistory) ...[
                    const SizedBox(height: 24),
                    _HistorySection(history: history),
                  ],
                  const SizedBox(height: 24),
                  _LogoutRow(),
                  const SizedBox(height: 24),
                ],
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
                  onPressed: () => showQrModal(context, handle: '@${user.username}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.overview, required this.progressPercent});

  final ProfileGamificationOverview overview;
  final int? progressPercent;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final hours = overview.studyMinutes ~/ 60;
    final minutes = overview.studyMinutes % 60;
    final cards = [
      MetricCard(emoji: '🔥', value: '${overview.streakDays}', label: 'дней подряд\nСерия'),
      MetricCard(icon: Icons.trending_up, accentColor: c.success, value: progressPercent == null ? '—' : '$progressPercent%', label: 'Общий прогресс'),
      MetricCard(icon: Icons.schedule, value: '$hoursч $minutesм', label: 'Время обучения'),
      MetricCard(icon: Icons.star, accentColor: c.warning, value: overview.level.score.toStringAsFixed(1), label: 'Уровень (${overview.level.code})'),
    ];

    // Row + IntrinsicHeight sizes every cell to the tallest card's actual
    // content, unlike GridView's childAspectRatio (a guessed number that
    // caused the original overflow — content taller than the guess just
    // spilled past the grid's own bounds). Two columns under 480px so each
    // card has enough width for its two-line label; four in one row above
    // that.
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = SizedBox(width: ProfileMetrics.cardGap, height: ProfileMetrics.cardGap);
        if (constraints.maxWidth < 480) {
          return Column(
            children: [
              IntrinsicHeight(child: Row(children: [Expanded(child: cards[0]), gap, Expanded(child: cards[1])])),
              gap,
              IntrinsicHeight(child: Row(children: [Expanded(child: cards[2]), gap, Expanded(child: cards[3])])),
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(children: [Expanded(child: cards[0]), gap, Expanded(child: cards[1]), gap, Expanded(child: cards[2]), gap, Expanded(child: cards[3])]),
        );
      },
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

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history});

  final AsyncValue<ProfileHistoryData> history;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('История занятий', style: ProfileTypography.sectionTitle(context)),
        const SizedBox(height: 8),
        history.when(
          loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
          error: (err, st) => Text('Не удалось загрузить: $err', style: ProfileTypography.body(context)),
          data: (data) => data.rows.isEmpty
              ? Text('Пока нет уроков.', style: ProfileTypography.body(context))
              : ProfileCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < data.rows.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: c.border),
                        _LessonHistoryTile(index: i, row: data.rows[i]),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _LessonHistoryTile extends StatelessWidget {
  const _LessonHistoryTile({required this.index, required this.row});

  final int index;
  final LessonHistoryRow row;

  @override
  Widget build(BuildContext context) {
    final summary = row.summary;
    return ListTile(
      title: Text('Урок ${index + 1}. ${row.title}', style: ProfileTypography.body(context)),
      subtitle: Text(
        summary == null
            ? 'Не начат'
            : 'Лучший результат: ${summary.bestScore}% · попыток: ${summary.attempts} · последняя: ${summary.lastScore}%',
        style: ProfileTypography.caption(context),
      ),
    );
  }
}

class _LogoutRow extends ConsumerWidget {
  const _LogoutRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.border)),
      onPressed: () => ref.read(authProvider.notifier).logout(),
      child: const Text('Выйти'),
    );
  }
}
