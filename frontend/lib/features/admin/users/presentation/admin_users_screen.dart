import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/user.dart';
import '../../widgets/admin_feedback.dart';
import '../data/admin_users_repository.dart';

final adminUsersListProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) => ref.watch(adminUsersRepositoryProvider).listUsers());

/// Mirrors AdminUsersPage.tsx: the full user list + create-user form.
/// «Онлайн» = активность за последние 5 минут; «Последний вход» = момент
/// ввода пароля, не время нахождения на сайте (same explanatory note as
/// the original).
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Не удалось загрузить список: $err')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersListProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _CreateUserCard(),
              const SizedBox(height: 20),
              Text('Все пользователи (${list.length})', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              const Text(
                '«Онлайн» — пользователь пользовался платформой в последние 5 минут. «Последний вход» — когда он в последний раз вводил пароль.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              for (final u in list) _UserRow(user: u),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});
  final AdminUser user;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => context.go('/admin/users/${user.id}'),
        title: Text('${user.firstName} ${user.lastName}'),
        subtitle: Text('@${user.username} · ${user.email} · ${_roleLabel(user.role)}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, size: 10, color: user.online ? Colors.green : Colors.grey),
                const SizedBox(width: 4),
                Text(user.online ? 'В сети' : 'Не в сети', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (user.status == 'BLOCKED')
              Text('Заблокирован', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) => switch (role) {
        'ADMIN' => 'администратор',
        'TEACHER' => 'преподаватель',
        _ => 'ученик',
      };
}

class _CreateUserCard extends ConsumerStatefulWidget {
  const _CreateUserCard();

  @override
  ConsumerState<_CreateUserCard> createState() => _CreateUserCardState();
}

class _CreateUserCardState extends ConsumerState<_CreateUserCard> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.user;
  bool _canEditProfile = true;
  bool _busy = false;
  String? _error;
  bool _expanded = false;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _phone.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminUsersRepositoryProvider).createUser(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            role: _role,
            canEditProfile: _canEditProfile,
          );
      _firstName.clear();
      _lastName.clear();
      _email.clear();
      _phone.clear();
      _username.clear();
      _password.clear();
      setState(() {
        _role = UserRole.user;
        _canEditProfile = true;
      });
      ref.invalidate(adminUsersListProvider);
      if (mounted) showSuccessSnack(context, 'Пользователь создан');
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось создать пользователя'));
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
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Expanded(child: Text('Новый пользователь', style: Theme.of(context).textTheme.titleMedium)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 12),
              TextField(controller: _firstName, decoration: const InputDecoration(labelText: 'Имя')),
              const SizedBox(height: 8),
              TextField(controller: _lastName, decoration: const InputDecoration(labelText: 'Фамилия')),
              const SizedBox(height: 8),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Телефон (необязательно)')),
              const SizedBox(height: 8),
              TextField(
                controller: _username,
                decoration: const InputDecoration(
                  labelText: 'Логин',
                  helperText: 'Только латинские буквы. Регистр не важен: Ivan и ivan — один и тот же логин.',
                ),
              ),
              const SizedBox(height: 8),
              TextField(controller: _password, decoration: const InputDecoration(labelText: 'Первоначальный пароль (мин. 6 символов)')),
              const SizedBox(height: 8),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Роль'),
                items: const [
                  DropdownMenuItem(value: UserRole.user, child: Text('USER — ученик')),
                  DropdownMenuItem(value: UserRole.teacher, child: Text('TEACHER — преподаватель')),
                  DropdownMenuItem(value: UserRole.admin, child: Text('ADMIN — администратор')),
                ],
                onChanged: (v) => setState(() => _role = v ?? UserRole.user),
              ),
              CheckboxListTile(
                value: _canEditProfile,
                onChanged: (v) => setState(() => _canEditProfile = v ?? true),
                title: const Text('Пользователь может редактировать свой профиль'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
              ),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Создаём…' : 'Создать пользователя')),
            ],
          ],
        ),
      ),
    );
  }
}
