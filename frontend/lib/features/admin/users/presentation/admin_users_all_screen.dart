import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../data/admin_users_repository.dart';
import 'admin_users_screen.dart' show adminUsersListProvider;
import 'widgets/users_data_table.dart';

/// Full, searchable user list (§ admin users expanded list, 2026-09-01) —
/// reached by pushing from the compact /admin list's "Показать все" button,
/// so it stacks inside the same ShellRoute Navigator: the nav rail/bottom
/// bar stays mounted the whole time (requirement — "не убирая главную
/// навигацию"), and popping (system back or the explicit "Назад" button)
/// returns to exactly whatever screen was showing before, not a hardcoded
/// route. Opening a user card from here pushes too (unlike the compact
/// list's own `go`, left untouched), so its back arrow can pop back here
/// specifically instead of resetting to /admin — see the matching canPop
/// fix in AdminUserDetailScreen.
///
/// Reuses the exact same data source as the compact list
/// (adminUsersListProvider) — same cache, same invalidation on
/// block/create/reset actions elsewhere — so this is deliberately not a
/// second user-list system, just a different view over the one list.
class AdminUsersAllScreen extends ConsumerStatefulWidget {
  const AdminUsersAllScreen({super.key});

  @override
  ConsumerState<AdminUsersAllScreen> createState() => _AdminUsersAllScreenState();
}

enum _StatusFilter { all, active, blocked }

class _AdminUsersAllScreenState extends ConsumerState<AdminUsersAllScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _StatusFilter _statusFilter = _StatusFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUser> _filter(List<AdminUser> sorted) {
    var result = sorted;
    switch (_statusFilter) {
      case _StatusFilter.all:
        break;
      case _StatusFilter.active:
        result = result.where((u) => u.status == 'ACTIVE').toList();
      case _StatusFilter.blocked:
        result = result.where((u) => u.status != 'ACTIVE').toList();
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return result;
    return result.where((u) {
      final fullName = '${u.firstName} ${u.lastName}'.toLowerCase();
      return fullName.contains(q) || u.username.toLowerCase().contains(q) || u.id.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final users = ref.watch(adminUsersListProvider);
    final canPop = Navigator.of(context).canPop();
    void goBack() {
      if (canPop) {
        context.pop();
      } else {
        context.go('/admin');
      }
    }

    return BackGuard(
      fallbackPath: '/admin',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Все пользователи'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: goBack),
        ),
        body: users.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, st) => Center(child: Text('Не удалось загрузить список: $err')),
          data: (list) {
            final sorted = sortUsersByActivity(list);
            final filtered = _filter(sorted);
            return RefreshIndicator(
              onRefresh: () async => ref.invalidate(adminUsersListProvider),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      // Wider than the compact list's 780/900px cap (§ admin
                      // users expanded list follow-up, 2026-09-01) — this
                      // screen exists specifically to see everyone at once,
                      // so it should use more of a wide viewport before the
                      // table's own horizontal scrollbar kicks in.
                      constraints: const BoxConstraints(maxWidth: 1600),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: goBack,
                                icon: const Icon(Icons.arrow_back, size: 18),
                                label: const Text('Назад'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.text,
                                  side: BorderSide(color: c.border),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Всего: ${sorted.length}',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 520),
                                    child: TextField(
                                      controller: _searchController,
                                      decoration: InputDecoration(
                                        hintText: 'Поиск по имени, логину, email или ID',
                                        prefixIcon: const Icon(Icons.search),
                                        suffixIcon: _query.isEmpty
                                            ? null
                                            : IconButton(
                                                icon: const Icon(Icons.close),
                                                onPressed: () {
                                                  _searchController.clear();
                                                  setState(() => _query = '');
                                                },
                                              ),
                                        filled: true,
                                        fillColor: c.surface,
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                      ),
                                      onChanged: (v) => setState(() => _query = v),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      _StatusFilterChip(
                                        label: 'Все',
                                        selected: _statusFilter == _StatusFilter.all,
                                        onSelected: () => setState(() => _statusFilter = _StatusFilter.all),
                                      ),
                                      _StatusFilterChip(
                                        label: 'Активные',
                                        selected: _statusFilter == _StatusFilter.active,
                                        onSelected: () => setState(() => _statusFilter = _StatusFilter.active),
                                      ),
                                      _StatusFilterChip(
                                        label: 'Заблокированные',
                                        selected: _statusFilter == _StatusFilter.blocked,
                                        onSelected: () => setState(() => _statusFilter = _StatusFilter.blocked),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  if (sorted.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(child: Text('Пользователей пока нет', style: TextStyle(color: c.textMuted))),
                                    )
                                  else if (filtered.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 24),
                                      child: Center(child: Text('Ничего не найдено', style: TextStyle(color: c.textMuted))),
                                    )
                                  else
                                    UsersDataTable(users: filtered, onOpen: (u) => context.push('/admin/users/${u.id}')),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Mirrors StatusPill's visual language (soft-fill pill) for a tappable
/// filter chip, so the status filter reads as belonging to the same
/// «Активен»/«Заблокирован» vocabulary the ОНЛАЙН/СТАТУС columns already use.
class _StatusFilterChip extends StatelessWidget {
  const _StatusFilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: selected ? c.primary : c.textMuted,
      ),
      backgroundColor: c.surface,
      selectedColor: c.primarySoft,
      side: BorderSide(color: selected ? c.primarySoft : c.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}
