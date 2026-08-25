import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Every screen in this app navigates with `context.go(...)`, which
/// replaces go_router's whole page stack rather than pushing onto it — so
/// a screen reached that way is the *only* page on the underlying platform
/// Navigator. That means the Android system back button has nothing to
/// pop: it falls straight through to closing the app, even from a screen
/// that visually has its own back arrow going somewhere else.
///
/// Wrap a "nested" screen's Scaffold in this so system back reuses that
/// same visual back arrow's target — [fallbackPath] — instead of exiting.
class BackGuard extends StatelessWidget {
  const BackGuard({super.key, required this.fallbackPath, required this.child});

  final String fallbackPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallbackPath);
      },
      child: child,
    );
  }
}
