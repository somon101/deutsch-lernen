import 'package:flutter/material.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../../../core/widgets/status_pill.dart';
import '../../data/admin_users_repository.dart';

/// "19.08.2026, 14:32" — mirrors src/lib/formatDate.ts's formatDateTime.
String _formatDateTime(String iso) {
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;
  final local = dt.toLocal();
  String p2(int n) => n.toString().padLeft(2, '0');
  return '${p2(local.day)}.${p2(local.month)}.${local.year}, ${p2(local.hour)}:${p2(local.minute)}';
}

/// The user table itself (columns + rows), extracted out of the compact
/// AdminUsersScreen (§ admin users expanded list, 2026-09-01) so the new
/// expanded "Показать все" list can reuse it verbatim instead of
/// duplicating the row markup — [onOpen] is the only behavioral knob, since
/// the compact list still needs `context.go(...)` (unchanged) while the
/// expanded list needs `context.push(...)` (§ back-navigation requirement).
class UsersDataTable extends StatefulWidget {
  const UsersDataTable({super.key, required this.users, required this.onOpen});

  final List<AdminUser> users;
  final ValueChanged<AdminUser> onOpen;

  @override
  State<UsersDataTable> createState() => _UsersDataTableState();
}

class _UsersDataTableState extends State<UsersDataTable> {
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
    return Theme(
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
                DataRow(
                  cells: [
                    DataCell(Text('${u.firstName} ${u.lastName}')),
                    DataCell(Text(u.username)),
                    DataCell(Text(u.email)),
                    DataCell(Text(u.role)),
                    DataCell(StatusPill(label: u.status == 'ACTIVE' ? 'Активен' : 'Заблокирован', active: u.status == 'ACTIVE')),
                    DataCell(StatusPill(label: u.online ? '● В сети' : 'Не в сети', active: u.online)),
                    DataCell(
                      u.lastLoginAt != null ? Text(_formatDateTime(u.lastLoginAt!)) : Text('никогда', style: TextStyle(color: c.textFaint)),
                    ),
                    DataCell(_OpenButton(onPressed: () => widget.onOpen(u))),
                  ],
                ),
            ],
          ),
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
