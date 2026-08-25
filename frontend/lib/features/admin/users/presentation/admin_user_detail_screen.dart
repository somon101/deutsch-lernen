import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/auth_state.dart';
import '../../../../core/auth/user.dart';
import '../../../profile/data/profile_repository.dart';
import '../../widgets/admin_feedback.dart';
import '../data/admin_users_repository.dart';
import 'admin_users_screen.dart';

class _DetailData {
  const _DetailData({required this.user, required this.progress, required this.logins, required this.lessonTitles});
  final AdminUser user;
  final List<LessonProgressSummary> progress;
  final List<LoginEventRow> logins;
  final Map<String, String> lessonTitles;
}

final _detailProvider = FutureProvider.autoDispose.family<_DetailData, String>((ref, userId) async {
  final repo = ref.watch(adminUsersRepositoryProvider);
  final user = await repo.getUser(userId);
  final progress = await repo.userProgress(userId);
  final logins = await repo.loginHistory(userId);
  final legacyLessons = await ref.watch(profileRepositoryProvider).fetchLegacyLessons();
  return _DetailData(
    user: user,
    progress: progress,
    logins: logins,
    lessonTitles: {for (final l in legacyLessons) l.lessonId: l.title},
  );
});

String _formatDate(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(local.day)}.${p2(local.month)}.${local.year} ${p2(local.hour)}:${p2(local.minute)}';
}

/// Mirrors AdminUserDetailPage.tsx.
class AdminUserDetailScreen extends ConsumerWidget {
  const AdminUserDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(_detailProvider(userId));
    final me = ref.watch(authProvider).value;
    final isSelf = me?.id == userId;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователь'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/admin')),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Не удалось загрузить: $err')),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('${d.user.firstName} ${d.user.lastName}', style: Theme.of(context).textTheme.headlineSmall),
            Text('@${d.user.username}', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.circle, size: 10, color: d.user.online ? Colors.green : Colors.grey),
                const SizedBox(width: 6),
                Text(d.user.online ? 'В сети' : 'Не в сети'),
              ],
            ),
            Text(
              d.user.lastLoginAt != null ? 'Последний вход: ${_formatDate(d.user.lastLoginAt!)}' : 'Никогда не входил(а)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (isSelf)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Это ваша учётная запись — снять с себя роль администратора или заблокировать себя нельзя.',
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            const SizedBox(height: 20),
            _EditForm(user: d.user, userId: userId, isSelf: isSelf),
            const SizedBox(height: 12),
            _StatusToggle(user: d.user, userId: userId, isSelf: isSelf),
            const SizedBox(height: 20),
            _ResetPasswordCard(userId: userId),
            const SizedBox(height: 20),
            Text('Прогресс по урокам', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _ProgressList(data: d),
            const SizedBox(height: 20),
            Text('История входов', style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'Каждая запись — отдельный момент ввода пароля, не время нахождения на сайте.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            if (d.logins.isEmpty) const Text('Ещё ни разу не входил(а).'),
            for (final l in d.logins) Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(_formatDate(l.createdAt))),
          ],
        ),
      ),
    );
  }
}

class _ProgressList extends StatelessWidget {
  const _ProgressList({required this.data});
  final _DetailData data;

