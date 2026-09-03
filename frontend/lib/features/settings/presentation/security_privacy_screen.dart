import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_state.dart';
import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/security_repository.dart';
import 'widgets/settings_section.dart';
import 'widgets/settings_tile.dart';

/// A reasonably strict, syntax-only email check for immediate UX feedback
/// (§ security & privacy rework, 2026-09-03). Deliberately not the source of
/// truth: the backend's own EmailStr (the email-validator package) re-checks
/// every request server-side and is the actual authority — confirmed
/// separately to correctly reject missing "@", a missing/malformed domain,
/// stray spaces, and doubled separators, all without a network/DNS lookup
/// (syntax only, never checks whether the mailbox exists). This regex only
/// has to catch the obvious mistakes before a round trip even starts.
bool looksLikeValidEmail(String value) {
  final email = value.trim();
  if (email.isEmpty) return false;
  final pattern = RegExp(
    r'^(?!.*\.\.)[A-Za-z0-9](?:[A-Za-z0-9._%+-]*[A-Za-z0-9])?'
    r'@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$',
  );
  return pattern.hasMatch(email);
}

class SecurityPrivacyScreen extends ConsumerStatefulWidget {
  const SecurityPrivacyScreen({super.key});

  @override
  ConsumerState<SecurityPrivacyScreen> createState() => _SecurityPrivacyScreenState();
}

