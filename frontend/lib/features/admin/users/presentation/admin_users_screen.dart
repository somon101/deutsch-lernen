import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/user.dart';
import '../../../../core/cache/cached_json.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../widgets/admin_feedback.dart';
import '../data/admin_users_repository.dart';
import 'widgets/users_data_table.dart';

/// Cached (caching plan, 2026-08-29 — extended to admin/profile screens):
/// shows the last-known list instantly, then silently swaps in fresh data
/// only if something actually changed. A block/create/reset action still
/// calls ref.invalidate(adminUsersListProvider) same as before — the only
/// visible difference is the stream briefly re-yields the (now stale)
/// cached list before the fresh one arrives, rather than a blank loading
/// spinner.
final adminUsersListProvider = StreamProvider.autoDispose<List<AdminUser>>((ref) async* {
  final repo = ref.watch(adminUsersRepositoryProvider);
  await for (final raw in cachedJsonStream(
    key: 'admin_users_list',
    fetchFresh: () async => {'users': await repo.listUsersRaw()},
  )) {
    yield (raw['users'] as List<dynamic>).map((u) => AdminUser.fromJson(u as Map<String, dynamic>)).toList();
  }
});

/// Mirrors AdminUsersPage.tsx: the full user list (as a real table) + the
/// always-visible create-user form. «Онлайн» = активность за последние 5
/// минут; «Последний вход» = момент ввода пароля, не время нахождения на
/// сайте (same explanatory note as the original).
class AdminUsersScreen extends ConsumerWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersListProvider);

    return BackGuard(
      fallbackPath: '/',
      child: Scaffold(
      appBar: AppBar(
        title: const Text('Пользователи'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) =>
            Center(child: Text('Не удалось загрузить список: $err')),
        data: (list) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersListProvider),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + bottomBarClearance(context),
            ),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: Column(
                    children: [
                      _UsersTableCard(users: list),
                      const SizedBox(height: 20),
                      const _CreateUserCard(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

/// Top-10-by-activity slice of the table, with a link to the full,
/// searchable list (§ admin users expanded list, 2026-09-01).
const _compactLimit = 10;

class _UsersTableCard extends StatelessWidget {
  const _UsersTableCard({required this.users});
  final List<AdminUser> users;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sorted = sortUsersByActivity(users);
    final visible = sorted.take(_compactLimit).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Пользователи',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.22,
                      color: c.text,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => context.push('/admin/users/all'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.primary,
                    side: BorderSide(color: c.primarySoft, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  child: Text('Показать все (${sorted.length})'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '«Онлайн» — пользователь пользовался платформой в последние 5 минут. «Последний вход» — когда он в '
              'последний раз вводил пароль (не показывает, сколько он потом оставался на сайте). Показаны первые '
              '$_compactLimit пользователей по активности — сначала те, кто сейчас в сети.',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            UsersDataTable(users: visible, onOpen: (u) => context.go('/admin/users/${u.id}')),
          ],
        ),
      ),
    );
  }
}

/// Mirrors the second .profile-card on AdminUsersPage.tsx — always-visible
/// (not collapsible) 2-column create-user form.
class _CreateUserCard extends ConsumerStatefulWidget {
  const _CreateUserCard();

  @override
  ConsumerState<_CreateUserCard> createState() => _CreateUserCardState();
}

class _CreateUserCardState extends ConsumerState<_CreateUserCard> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.user;
  bool _canEditProfile = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
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
      await ref
          .read(adminUsersRepositoryProvider)
          .createUser(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            username: _username.text.trim(),
            password: _password.text,
            role: _role,
            canEditProfile: _canEditProfile,
          );
      _firstName.clear();
      _lastName.clear();
      _email.clear();
      _username.clear();
      _password.clear();
      setState(() {
        _role = UserRole.user;
        _canEditProfile = true;
      });
      ref.invalidate(adminUsersListProvider);
      if (mounted) showSuccessSnack(context, 'Пользователь создан');
    } catch (e) {
      setState(
        () => _error = adminErrorMessage(e, 'Не удалось создать пользователя'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Создать пользователя',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: c.text,
              ),
            ),
            const SizedBox(height: 16),
            _FieldRow(
              children: [
                _Field(label: 'Имя', controller: _firstName),
                _Field(label: 'Фамилия', controller: _lastName),
              ],
            ),
            const SizedBox(height: 14),
            _FieldRow(
              children: [
                _Field(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 14),
            _FieldRow(
              children: [
                _Field(
                  label: 'Логин',
                  controller: _username,
                  hint: 'Только латинские буквы. Регистр не важен: Ivan и ivan — один и тот же логин.',
                ),
                _Field(label: 'Первоначальный пароль', controller: _password),
              ],
            ),
            const SizedBox(height: 14),
            _FieldRow(
              children: [
                _RoleField(
                  value: _role,
                  onChanged: (v) => setState(() => _role = v ?? UserRole.user),
                ),
                const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _canEditProfile = !_canEditProfile),
              child: Row(
                children: [
                  Checkbox(
                    value: _canEditProfile,
                    onChanged: (v) =>
                        setState(() => _canEditProfile = v ?? true),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Пользователь может редактировать свой профиль',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 14.5, color: c.danger),
                ),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: Text(_busy ? 'Создаём…' : 'Создать пользователя'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors .auth-form-grid — 2 equal columns, 14px gap on wide layouts.
/// Below 480px a column this narrow (plus the card's 28px padding) doesn't
/// leave enough room for a label + input + hint without clipping, so it
/// stacks to one column instead of forcing the 2-column grid everywhere.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [children[0], const SizedBox(height: 14), children[1]],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 14),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

/// Mirrors .auth-field — label above input, optional hint below.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
  });
  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c.text,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint!, style: TextStyle(fontSize: 12, color: c.textFaint)),
        ],
      ],
    );
  }
}

class _RoleField extends StatelessWidget {
  const _RoleField({required this.value, required this.onChanged});
  final UserRole value;
  final ValueChanged<UserRole?> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Роль',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: c.textMuted,
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<UserRole>(
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c.text,
          ),
          items: const [
            DropdownMenuItem(
              value: UserRole.user,
              child: Text('USER — ученик'),
            ),
            DropdownMenuItem(
              value: UserRole.teacher,
              child: Text('TEACHER — преподаватель'),
            ),
            DropdownMenuItem(
              value: UserRole.admin,
              child: Text('ADMIN — администратор'),
            ),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
