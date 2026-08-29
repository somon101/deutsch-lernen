import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/auth/auth_state.dart';
import '../../../../core/auth/user.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/status_pill.dart';
import '../../../profile/data/profile_repository.dart';
import '../../widgets/admin_feedback.dart';
import '../data/admin_users_repository.dart';
import 'admin_users_screen.dart';

class _DetailData {
  const _DetailData({
    required this.user,
    required this.progress,
    required this.logins,
    required this.lessonTitles,
  });
  final AdminUser user;
  final List<LessonProgressSummary> progress;
  final List<LoginEventRow> logins;
  final Map<String, String> lessonTitles;
}

final _detailProvider = FutureProvider.autoDispose.family<_DetailData, String>((
  ref,
  userId,
) async {
  final repo = ref.watch(adminUsersRepositoryProvider);
  final user = await repo.getUser(userId);
  final progress = await repo.userProgress(userId);
  final logins = await repo.loginHistory(userId);
  final legacyLessons = await ref
      .watch(profileRepositoryProvider)
      .fetchLegacyLessons();
  return _DetailData(
    user: user,
    progress: progress,
    logins: logins,
    lessonTitles: {for (final l in legacyLessons) l.lessonId: l.title},
  );
});

/// "19.08.2026, 14:32" — mirrors src/lib/formatDate.ts's formatDateTime.
String _formatDateTime(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(local.day)}.${p2(local.month)}.${local.year}, ${p2(local.hour)}:${p2(local.minute)}';
}

/// Mirrors AdminUserDetailPage.tsx. The avatar photo header is a deliberate
/// addition beyond the old page (which shows no photo at all) — confirmed
/// with the user.
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/admin'),
        ),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Не удалось загрузить: $err')),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: Column(
                  children: [
                    _ProfileCard(userId: userId, user: d.user, isSelf: isSelf),
                    const SizedBox(height: 20),
                    _ResetPasswordCard(userId: userId),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'Прогресс по урокам',
                      child: _ProgressList(data: d),
                    ),
                    const SizedBox(height: 20),
                    _SectionCard(
                      title: 'История входов',
                      subtitle: 'Каждая запись — отдельный момент ввода пароля, не время нахождения на сайте.',
                      child: _LoginHistoryList(logins: d.logins),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mirrors .profile-card — background/radius/shadow/padding-28.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: c.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(fontSize: 13, color: c.textMuted),
              ),
            ],
            const SizedBox(height: 16),
            child,
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
    final c = context.colors;
    final rows = data.lessonTitles.entries.toList();
    if (rows.isEmpty) {
      return Text('Уроки не найдены.', style: TextStyle(color: c.textMuted));
    }
    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Builder(
            builder: (context) {
              final entry = rows[i];
              LessonProgressSummary? summary;
              for (final p in data.progress) {
                if (p.lessonId == entry.key) {
                  summary = p;
                  break;
                }
              }
              return _ProgressRow(
                title: 'Урок ${i + 1}. ${entry.value}',
                stats: summary == null
                    ? 'Не начат'
                    : 'Лучший результат: ${summary.bestScore}% · попыток: ${summary.attempts} · последняя: ${summary.lastScore}%',
                muted: summary == null,
              );
            },
          ),
        ],
      ],
    );
  }
}

class _LoginHistoryList extends StatelessWidget {
  const _LoginHistoryList({required this.logins});
  final List<LoginEventRow> logins;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (logins.isEmpty) {
      return Text(
        'Ещё ни разу не входил(а).',
        style: TextStyle(color: c.textFaint),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < logins.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          _ProgressRow(title: _formatDateTime(logins[i].createdAt)),
        ],
      ],
    );
  }
}

