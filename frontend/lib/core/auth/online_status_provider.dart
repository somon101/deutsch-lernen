import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the app is currently in the foreground — driven by
/// AppLifecycleHeartbeat's WidgetsBindingObserver. The "online" dot on the
/// user's own profile reads this directly rather than any cached
/// lastActiveAt timestamp: if the app is open and resumed right now, the
/// user is self-evidently online, no server round trip needed to know that
/// about yourself.
final isAppForegroundProvider = StateProvider<bool>((ref) => true);