  @override
  Widget build(BuildContext context) {
    final rows = data.lessonTitles.entries.toList();
    if (rows.isEmpty) return const Text('Уроки не найдены.');
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Builder(builder: (context) {
              final entry = rows[i];
              LessonProgressSummary? summary;
              for (final p in data.progress) {
                if (p.lessonId == entry.key) {
                  summary = p;
                  break;
                }
              }
              return ListTile(
                title: Text('Урок ${i + 1}. ${entry.value}'),
                subtitle: Text(
                  summary == null
                      ? 'Не начат'
                      : 'Лучший результат: ${summary.bestScore}% · попыток: ${summary.attempts} · последняя: ${summary.lastScore}%',
                ),
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _EditForm extends ConsumerStatefulWidget {
  const _EditForm({required this.user, required this.userId, required this.isSelf});
  final AdminUser user;
  final String userId;
  final bool isSelf;

  @override
  ConsumerState<_EditForm> createState() => _EditFormState();
}

class _EditFormState extends ConsumerState<_EditForm> {
  late final _firstName = TextEditingController(text: widget.user.firstName);
  late final _lastName = TextEditingController(text: widget.user.lastName);
  late final _email = TextEditingController(text: widget.user.email);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _username = TextEditingController(text: widget.user.username);
  late UserRole _role = _roleFromWire(widget.user.role);
  late bool _canEditProfile = widget.user.canEditProfile;
  bool _busy = false;

  UserRole _roleFromWire(String r) => switch (r) {
        'ADMIN' => UserRole.admin,
        'TEACHER' => UserRole.teacher,
        _ => UserRole.user,
      };

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref.read(adminUsersRepositoryProvider).updateUser(
            widget.userId,
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            username: _username.text.trim(),
            role: _role,
            canEditProfile: _canEditProfile,
          );
      ref.invalidate(adminUsersListProvider);
      if (mounted) showSuccessSnack(context);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить изменения');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(controller: _firstName, decoration: const InputDecoration(labelText: 'Имя')),
            const SizedBox(height: 8),
            TextField(controller: _lastName, decoration: const InputDecoration(labelText: 'Фамилия')),
            const SizedBox(height: 8),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Телефон')),
            const SizedBox(height: 8),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Логин')),
            const SizedBox(height: 8),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Роль'),
              items: const [
                DropdownMenuItem(value: UserRole.user, child: Text('USER — ученик')),
                DropdownMenuItem(value: UserRole.teacher, child: Text('TEACHER — преподаватель')),
                DropdownMenuItem(value: UserRole.admin, child: Text('ADMIN — администратор')),
              ],
              onChanged: widget.isSelf ? null : (v) => setState(() => _role = v ?? UserRole.user),
            ),
            CheckboxListTile(
              value: _canEditProfile,
              onChanged: (v) => setState(() => _canEditProfile = v ?? true),
              title: const Text('Может редактировать свой профиль'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Сохраняем…' : 'Сохранить')),
          ],
        ),
      ),
    );
  }
}

class _StatusToggle extends ConsumerStatefulWidget {
  const _StatusToggle({required this.user, required this.userId, required this.isSelf});
  final AdminUser user;
  final String userId;
  final bool isSelf;

  @override
  ConsumerState<_StatusToggle> createState() => _StatusToggleState();
}

class _StatusToggleState extends ConsumerState<_StatusToggle> {
  bool _busy = false;

  Future<void> _toggle() async {
    setState(() => _busy = true);
    try {
      final next = widget.user.status == 'BLOCKED' ? 'ACTIVE' : 'BLOCKED';
      await ref.read(adminUsersRepositoryProvider).updateUser(widget.userId, status: next);
      ref.invalidate(_detailProvider(widget.userId));
      ref.invalidate(adminUsersListProvider);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось изменить статус');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.user.status == 'BLOCKED';
    return OutlinedButton(
      onPressed: widget.isSelf || _busy ? null : _toggle,
      style: OutlinedButton.styleFrom(foregroundColor: blocked ? Colors.green : Theme.of(context).colorScheme.error),
      child: Text(blocked ? 'Активировать' : 'Заблокировать'),
    );
  }
}

class _ResetPasswordCard extends ConsumerStatefulWidget {
  const _ResetPasswordCard({required this.userId});
  final String userId;

  @override
  ConsumerState<_ResetPasswordCard> createState() => _ResetPasswordCardState();
}

class _ResetPasswordCardState extends ConsumerState<_ResetPasswordCard> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _done = false;
    });
    try {
      await ref.read(adminUsersRepositoryProvider).resetPassword(widget.userId, _password.text);
      _password.clear();
      setState(() => _done = true);
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось сбросить пароль'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Сброс пароля', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(controller: _password, decoration: const InputDecoration(labelText: 'Новый пароль (мин. 6 символов)')),
            const SizedBox(height: 8),
            if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (_done) const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Пароль обновлён', style: TextStyle(color: Colors.green))),
            ElevatedButton(onPressed: _busy ? null : _submit, child: const Text('Сбросить пароль')),
          ],
        ),
      ),
    );
  }
}
