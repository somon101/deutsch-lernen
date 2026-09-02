import 'package:flutter/material.dart';

import '../../../core/api/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../admin_tokens.dart';

/// Shared feedback helpers for the admin screens — a native SnackBar stands
/// in for the old React admin's transient "Сохранено" flash /
/// `.exercise-feedback.incorrect` banner, and AlertDialog stands in for its
/// `window.confirm(...)` calls (enumerated per-screen in the migration
/// notes: delete course/lesson/block/word, overwrite-material-from-library).

String adminErrorMessage(
  Object error, [
  String fallback = 'Не удалось выполнить действие',
]) {
  if (error is ApiException) return error.message;
  return fallback;
}

void showSuccessSnack(BuildContext context, [String message = 'Сохранено']) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), backgroundColor: AdminColors.success),
  );
}

void showErrorSnack(
  BuildContext context,
  Object error, [
  String fallback = 'Не удалось выполнить действие',
]) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(adminErrorMessage(error, fallback)),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Удалить',
}) async {
  final result = await showDialog<bool>(
    context: context,
    // showDialog attaches to the Navigator's Overlay, outside any local
    // `Theme(data: lightTheme, ...)` wrapper an admin screen applies to
    // itself — so without this, the dialog falls back to the app's actual
    // ambient theme instead of the admin family's fixed light palette (§
    // admin light-theme fix, 2026-09-01, same bug as the original report,
    // just in a spot that screen-level wrapper doesn't reach). confirmDialog
    // is only ever called from admin screens, so forcing lightTheme here is
    // always correct.
    builder: (context) => Theme(
      data: lightTheme,
      child: AlertDialog(
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
