import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Most screens in this app navigate with `context.go(...)`, which replaces
/// go_router's whole page stack rather than pushing onto it — so a screen
/// reached that way is the *only* page on the underlying platform
/// Navigator. That means the Android system back button has nothing to
/// pop: it falls straight through to closing the app, even from a screen
/// that visually has its own back arrow going somewhere else.
///
/// Wrap a "nested" screen's Scaffold in this so system back reuses that
/// same visual back arrow's target — [fallbackPath] — instead of exiting.
/// A screen that can ALSO be reached with `context.push(...)` (§
/// subscriptions follow-up, 2026-08-31 — a profile opened from a
/// followers/following list, itself pushed) genuinely has something to pop
/// to in that case, so this defers to the real Navigator stack instead of
/// always forcing [fallbackPath]: `Navigator.canPop` is false for every
/// existing go()-only screen exactly as before (nothing changes for them),
/// and true only when there's a real page underneath to return to.
class BackGuard extends StatelessWidget {
  const BackGuard({super.key, required this.fallbackPath, required this.child});

  final String fallbackPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go(fallbackPath);
      },
      child: child,
    );
  }
}
