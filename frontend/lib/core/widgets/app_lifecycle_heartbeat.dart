import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../auth/auth_state.dart';
import '../auth/online_status_provider.dart';

/// Wraps the whole app to track foreground/background state
/// (isAppForegroundProvider, for the profile screen's own "online" dot) and
/// send a periodic heartbeat while resumed — a GET /api/me/ request, which
/// already bumps lastActiveAt server-side via require_auth's throttled
/// touch (see backend/app/auth/deps.py). Without this, lastActiveAt only
/// updates when *some* other request happens to fire; sitting idle on a
/// screen for a few minutes would otherwise let it go stale and show the
/// user as offline elsewhere (e.g. the admin user list) even while the app
/// is genuinely open in front of them.
class AppLifecycleHeartbeat extends ConsumerStatefulWidget {
  const AppLifecycleHeartbeat({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLifecycleHeartbeat> createState() => _AppLifecycleHeartbeatState();
}

class _AppLifecycleHeartbeatState extends ConsumerState<AppLifecycleHeartbeat> with WidgetsBindingObserver {
  Timer? _timer;
  static const _interval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sendHeartbeat();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _sendHeartbeat());
  }

  Future<void> _sendHeartbeat() async {
    if (ref.read(authProvider).value == null) return;
    try {
      await ref.read(apiClientProvider).get('/api/me/');
    } catch (_) {
      // Best-effort — a missed heartbeat just means the next one (or the
      // next real request) catches lastActiveAt back up.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    ref.read(isAppForegroundProvider.notifier).state = foreground;
    if (foreground) {
      _sendHeartbeat();
      _startTimer();
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