/// Mirrors .progress-lesson-row — bg=--color-bg, radius-md, 14/16 padding.
class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.title, this.stats, this.muted = false});
  final String title;
  final String? stats;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: c.text,
            ),
          ),
          if (stats != null)
            Text(
              stats!,
              style: TextStyle(
                fontSize: 13.5,
                color: muted ? c.textFaint : c.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}

/// Header card: avatar + name/username, online status, last login/active,
/// editable fields, block/activate + save row. Mirrors AdminUserDetailPage's
/// first .profile-card, plus a read-only avatar (new — see class doc above).
class _ProfileCard extends ConsumerStatefulWidget {
  const _ProfileCard({
    required this.userId,
    required this.user,
    required this.isSelf,
  });
  final String userId;
  final AdminUser user;
  final bool isSelf;

  @override
  ConsumerState<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends ConsumerState<_ProfileCard> {
  late final _firstName = TextEditingController(text: widget.user.firstName);
  late final _lastName = TextEditingController(text: widget.user.lastName);
  late final _email = TextEditingController(text: widget.user.email);
  late final _phone = TextEditingController(text: widget.user.phone ?? '');
  late final _username = TextEditingController(text: widget.user.username);
  late UserRole _role = _roleFromWire(widget.user.role);
  late bool _canEditProfile = widget.user.canEditProfile;
  bool _saving = false;
  bool _togglingStatus = false;
  String? _error;

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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminUsersRepositoryProvider)
          .updateUser(
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
      if (mounted) showSuccessSnack(context, 'Сохранено');
    } catch (e) {
      setState(
        () => _error = adminErrorMessage(e, 'Не удалось сохранить изменения'),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleStatus() async {
    setState(() {
      _togglingStatus = true;
      _error = null;
    });
    try {
      final next = widget.user.status == 'ACTIVE' ? 'BLOCKED' : 'ACTIVE';
      await ref
          .read(adminUsersRepositoryProvider)
          .updateUser(widget.userId, status: next);
      ref.invalidate(_detailProvider(widget.userId));
      ref.invalidate(adminUsersListProvider);
    } catch (e) {
      setState(
        () => _error = adminErrorMessage(e, 'Не удалось изменить статус'),
      );
    } finally {
      if (mounted) setState(() => _togglingStatus = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final u = widget.user;
    final avatarUrl = ref.read(apiClientProvider).assetUrl(u.avatarUrl);
    final initials =
        ((u.firstName.isNotEmpty ? u.firstName[0] : '') +
                (u.lastName.isNotEmpty ? u.lastName[0] : ''))
            .toUpperCase();
    final active = u.status == 'ACTIVE';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: c.primarySoft,
                  backgroundImage: avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl.isEmpty
                      ? Text(
                          initials,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: c.primaryDark,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${u.firstName} ${u.lastName}',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.22,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${u.username}',
                        style: TextStyle(fontSize: 15.5, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 6,
                children: [
                  StatusPill(
                    label: u.online ? '● В сети сейчас' : 'Не в сети',
                    active: u.online,
                  ),
                  Text(
                    '— пользовался платформой в последние 5 минут (учитывается любое действие, не только вход)',
                    style: TextStyle(fontSize: 12.5, color: c.textFaint),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 15.5,
                  color: c.textMuted,
                  height: 1.5,
                ),
                children: [
                  const TextSpan(text: 'Последний вход: '),
                  TextSpan(
                    text: u.lastLoginAt != null
                        ? _formatDateTime(u.lastLoginAt!)
                        : 'никогда не входил(а)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              'момент ввода пароля — не показывает, сколько потом человек оставался на сайте',
              style: TextStyle(fontSize: 12.5, color: c.textFaint),
            ),
            if (u.lastActiveAt != null) ...[
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 15.5,
                    color: c.textMuted,
                    height: 1.5,
                  ),
                  children: [
                    const TextSpan(text: 'Последняя активность: '),
                    TextSpan(
                      text: _formatDateTime(u.lastActiveAt!),
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'последний раз, когда человек что-то делал на платформе (не только вход) — по этому определяется «в сети сейчас»',
                style: TextStyle(fontSize: 12.5, color: c.textFaint),
              ),
            ],
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
                _Field(label: 'Email', controller: _email),
                _Field(label: 'Телефон', controller: _phone),
              ],
            ),
            const SizedBox(height: 14),
            _FieldRow(
              children: [
                _Field(label: 'Логин', controller: _username),
                _RoleCodeField(
                  value: _role,
                  enabled: !widget.isSelf,
                  onChanged: (v) => setState(() => _role = v ?? _role),
                ),
              ],
            ),
            if (widget.isSelf) ...[
              const SizedBox(height: 12),
              Text(
                'Это ваша учётная запись — снять с себя роль администратора или заблокировать себя нельзя.',
                style: TextStyle(fontSize: 13.5, color: c.textMuted),
              ),
            ],
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
                  Text(
                    'Пользователь может редактировать свой профиль',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: c.text,
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
            Row(
              children: [
                OutlinedButton(
                  onPressed: widget.isSelf || _togglingStatus
                      ? null
                      : _toggleStatus,
                  style: active
                      ? OutlinedButton.styleFrom(
                          foregroundColor: c.primary,
                          side: BorderSide(color: c.primarySoft, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 13,
                          ),
                        )
                      : OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: c.primary,
                          side: BorderSide.none,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 13,
                          ),
                        ),
                  child: Text(active ? 'Заблокировать' : 'Активировать'),
                ),
                const Spacer(),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Сохраняем…' : 'Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
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
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref
          .read(adminUsersRepositoryProvider)
          .resetPassword(widget.userId, _password.text);
      _password.clear();
      setState(() {
        _message = 'Пароль обновлён';
        _ok = true;
      });
    } catch (e) {
      setState(() {
        _message = adminErrorMessage(e, 'Не удалось сбросить пароль');
        _ok = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return _SectionCard(
      title: 'Сброс пароля',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(label: 'Новый пароль', controller: _password),
          if (_message != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: _ok ? c.successSoft : c.dangerSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _message!,
                style: TextStyle(
                  fontSize: 14.5,
                  color: _ok ? c.success : c.danger,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _busy ? null : _submit,
            style: OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              backgroundColor: c.surface,
              side: BorderSide(color: c.primarySoft, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 13),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('Сбросить пароль'),
          ),
        ],
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

/// Mirrors .auth-field — label above input.
class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});
  final String label;
  final TextEditingController controller;

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
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c.text,
          ),
        ),
      ],
    );
  }
}

/// Role select showing the raw code (USER/TEACHER/ADMIN) — matches
/// AdminUserDetailPage.tsx's <option> labels exactly (unlike the create-user
/// form, which uses descriptive labels).
class _RoleCodeField extends StatelessWidget {
  const _RoleCodeField({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });
  final UserRole value;
  final bool enabled;
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
          decoration: const InputDecoration(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: c.text,
          ),
          items: const [
            DropdownMenuItem(value: UserRole.user, child: Text('USER')),
            DropdownMenuItem(value: UserRole.teacher, child: Text('TEACHER')),
            DropdownMenuItem(value: UserRole.admin, child: Text('ADMIN')),
          ],
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }
}
