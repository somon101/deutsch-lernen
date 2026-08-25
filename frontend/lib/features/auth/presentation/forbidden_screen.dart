import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';

/// Mirrors src/pages/ForbiddenPage.tsx — shown when go_router's redirect
/// blocks a role-mismatched route. Message differs slightly for TEACHER,
/// same as the React version.
class ForbiddenScreen extends ConsumerWidget {
  const ForbiddenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).value;
    final isTeacher = user?.role == UserRole.teacher;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 40),
              const SizedBox(height: 16),
              Text('Доступ запрещён', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                isTeacher
                    ? 'Этот раздел доступен только администраторам.'
                    : 'У вас нет доступа к этой странице.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(onPressed: () => context.go('/'), child: const Text('На главную')),
            ],
          ),
        ),
      ),
    );
  }
}
