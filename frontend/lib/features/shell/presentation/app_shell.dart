import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/presentation/profile_tokens.dart';
import 'graph_sidebar_controls.dart';

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

    // Reference layout (§ shell card treatment, 2026-09-02): the page itself
    // is the soft lavender ground, the purple rail hugs the left edge with
    // its inner corners rounded, and the routed screen floats on top as one
    // big rounded card with a little breathing room around it.
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(
        children: [
          _NavRail(currentPath: currentPath, user: user),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_shellGap, _shellGap, _shellGap, _shellGap),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_shellRadius),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Gap of page-ground left visible around the floating content card, and the
/// radius of that card — the rail reuses the same radius on its inner edge so
/// the two curves read as one shape (§ shell card treatment, 2026-09-02).
const _shellGap = 10.0;
const _shellRadius = 22.0;

class _NavItem {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.path});

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String path;
}

const _navItems = [
  _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Главная', path: '/'),
  _NavItem(icon: Icons.edit_note_outlined, activeIcon: Icons.edit_note, label: 'Конструктор курсов', path: '/admin/courses'),
  _NavItem(icon: Icons.people_outline, activeIcon: Icons.people, label: 'Пользователи', path: '/admin'),
  _NavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Профиль', path: '/profile'),
  _NavItem(icon: Icons.emoji_events_outlined, activeIcon: Icons.emoji_events, label: 'Рейтинг', path: '/leaderboard'),
  _NavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Настройки', path: '/settings'),
];

bool _visibleFor(_NavItem item, AppUser? user) {
  if (item.path == '/admin/courses') return user?.isStaff ?? false;
  if (item.path == '/admin') return user?.isAdmin ?? false;
  return true;
}

/// Paths that belong to a nav item's section without starting with that
/// item's own path — the course builder's editor screens live under
/// /admin/builder and /admin/lessons but are part of "Конструктор курсов"
/// (§ builder full-width layout, 2026-09-02).
const _sectionAliases = <String, List<String>>{
  '/admin/courses': ['/admin/builder', '/admin/lessons'],
};

bool _isActive(_NavItem item, String currentPath) {
  if (item.path == '/') return currentPath == '/';
  for (final alias in _sectionAliases[item.path] ?? const <String>[]) {
    if (currentPath.startsWith(alias)) return true;
  }
  // "Пользователи" is /admin, a prefix of every other admin path — without
  // this it would light up on the courses/builder screens too. Its own
  // section is just /admin itself plus /admin/users/*.
  if (item.path == '/admin') {
    return currentPath == '/admin' || currentPath.startsWith('/admin/users');
  }
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
    // Gated on the route too, not just the provider value (§ graph editor
    // layout, 2026-09-04 verification finding) — a stray postFrameCallback
    // racing LessonGraphEditor's own dispose() could otherwise leave a
    // stale non-null value showing these on completely unrelated screens.
    // Every lesson-builder path (course editor, lesson editor, and the
    // graph inside it) lives under /admin/builder — this is the same
    // prefix _sectionAliases below already uses to recognize the section.
    final graphActions = currentPath.startsWith('/admin/builder') ? ref.watch(graphSidebarActionsProvider) : null;

    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: c.primary,
        // Only the inner (content-facing) corners are rounded — the rail
        // still bleeds to the window's own left edge, exactly like the
        // reference (§ shell card treatment, 2026-09-02).
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(_shellRadius),
          bottomRight: Radius.circular(_shellRadius),
        ),
      ),
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
            if (graphActions != null) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                child: Divider(color: Colors.white24, height: 1),
              ),
              Expanded(child: SingleChildScrollView(child: _GraphToolsSection(actions: graphActions))),
            ] else
              const Spacer(),
            if (graphActions == null)
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

/// The graph editor's own tool group (§ graph editor layout, 2026-09-04,
/// changes 1-3): every "+ add block" type as an icon button, then "Соединить
/// блоки"/"Отменить соединение", "Урок" (opens the lesson-settings dialog),
/// "Маршрут" (opens the connections dialog), and "Выйти из графа" — all in
/// the same rail, replacing the logout button while a graph is open (still
/// reachable from Settings/Profile, same convention _BottomBar already uses
/// for not fitting logout into its own row).
class _GraphToolsSection extends StatelessWidget {
  const _GraphToolsSection({required this.actions});
  final GraphSidebarActions actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final block in actions.blockTypes)
          _RailButton(
            icon: block.icon,
            tooltip: block.label,
            active: false,
            enabled: !actions.busy,
            onTap: () => actions.onAdd(block.type),
          ),
        _RailButton(
          icon: Icons.arrow_right_alt,
          tooltip: actions.connecting ? 'Отменить соединение' : 'Соединить блоки',
          active: actions.connecting,
          enabled: !actions.busy,
          onTap: actions.onToggleConnect,
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          child: Divider(color: Colors.white24, height: 1),
        ),
        _RailButton(icon: Icons.description_outlined, tooltip: 'Урок', active: false, onTap: actions.onOpenLessonSettings),
        _RailButton(icon: Icons.route_outlined, tooltip: 'Маршрут', active: false, onTap: actions.onOpenRoute),
        _RailButton(icon: Icons.logout, tooltip: 'Выйти из графа', active: false, onTap: actions.onExit),
      ],
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
  const _RailButton({required this.icon, required this.tooltip, required this.active, required this.onTap, this.enabled = true});

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  // Additive (§ graph editor layout, 2026-09-04) — every pre-existing call
  // site omits this and keeps its exact old always-enabled behavior; only
  // the graph tool buttons pass false while a request is in flight.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Tooltip(
        message: tooltip,
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
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
          height: ProfileMetrics.bottomBarHeight,
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