class _SecurityPrivacyScreenState extends ConsumerState<SecurityPrivacyScreen> {
  Future<void> _openEmailDialog() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _EmailChangeDialog());
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).saved)));
    }
  }

  Future<void> _openPasswordDialog() async {
    final changed = await showDialog<bool>(context: context, builder: (_) => const _PasswordChangeDialog());
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).securityPasswordChanged)));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.securityDeleteAccountConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.securityDeleteAccountConfirmBody),
            const SizedBox(height: 12),
            TextField(controller: controller, decoration: InputDecoration(hintText: l10n.securityDeleteConfirmationWord)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.cancel)),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => FilledButton(
              style: FilledButton.styleFrom(backgroundColor: c.danger),
              onPressed: value.text.trim() == l10n.securityDeleteConfirmationWord ? () => Navigator.of(dialogContext).pop(true) : null,
              child: Text(l10n.securityDeleteAccountAction),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed ?? false) {
      await ref.read(securityRepositoryProvider).deleteAccount();
      if (mounted) ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final linked = ref.watch(linkedAccountsProvider);
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    return BackGuard(
      fallbackPath: '/settings',
      child: Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? ProfileMetrics.desktopContentMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? ProfileMetrics.pageMarginDesktop : ProfileMetrics.pageMarginMobile,
                vertical: ProfileMetrics.pageMarginMobile,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          tooltip: l10n.back,
                          icon: Icon(Icons.arrow_back, color: c.text),
                          onPressed: () => context.go('/settings'),
                        ),
                      ),
                      Expanded(child: Text(l10n.securityPrivacy, textAlign: TextAlign.center, style: ProfileTypography.sectionTitle(context))),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Email and password each show their CURRENT state first —
                  // the value for email, nothing shown for password — and
                  // editing happens in a floating modal, never inline on this
                  // page (§ security & privacy rework, 2026-09-03). Phone is
                  // gone entirely: no field, no row, no way to add one.
                  SettingsSection(
                    title: l10n.securityEmailLabel,
                    children: [
                      SettingsTile(
                        icon: Icons.email_outlined,
                        label: l10n.securityEmailLabel,
                        subtitle: user.email,
                        trailing: TextButton(onPressed: _openEmailDialog, child: Text(l10n.change)),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.securityChangePassword,
                    children: [
                      SettingsTile(
                        icon: Icons.lock_outline,
                        label: l10n.securityChangePassword,
                        onTap: _openPasswordDialog,
                        trailing: Icon(Icons.chevron_right, color: c.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.securityLinkedAccounts,
                    children: [
                      _LinkedAccountTile(
                        icon: Icons.g_mobiledata,
                        label: 'Google',
                        linked: linked.contains(LinkedProvider.google),
                        onTap: () => ref.read(linkedAccountsProvider.notifier).toggle(LinkedProvider.google),
                      ),
                      _LinkedAccountTile(
                        icon: Icons.apple,
                        label: 'Apple',
                        linked: linked.contains(LinkedProvider.apple),
                        onTap: () => ref.read(linkedAccountsProvider.notifier).toggle(LinkedProvider.apple),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(l10n.securityDeleteAccountWarning, style: ProfileTypography.caption(context)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: c.danger, side: BorderSide(color: c.danger)),
                    onPressed: _confirmDeleteAccount,
                    child: Text(l10n.securityDeleteAccount),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Floating modal for changing the account email
/// (§ security & privacy rework, 2026-09-03).
///
/// Owns its own text field and error/loading state, entirely separate from
/// the page behind it — closing without saving (Cancel, the barrier, the
/// back button) simply discards this widget, so the account's email is
/// untouched unless [_save] actually completes. Returns `true` via
/// [Navigator.pop] only after the backend confirms the change, never on the
/// strength of a local edit.
class _EmailChangeDialog extends ConsumerStatefulWidget {
  const _EmailChangeDialog();

  @override
  ConsumerState<_EmailChangeDialog> createState() => _EmailChangeDialogState();
}

class _EmailChangeDialogState extends ConsumerState<_EmailChangeDialog> {
  final _email = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Keeps the Save button's enabled state in sync with the field as the
    // user types — the same reactive pattern the old inline form used.
    _email.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final value = _email.text.trim();

    // Format is checked here, client-side, before any request is sent — an
    // obviously malformed address never reaches the network
    // (§3 of the request: "запрос на сохранение не должен выполняться").
    // The backend re-validates the same field independently on arrival;
    // this check is for immediate feedback, not the security boundary.
    if (!looksLikeValidEmail(value)) {
      setState(() => _error = l10n.securityEmailInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ref.read(profileRepositoryProvider).updateEmail(value);
      // The backend response — not the locally-typed value — is what gets
      // written into app state, so a stale email can never linger on screen
      // if the server normalized or rejected something unexpectedly.
      await ref.read(authProvider.notifier).updateLocalUser(updated);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Covers a taken email (409 from the backend's own uniqueness check),
      // a network failure, and anything else the server reports — surfaced
      // right here in the modal, never silently swallowed.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final canSubmit = !_saving && _email.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(l10n.securityChangeEmail),
      content: SizedBox(
        width: 360,
        child: TextField(
          controller: _email,
          autofocus: true,
          enabled: !_saving,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: l10n.securityNewEmail, errorText: _error),
          onSubmitted: (_) {
            if (canSubmit) _save();
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
          onPressed: canSubmit ? _save : null,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

/// Floating modal for changing the account password
/// (§ security & privacy rework, 2026-09-03).
///
/// The password itself is never shown on the settings page — only this
/// modal exists, with three fields. Every check (current password correct,
/// new password meets the project's existing minimum, confirmation matches)
/// happens before the request fires; the backend re-verifies the current
/// password and re-applies the same minimum independently, since a client
/// cannot be trusted to enforce either on its own.
class _PasswordChangeDialog extends ConsumerStatefulWidget {
  const _PasswordChangeDialog();

  @override
  ConsumerState<_PasswordChangeDialog> createState() => _PasswordChangeDialogState();
}

class _PasswordChangeDialogState extends ConsumerState<_PasswordChangeDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _repeat = TextEditingController();
  bool _showCurrent = false;
  bool _showNext = false;
  bool _showRepeat = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final controller in [_current, _next, _repeat]) {
      controller.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _canSubmit => !_saving && _current.text.isNotEmpty && _next.text.isNotEmpty && _repeat.text.isNotEmpty;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);

    // Same minimum the backend's ChangePasswordRequest already enforces
    // (Field(min_length=6)) — matched here, not invented fresh, per the
    // request's "по существующим требованиям безопасности проекта".
    if (_next.text.length < 6) {
      setState(() => _error = l10n.securityPasswordTooShort);
      return;
    }
    if (_next.text != _repeat.text) {
      setState(() => _error = l10n.securityPasswordsDontMatch);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The current-password check happens server-side
      // (backend/app/routers/me.py's verify_password against the stored
      // hash) — this call either succeeds because it was right, or throws
      // with the backend's own "Неверный текущий пароль", surfaced below.
      await ref.read(profileRepositoryProvider).changePassword(currentPassword: _current.text, newPassword: _next.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;

    return AlertDialog(
      title: Text(l10n.securityChangePassword),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _PasswordField(
              controller: _current,
              label: l10n.securityCurrentPassword,
              obscure: !_showCurrent,
              enabled: !_saving,
              onToggle: () => setState(() => _showCurrent = !_showCurrent),
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _next,
              label: l10n.securityNewPassword,
              obscure: !_showNext,
              enabled: !_saving,
              onToggle: () => setState(() => _showNext = !_showNext),
            ),
            const SizedBox(height: 12),
            _PasswordField(
              controller: _repeat,
              label: l10n.securityRepeatPassword,
              obscure: !_showRepeat,
              enabled: !_saving,
              onToggle: () => setState(() => _showRepeat = !_showRepeat),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(_error!, style: TextStyle(color: c.danger, fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
          onPressed: _canSubmit ? _save : null,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(l10n.save),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller, required this.label, required this.obscure, required this.onToggle, this.enabled = true});

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: enabled ? onToggle : null,
        ),
      ),
    );
  }
}

class _LinkedAccountTile extends StatelessWidget {
  const _LinkedAccountTile({required this.icon, required this.label, required this.linked, required this.onTap});

  final IconData icon;
  final String label;
  final bool linked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    return SettingsTile(
      icon: icon,
      label: label,
      subtitle: linked ? l10n.securityLinked : l10n.securityNotLinked,
      trailing: TextButton(
        onPressed: onTap,
        child: Text(linked ? l10n.securityUnlink : l10n.securityLink, style: TextStyle(color: linked ? c.danger : c.accent)),
      ),
    );
  }
}
