import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/locale/locale_provider.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/settings_repository.dart';
import 'widgets/avatar_picker_sheet.dart';
import 'widgets/profile_header.dart';
import 'widgets/settings_nav_tile.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_switch_tile.dart';

/// Version shown under "О приложении" — matches pubspec.yaml's `version:`.
/// TODO: подключить API — вынести через package_info_plus, если он
/// появится в проекте, вместо строкового литерала.
const _appVersion = '1.0.0';

const _dailyGoalOptions = [10, 20, 30, 60];

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _avatarBusy = false;

  Future<void> _pickAvatar(Uint8List bytes, String filename) async {
    setState(() => _avatarBusy = true);
    try {
      final user = await ref.read(profileRepositoryProvider).uploadAvatar(bytes: bytes, filename: filename);
      await ref.read(authProvider.notifier).updateLocalUser(user);
    } catch (_) {
      // Avatar upload failing is non-critical to the rest of the screen.
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _avatarBusy = true);
    try {
      final user = await ref.read(profileRepositoryProvider).deleteAvatar();
      await ref.read(authProvider.notifier).updateLocalUser(user);
    } finally {
      if (mounted) setState(() => _avatarBusy = false);
    }
  }

  void _comingSoon() {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.comingSoon)));
  }

  Future<void> _confirmLogout() async {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.logoutConfirmTitle),
        content: Text(l10n.logoutConfirmBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final settings = ref.watch(settingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final avatarUrl = ref.read(apiClientProvider).assetUrl(user.avatarUrl);
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    Future<void> openAvatarSheet() => showAvatarPickerSheet(
          context,
          hasAvatar: user.avatarUrl != null,
          onPicked: _pickAvatar,
          onRemove: _removeAvatar,
        );

    return BackGuard(
      fallbackPath: '/profile',
      child: Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
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
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          tooltip: l10n.back,
                          icon: Icon(Icons.arrow_back, color: c.text),
                          onPressed: () => context.go('/profile'),
                        ),
                      ),
                      Expanded(child: Text(l10n.settingsTitle, textAlign: TextAlign.center, style: ProfileTypography.sectionTitle(context))),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ProfileHeader(user: user, avatarUrl: avatarUrl, busy: _avatarBusy, onAvatarTap: openAvatarSheet),
                  const SizedBox(height: 28),
                  SettingsSection(
                    title: l10n.sectionAccount,
                    children: [
                      SettingsNavTile(icon: Icons.badge_outlined, label: l10n.personalDetails, onTap: () => context.go('/settings/personal')),
                      SettingsNavTile(icon: Icons.shield_outlined, label: l10n.securityPrivacy, onTap: () => context.go('/settings/security')),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.sectionLearning,
                    children: [
                      SettingsNavTile(
                        icon: Icons.flag_outlined,
                        label: l10n.dailyGoal,
                        value: l10n.dailyGoalMinutes(settings.dailyGoalMinutes),
                        onTap: () => _pickDailyGoal(context, settings.dailyGoalMinutes),
                      ),
                      SettingsNavTile(
                        icon: Icons.trending_up,
                        label: l10n.languageLevel,
                        value: settings.languageLevel.label,
                        onTap: () => _pickLanguageLevel(context, settings.languageLevel),
                      ),
                      SettingsSwitchTile(
                        icon: Icons.volume_up_outlined,
                        label: l10n.lessonSounds,
                        value: settings.lessonSounds,
                        onChanged: (v) => ref.read(settingsProvider.notifier).setLessonSounds(v),
                      ),
                      SettingsSwitchTile(
                        icon: Icons.record_voice_over_outlined,
                        label: l10n.wordPronunciation,
                        value: settings.wordPronunciation,
                        onChanged: (v) => ref.read(settingsProvider.notifier).setWordPronunciation(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.sectionNotifications,
                    children: [
                      SettingsSwitchTile(
                        icon: Icons.notifications_outlined,
                        label: l10n.pushNotifications,
                        value: settings.pushNotifications,
                        onChanged: (v) => ref.read(settingsProvider.notifier).setPushNotifications(v),
                      ),
                      SettingsSwitchTile(
                        icon: Icons.alarm_outlined,
                        label: l10n.lessonReminder,
                        value: settings.lessonReminder,
                        onChanged: (v) => ref.read(settingsProvider.notifier).setLessonReminder(v),
                      ),
                      if (settings.lessonReminder)
                        SettingsNavTile(
                          icon: Icons.access_time,
                          label: l10n.reminderTime,
                          value: _formatTime(settings.lessonReminderHour, settings.lessonReminderMinute),
                          onTap: () => _pickReminderTime(context, settings.lessonReminderHour, settings.lessonReminderMinute),
                        ),
                      SettingsSwitchTile(
                        icon: Icons.local_fire_department_outlined,
                        label: l10n.streakReminder,
                        value: settings.streakReminder,
                        onChanged: (v) => ref.read(settingsProvider.notifier).setStreakReminder(v),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.sectionLanguageAppearance,
                    children: [
                      SettingsNavTile(
                        icon: Icons.translate,
                        label: l10n.appLanguage,
                        value: localeDisplayName(locale ?? Localizations.localeOf(context)),
                        onTap: () => _pickAppLanguage(context, ref, locale),
                      ),
                      SettingsNavTile(
                        icon: Icons.menu_book_outlined,
                        label: l10n.courseLanguage,
                        value: settings.courseLanguage,
                        onTap: () => _pickCourseLanguage(context, settings.courseLanguage),
                      ),
                      SettingsNavTile(
                        icon: Icons.dark_mode_outlined,
                        label: l10n.theme,
                        value: _themeLabel(l10n, themeMode),
                        onTap: () => _pickTheme(context, ref, themeMode),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.sectionSupport,
                    children: [
                      SettingsNavTile(icon: Icons.help_outline, label: l10n.helpFaq, onTap: _comingSoon),
                      SettingsNavTile(icon: Icons.mail_outline, label: l10n.contactUs, onTap: _comingSoon),
                      SettingsNavTile(icon: Icons.info_outline, label: l10n.aboutApp, value: l10n.appVersion(_appVersion), onTap: _comingSoon),
                    ],
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.border)),
                    onPressed: _confirmLogout,
                    child: Text(l10n.logout),
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

  String _formatTime(int hour, int minute) => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String _themeLabel(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
        ThemeMode.dark => l10n.themeDark,
        ThemeMode.light => l10n.themeLight,
        ThemeMode.system => l10n.themeSystem,
      };

  Future<void> _pickDailyGoal(BuildContext context, int current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _showOptionSheet<int>(
      context,
      title: l10n.dailyGoal,
      options: [for (final m in _dailyGoalOptions) (value: m, label: l10n.dailyGoalMinutes(m))],
      current: current,
    );
    if (picked != null) await ref.read(settingsProvider.notifier).setDailyGoal(picked);
  }

  Future<void> _pickLanguageLevel(BuildContext context, LanguageLevel current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _showOptionSheet<LanguageLevel>(
      context,
      title: l10n.languageLevel,
      options: [for (final lvl in LanguageLevel.values) (value: lvl, label: lvl.label)],
      current: current,
    );
    if (picked != null) await ref.read(settingsProvider.notifier).setLanguageLevel(picked);
  }

  Future<void> _pickCourseLanguage(BuildContext context, String current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _showOptionSheet<String>(
      context,
      title: l10n.courseLanguage,
      options: const [(value: 'Русский', label: 'Русский'), (value: 'English', label: 'English')],
      current: current,
    );
    if (picked != null) await ref.read(settingsProvider.notifier).setCourseLanguage(picked);
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _showOptionSheet<ThemeMode>(
      context,
      title: l10n.theme,
      options: [
        (value: ThemeMode.system, label: l10n.themeSystem),
        (value: ThemeMode.dark, label: l10n.themeDark),
        (value: ThemeMode.light, label: l10n.themeLight),
      ],
      current: current,
    );
    if (picked != null) await ref.read(themeModeProvider.notifier).setMode(picked);
  }

  Future<void> _pickAppLanguage(BuildContext context, WidgetRef ref, Locale? current) async {
    final l10n = AppLocalizations.of(context);
    final systemLocale = Localizations.localeOf(context);
    final picked = await _showOptionSheet<Locale?>(
      context,
      title: l10n.appLanguage,
      options: [
        (value: null, label: '${l10n.themeSystem} (${localeDisplayName(systemLocale)})'),
        for (final locale in AppLocalizations.supportedLocales) (value: locale, label: localeDisplayName(locale)),
      ],
      current: current,
    );
    if (picked != current) await ref.read(localeProvider.notifier).setLocale(picked);
  }

  Future<T?> _showOptionSheet<T>(
    BuildContext context, {
    required String title,
    required List<({T value, String label})> options,
    required T current,
  }) {
    final c = context.profileColors;
    return showModalBottomSheet<T>(
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
                child: Align(alignment: Alignment.centerLeft, child: Text(title, style: ProfileTypography.sectionTitle(sheetContext))),
              ),
              for (final option in options)
                ListTile(
                  title: Text(option.label, style: ProfileTypography.body(sheetContext)),
                  trailing: option.value == current ? Icon(Icons.check, color: c.accent) : null,
                  onTap: () => Navigator.of(sheetContext).pop(option.value),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickReminderTime(BuildContext context, int hour, int minute) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: hour, minute: minute));
    if (picked != null) await ref.read(settingsProvider.notifier).setLessonReminderTime(picked.hour, picked.minute);
  }
}
