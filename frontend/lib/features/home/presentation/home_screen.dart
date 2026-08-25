import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/theme/theme_provider.dart';

/// Real (not a stub) — the app's landing screen, with the navigation every
/// other screen is reached from. The actual course/lesson content it will
/// show is Phase 5 work; for now it's the functional shell: theme toggle,
/// role-aware nav links, logout.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deutsch Lernen'),
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
          if (user != null)
            Text('Привет, ${user.firstName}!', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          _NavCard(icon: Icons.menu_book_outlined, title: 'Курсы', onTap: () => context.go('/courses')),
          _NavCard(icon: Icons.person_outline, title: 'Профиль', onTap: () => context.go('/profile')),
          if (user?.isStaff ?? false)
            _NavCard(icon: Icons.edit_note_outlined, title: 'Конструктор курсов', onTap: () => context.go('/admin/courses')),
          if (user?.isAdmin ?? false)
            _NavCard(icon: Icons.people_outline, title: 'Пользователи', onTap: () => context.go('/admin')),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => ref.read(authProvider.notifier).logout(),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.icon, required this.title, required this.onTap});

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
