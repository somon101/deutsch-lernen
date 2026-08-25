import 'package:file_picker/file_picker.dart';
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
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? ProfileMetrics.desktopContentMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? ProfileMetrics.pageMarginDesktop : ProfileMetrics.pageMarginMobile,
                vertical: ProfileMetrics.pageMarginMobile,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(user: user),
                  const SizedBox(height: 20),
                  _AvatarHeader(user: user, bio: overview.bio, busy: _avatarBusy, onPick: _pickAvatar, onDelete: _deleteAvatar, isWide: isWide),
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

    return Row(
      children: [
        SizedBox(
          width: 40,
          child: canPop
              ? IconButton(icon: Icon(Icons.arrow_back, color: c.text), onPressed: () => Navigator.of(context).pop())
              : null,
        ),
        Expanded(child: Text('Профиль', textAlign: TextAlign.center, style: ProfileTypography.sectionTitle(context))),
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
    );
  }
}

bool _isOnline(AppUser user) {
  final raw = user.lastActiveAt;
  if (raw == null) return false;
  final at = DateTime.tryParse(raw);
  if (at == null) return false;
  return DateTime.now().toUtc().difference(at.toUtc()) < const Duration(minutes: 5);
}

class _AvatarHeader extends ConsumerWidget {
  const _AvatarHeader({required this.user, required this.bio, required this.busy, required this.onPick, required this.onDelete, required this.isWide});

  final AppUser user;
  final String bio;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onDelete;
  final bool isWide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.profileColors;
    final avatarUrl = ref.read(apiClientProvider).assetUrl(user.avatarUrl);
    final size = isWide ? ProfileMetrics.avatarDesktop : ProfileMetrics.avatarMobile;
    final online = _isOnline(user);

    return Column(
      children: [
        Stack(
          children: [
            SizedBox(
              width: size,
              height: size,
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: size / 2,
                    backgroundColor: c.card,
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty
                        ? Text(user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?', style: ProfileTypography.username(context))
                        : null,
                  ),
                  if (busy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
                  if (online)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(color: c.success, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                      ),
                    ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: busy ? null : onPick,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle, border: Border.all(color: c.bg, width: 2)),
                        child: const Icon(Icons.camera_alt, size: 15, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('${user.firstName} ${user.lastName}'.trim(), style: ProfileTypography.username(context)),
        const SizedBox(height: 2),
        Text('@${user.username}', style: ProfileTypography.body(context).copyWith(color: c.accent)),
        const SizedBox(height: 8),
        Text(bio, textAlign: TextAlign.center, style: ProfileTypography.body(context).copyWith(color: c.textMuted)),
        if (user.avatarUrl != null)
          TextButton(
            onPressed: busy ? null : onDelete,
            child: Text('Удалить фото', style: ProfileTypography.caption(context).copyWith(color: c.danger)),
          ),
      ],
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
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: ProfileMetrics.cardGap,
      mainAxisSpacing: ProfileMetrics.cardGap,
      childAspectRatio: 0.85,
      children: cards,
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
