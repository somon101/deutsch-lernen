import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/user.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../widgets/admin_feedback.dart';
import '../data/admin_users_repository.dart';

final adminUsersListProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) => ref.watch(adminUsersRepositoryProvider).listUsers());

/// "19.08.2026, 14:32" — mirrors src/lib/formatDate.ts's formatDateTime.
String _formatDateTime(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(local.day)}.${p2(local.month)}.${local.year}, ${p2(local.hour)}:${p2(local.minute)}';
}

/// Mirrors AdminUsersPage.tsx: the full user list (as a real table) + the
/// always-visible create-user form. «Онлайн» = активность за последние 5
/// минут; «Последний вход» = момент ввода пароля, не время нахождения на
/// сайте (same explanatory note as the original).
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
    );
  }
}

class _UsersTableCard extends StatefulWidget {
  const _UsersTableCard({required this.users});
  final List<AdminUser> users;

  @override
  State<_UsersTableCard> createState() => _UsersTableCardState();
}

class _UsersTableCardState extends State<_UsersTableCard> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.users;
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Пользователи', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.22, color: c.text)),
            const SizedBox(height: 8),
            Text(
              '«Онлайн» — пользователь пользовался платформой в последние 5 минут. «Последний вход» — когда он в '
              'последний раз вводил пароль (не показывает, сколько он потом оставался на сайте).',
              style: TextStyle(fontSize: 13, height: 1.5, color: c.textMuted),
            ),
            const SizedBox(height: 16),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: c.border.withValues(alpha: 0.6)),
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 10),
                child: DataTable(
                  headingRowHeight: 34,
                  dataRowMinHeight: 34,
                  dataRowMaxHeight: 40,
                  columnSpacing: 18,
                  horizontalMargin: 8,
                  dividerThickness: 0.6,
                  headingTextStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: c.textFaint, letterSpacing: 0.5),
                  dataTextStyle: TextStyle(fontSize: 14, color: c.text),
                  columns: const [
                    DataColumn(label: Text('ИМЯ')),
                    DataColumn(label: Text('ЛОГИН')),
                    DataColumn(label: Text('EMAIL')),
                    DataColumn(label: Text('РОЛЬ')),
                    DataColumn(label: Text('СТАТУС')),
                    DataColumn(label: Text('ОНЛАЙН')),
                    DataColumn(label: Text('ПОСЛЕДНИЙ ВХОД')),
                    DataColumn(label: Text('')),
                  ],
                  rows: [
                    for (final u in users)
                      DataRow(cells: [
                        DataCell(Text('${u.firstName} ${u.lastName}')),
                        DataCell(Text(u.username)),
                        DataCell(Text(u.email)),
                        DataCell(Text(u.role)),
                        DataCell(StatusPill(label: u.status == 'ACTIVE' ? 'Активен' : 'Заблокирован', active: u.status == 'ACTIVE')),
                        DataCell(StatusPill(label: u.online ? '● В сети' : 'Не в сети', active: u.online)),
                        DataCell(
                          u.lastLoginAt != null
                              ? Text(_formatDateTime(u.lastLoginAt!))
                              : Text('никогда', style: TextStyle(color: c.textFaint)),
                        ),
                        DataCell(_OpenButton(onPressed: () => context.go('/admin/users/${u.id}'))),
                      ]),
                  ],
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors .btn-secondary — surface bg, primary text, primary-soft border.
class _OpenButton extends StatelessWidget {
  const _OpenButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: c.primary,
        backgroundColor: c.surface,
        side: BorderSide(color: c.primarySoft, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      child: const Text('Открыть'),
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
  final _phone = TextEditingController();
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
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Создать пользователя', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.2, color: c.text)),
            const SizedBox(height: 16),
            _FieldRow(children: [
              _Field(label: 'Имя', controller: _firstName),
              _Field(label: 'Фамилия', controller: _lastName),
            ]),
            const SizedBox(height: 14),
            _FieldRow(children: [
              _Field(label: 'Email', controller: _email, keyboardType: TextInputType.emailAddress),
              _Field(label: 'Телефон', controller: _phone),
            ]),
            const SizedBox(height: 14),
            _FieldRow(children: [
              _Field(
                label: 'Логин',
                controller: _username,
                hint: 'Только латинские буквы. Регистр не важен: Ivan и ivan — один и тот же логин.',
              ),
              _Field(label: 'Первоначальный пароль', controller: _password),
            ]),
            const SizedBox(height: 14),
            _FieldRow(children: [
              _RoleField(value: _role, onChanged: (v) => setState(() => _role = v ?? UserRole.user)),
              const SizedBox.shrink(),
            ]),
            const SizedBox(height: 14),
            InkWell(
              onTap: () => setState(() => _canEditProfile = !_canEditProfile),
              child: Row(
                children: [
                  Checkbox(value: _canEditProfile, onChanged: (v) => setState(() => _canEditProfile = v ?? true)),
                  const SizedBox(width: 4),
                  Text('Пользователь может редактировать свой профиль', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(color: c.dangerSoft, borderRadius: BorderRadius.circular(14)),
                child: Text(_error!, style: TextStyle(fontSize: 14.5, color: c.danger)),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Создаём…' : 'Создать пользователя')),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors .auth-form-grid — 2 equal columns, 14px gap.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: children[0]),
        const SizedBox(width: 14),
        Expanded(child: children[1]),
      ],
    );
  }
}

/// Mirrors .auth-field — label above input, optional hint below.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.hint, this.keyboardType});
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
        Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textMuted)),
        const SizedBox(height: 6),
        TextField(controller: controller, keyboardType: keyboardType, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
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
        Text('Роль', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.textMuted)),
        const SizedBox(height: 6),
        DropdownButtonFormField<UserRole>(
          initialValue: value,
          decoration: const InputDecoration(),
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
          items: const [
            DropdownMenuItem(value: UserRole.user, child: Text('USER — ученик')),
            DropdownMenuItem(value: UserRole.teacher, child: Text('TEACHER — преподаватель')),
            DropdownMenuItem(value: UserRole.admin, child: Text('ADMIN — администратор')),
          ],
          onChanged: onChanged,
        ),
      ],
    );
  }
}
