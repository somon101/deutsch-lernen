import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/notifications/local_reminder_service.dart';
import 'core/push/push_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await initializePushIfSupported();
  // Must run before Settings can schedule/cancel the local study reminder
  // (§ study reminder local delivery, 2026-09-15) — a no-op on platforms
  // without real local-notification support (see the service's own header).
  await LocalReminderService.initialize();
  runApp(const ProviderScope(child: DeutschLernenApp()));
}
