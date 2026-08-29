import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../api/api_client.dart';

/// Push notifications (Firebase Cloud Messaging) — Android only for now.
/// Every entry point here is a no-op off Android (no iOS/Windows/web native
/// setup exists yet: no APNs config, no google-services.json equivalent, no
/// service worker), so calling this from app startup on any other platform
/// is always safe.
bool get _pushSupportedOnThisPlatform => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

void _log(String message) => developer.log(message, name: 'PushService');

/// Must run once at app startup, before anything else here — mirrors
/// MediaKit.ensureInitialized() in main.dart, same "do this before runApp"
/// shape. A failure here (e.g. this exact device/build has no Google Play
/// Services) is swallowed: push is a nice-to-have, never something that
/// should stop the app from starting.
Future<void> initializePushIfSupported() async {
  if (!_pushSupportedOnThisPlatform) return;
  try {
    await Firebase.initializeApp();
  } catch (e) {
    _log('Firebase.initializeApp failed, push disabled for this session: $e');
  }
}

/// Requests notification permission (Android 13+ needs this explicitly;
/// earlier versions grant it implicitly and this call is a harmless no-op),
/// then registers the device's current FCM token with the backend. Safe to
/// call every time the app has an authenticated user (fresh login or a
/// restored session) — the backend's registerToken is an upsert, so
/// re-sending the same token repeatedly is harmless.
Future<void> registerPushTokenIfSupported(ApiClient api) async {
  if (!_pushSupportedOnThisPlatform) return;
  try {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _log('Notification permission denied by the user.');
      return;
    }
    final token = await messaging.getToken();
    if (token == null) return;
    await api.post('/api/me/push-token', body: {'token': token, 'platform': 'android'});
    // A token can rotate at any point while the app is running (not just on
    // reinstall) — re-register whenever that happens.
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      api.post('/api/me/push-token', body: {'token': newToken, 'platform': 'android'}).catchError((Object e) {
        _log('Failed to register a refreshed push token: $e');
        return <String, dynamic>{};
      });
    });
  } catch (e) {
    _log('Push token registration failed: $e');
  }
}

/// The deep-link path (e.g. "/courses/x/lesson/y/vocabulary") carried in a
/// notification's data payload — app.dart's GoRouter already understands
/// this exact route shape, no new route needed. Returns null if the
/// message carries no deep link, or push isn't supported on this platform.
String? _deepLinkFrom(RemoteMessage message) {
  final link = message.data['deepLink'];
  return (link is String && link.isNotEmpty) ? link : null;
}

/// Wires up "the app was opened by tapping a notification" for both cases:
/// tapped while the app was already running in the background, and tapped
/// from a cold start (app wasn't running at all). Call once, after the
/// GoRouter exists, passing a function that navigates to the given path —
/// kept as a plain callback rather than a BuildContext/GoRouter dependency
/// so this file has no UI-layer imports.
Future<void> listenForNotificationTaps(void Function(String path) navigateTo) async {
  if (!_pushSupportedOnThisPlatform) return;
  try {
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final path = _deepLinkFrom(message);
      if (path != null) navigateTo(path);
    });
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final path = _deepLinkFrom(initialMessage);
      if (path != null) navigateTo(path);
    }
  } catch (e) {
    // Called fire-and-forget from initState (see app.dart) — an uncaught
    // error here becomes an unhandled Future rejection that crashes the
    // whole app. If Firebase didn't actually initialize (e.g. no Google
    // Play Services on this device), tap-to-open-lesson just silently
    // doesn't work; nothing else should be at stake over it.
    _log('listenForNotificationTaps failed: $e');
  }
}
