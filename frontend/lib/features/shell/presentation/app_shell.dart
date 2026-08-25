import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/presentation/profile_tokens.dart';

/// App chrome for the shell-routed top-level sections (home/courses/admin/
/// profile): a persistent icon rail on the left on wide viewports — the
/// layout from the reference design — or a bottom tab bar on narrow ones,
/// both built from the same nav item list so the two stay in sync.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  static const _wideBreakpoint = ProfileMetrics.wideBreakpoint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWide = MediaQuery.sizeOf(context).width >= _wideBreakpoint;
    final user = ref.watch(authProvider).value;

    if (!isWide) {
      return Scaffold(
        body: child,
        bottomNavigationBar: _BottomBar(currentPath: currentPath, user: user),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _NavRail(currentPath: currentPath, user: user),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.path});

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
}

const _navItems = [
  _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Главная', path: '/'),
  _NavItem(icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'Курсы', path: '/courses'),
  _NavItem(icon: Icons.edit_note_outlined, activeIcon: Icons.edit_note, label: 'Конструктор курсов', path: '/admin/courses'),
  _NavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'Пользователи', path: '/admin'),
  _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Профиль', path: '/profile'),
];

bool _visibleFor(_NavItem item, AppUser? user) {
  if (item.path == '/admin/courses') return user?.isStaff ?? false;
  if (item.path == '/admin') return user?.isAdmin ?? false;
  return true;
}

bool _isActive(_NavItem item, String currentPath) {
  if (item.path == '/') return currentPath == '/';
  return currentPath.startsWith(item.path);
}

class _NavRail extends ConsumerWidget {
  const _NavRail({required this.currentPath, required this.user});

  final String currentPath;
  final AppUser? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final items = _navItems.where((item) => _visibleFor(item, user)).toList();

    return Container(
      width: 88,
      color: c.primary,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              'Deutsch\nLernen',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13, height: 1.25),
            ),
            const SizedBox(height: 32),
            for (final item in items)
              _RailButton(
                icon: _isActive(item, currentPath) ? item.activeIcon : item.icon,
                tooltip: item.label,
                active: _isActive(item, currentPath),
                onTap: () => context.go(item.path),
              ),
            const Spacer(),
            _RailButton(
              icon: Icons.logout,
              tooltip: 'Выйти',
              active: false,
              onTap: () => _confirmLogout(context, ref),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Выйти из аккаунта?'),
      content: const Text('Вы сможете снова войти в любой момент.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Выйти')),
      ],
    ),
  );
  if (confirmed ?? false) {
    ref.read(authProvider.notifier).logout();
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.tooltip, required this.active, required this.onTap});

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: active ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Narrow-viewport counterpart to _NavRail — same items, same active/
/// inactive logic, laid out as a bottom tab bar per the mobile design spec
/// (active icon: accent in a soft accent circle; inactive: text-muted).
/// Logout isn't in the bar itself (no room for a 6th icon without labels) —
/// it stays reachable from the profile screen, same as on desktop.
class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.currentPath, required this.user});

  final String currentPath;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    final items = _navItems.where((item) => _visibleFor(item, user)).toList();

    return DecoratedBox(
      decoration: BoxDecoration(color: c.bg, border: Border(top: BorderSide(color: c.border))),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final item in items) _BottomBarButton(item: item, active: _isActive(item, currentPath)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({required this.item, required this.active});

  final _NavItem item;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.profileColors;
    return Tooltip(
      message: item.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go(item.path),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: active ? c.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(14)),
          child: Icon(active ? item.activeIcon : item.icon, color: active ? c.accent : c.textMuted, size: 22),
        ),
      ),
    );
  }
}
