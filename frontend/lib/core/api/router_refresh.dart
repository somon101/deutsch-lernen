import 'package:flutter/foundation.dart';

/// Bridges Riverpod state changes into go_router's refreshListenable, so
/// redirect() re-runs whenever auth state changes (login/logout) — without
/// this, go_router only re-evaluates redirects on navigation, not on state
/// changes that happen to already be on the current screen. Driven by a
/// manual ref.listen(...) call (see app.dart's routerProvider) rather than
/// a Stream, since AsyncNotifierProvider doesn't expose one directly.
class GoRouterRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}
