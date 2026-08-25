import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/theme/theme_provider.dart';
import '../data/profile_repository.dart';
import 'profile_history.dart';

/// Mirrors ProfilePage.tsx — but only its real, already-backed parts: name/
/// email/phone/avatar editing and the genuinely-computed overall-progress
/// percentage + lesson history. The old page's social/streak/level/
/// achievements/ranking/weekly-activity sections are explicitly marked in
/// its own source as temporary demo data with no backing system — the
/// migration plan is explicit that fake data is not part of the functionality
/// being preserved, so none of it is ported here.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _initialized = false;

  bool _saving = false;
  String? _saveError;
  bool _saved = false;
  bool _avatarBusy = false;
  bool _idCopied = false;

  void _initFromUser(AppUser user) {
    if (_initialized) return;
    _initialized = true;
    _firstName.text = user.firstName;
    _lastName.text = user.lastName;
    _email.text = user.email;
    _phone.text = user.phone ?? '';
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveError = null;
      _saved = false;
    });
    try {
      final user = await ref.read(profileRepositoryProvider).updateProfile(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      await ref.read(authProvider.notifier).updateLocalUser(user);
      if (mounted) setState(() => _saved = true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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

  Future<void> _copyUserId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    setState(() => _idCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _idCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    final themeMode = ref.watch(themeModeProvider);
    if (user == null) return const SizedBox.shrink();
    _initFromUser(user);

    final history = ref.watch(profileHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/courses')),
        title: const Text('Профиль'),
        actions: [
          IconButton(
            tooltip: themeMode == ThemeMode.dark ? 'Светлая тема' : 'Тёмная тема',
            icon: Icon(themeMode == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AvatarHeader(user: user, busy: _avatarBusy, onPick: _pickAvatar, onDelete: _deleteAvatar),
          const SizedBox(height: 20),
          history.when(
            loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            error: (err, st) => Text('Не удалось загрузить прогресс: $err'),
            data: (data) => _OverallProgressCard(percent: data.overallProgressPercent),
          ),
          const SizedBox(height: 20),
          Text('История занятий', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          history.when(
            loading: () => const SizedBox.shrink(),
            error: (err, st) => const SizedBox.shrink(),
            data: (data) => data.rows.isEmpty
                ? const Text('Пока нет уроков.')
                : Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < data.rows.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _LessonHistoryTile(index: i, row: data.rows[i]),
                        ],
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Text('Настройки', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (user.isStaff)
                OutlinedButton(onPressed: () => context.go('/admin/courses'), child: const Text('Курсы (админ)')),
              if (user.isAdmin) OutlinedButton(onPressed: () => context.go('/admin'), child: const Text('Пользователи')),
              OutlinedButton(onPressed: () => ref.read(authProvider.notifier).logout(), child: const Text('Выйти')),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('ID пользователя'),
                  const SizedBox(width: 8),
                  Expanded(child: Text(user.id, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace'))),
                  TextButton(onPressed: () => _copyUserId(user.id), child: Text(_idCopied ? 'Скопировано' : 'Скопировать')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!user.canEditProfile)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text('Редактирование профиля отключено администратором — данные доступны только для просмотра.'),
            ),
          TextField(
            controller: _firstName,
            enabled: user.canEditProfile,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastName,
            enabled: user.canEditProfile,
            decoration: const InputDecoration(labelText: 'Фамилия'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            enabled: user.canEditProfile,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            enabled: user.canEditProfile,
            decoration: const InputDecoration(labelText: 'Телефон'),
          ),
          const SizedBox(height: 16),
          if (_saveError != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_saveError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_saved) const Padding(padding: EdgeInsets.only(bottom: 12), child: Text('Профиль сохранён', style: TextStyle(color: Colors.green))),
          if (user.canEditProfile)
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
            ),
        ],
      ),
    );
  }
}

class _AvatarHeader extends ConsumerWidget {
  const _AvatarHeader({required this.user, required this.busy, required this.onPick, required this.onDelete});

  final AppUser user;
  final bool busy;
  final VoidCallback onPick;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatarUrl = ref.read(apiClientProvider).assetUrl(user.avatarUrl);
    return Row(
      children: [
        Stack(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? Text(user.firstName.isNotEmpty ? user.firstName[0].toUpperCase() : '?') : null,
            ),
            if (busy) const Positioned.fill(child: Center(child: CircularProgressIndicator())),
          ],
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${user.firstName} ${user.lastName}'.trim(), style: Theme.of(context).textTheme.titleLarge),
              Text(user.email, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(onPressed: busy ? null : onPick, child: const Text('Сменить фото')),
                  if (user.avatarUrl != null) TextButton(onPressed: busy ? null : onDelete, child: const Text('Удалить')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OverallProgressCard extends StatelessWidget {
  const _OverallProgressCard({required this.percent});
  final int? percent;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(percent == null ? '—' : '$percent%', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(width: 12),
            const Expanded(child: Text('Общий прогресс по урокам')),
          ],
        ),
      ),
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
      title: Text('Урок ${index + 1}. ${row.title}'),
      subtitle: Text(
        summary == null
            ? 'Не начат'
            : 'Лучший результат: ${summary.bestScore}% · попыток: ${summary.attempts} · последняя: ${summary.lastScore}%',
      ),
    );
  }
}
