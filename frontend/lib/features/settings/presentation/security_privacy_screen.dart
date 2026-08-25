import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Best-effort "+D (DDD) DDD-DD-DD" grouping — not validated per-country,
/// just digit grouping so the field doesn't feel like a bare number input.
class _PhoneMaskFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 11) digits = digits.substring(0, 11);

    final buffer = StringBuffer();
    if (digits.isNotEmpty) {
      buffer.write('+${digits[0]}');
      if (digits.length > 1) buffer.write(' (${digits.substring(1, digits.length < 4 ? digits.length : 4)}');
      if (digits.length >= 4) buffer.write(')');
      if (digits.length > 4) buffer.write(' ${digits.substring(4, digits.length < 7 ? digits.length : 7)}');
      if (digits.length > 7) buffer.write('-${digits.substring(7, digits.length < 9 ? digits.length : 9)}');
      if (digits.length > 9) buffer.write('-${digits.substring(9)}');
    }
    final text = buffer.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

class SecurityPrivacyScreen extends ConsumerStatefulWidget {
  const SecurityPrivacyScreen({super.key});

  @override
  ConsumerState<SecurityPrivacyScreen> createState() => _SecurityPrivacyScreenState();
}

class _SecurityPrivacyScreenState extends ConsumerState<SecurityPrivacyScreen> {
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _repeatPassword = TextEditingController();
  bool _showCurrentPassword = false;
  bool _showNewPassword = false;
  bool _showRepeatPassword = false;
  bool _passwordSaving = false;

  final _newEmail = TextEditingController();
  bool _emailSaving = false;

  final _newPhone = TextEditingController();
  bool _phoneSaving = false;

  @override
  void initState() {
    super.initState();
    _newEmail.addListener(() => setState(() {}));
    _newPhone.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _currentPassword.dispose();
    _newPassword.dispose();
    _repeatPassword.dispose();
    _newEmail.dispose();
    _newPhone.dispose();
    super.dispose();
  }

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _changePassword() async {
    final l10n = AppLocalizations.of(context);
    if (_newPassword.text != _repeatPassword.text) {
      _snack(l10n.securityPasswordsDontMatch);
      return;
    }
    setState(() => _passwordSaving = true);
    try {
      await ref.read(profileRepositoryProvider).changePassword(currentPassword: _currentPassword.text, newPassword: _newPassword.text);
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _repeatPassword.clear();
      _snack(l10n.securityPasswordChanged);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _passwordSaving = false);
    }
  }

  Future<void> _changeEmail() async {
    final user = ref.read(authProvider).value;
    if (user == null) return;
    setState(() => _emailSaving = true);
    try {
      final updated = await ref.read(profileRepositoryProvider).updateProfile(
            firstName: user.firstName,
            lastName: user.lastName,
            email: _newEmail.text.trim(),
            phone: user.phone,
          );
      await ref.read(authProvider.notifier).updateLocalUser(updated);
      if (!mounted) return;
      _newEmail.clear();
      _snack(AppLocalizations.of(context).saved);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _emailSaving = false);
    }
  }

  Future<void> _changePhone() async {
    final user = ref.read(authProvider).value;
    if (user == null) return;
    setState(() => _phoneSaving = true);
    try {
      final updated = await ref.read(profileRepositoryProvider).updateProfile(
            firstName: user.firstName,
            lastName: user.lastName,
            email: user.email,
            phone: _newPhone.text.trim(),
          );
      await ref.read(authProvider.notifier).updateLocalUser(updated);
      if (!mounted) return;
      _newPhone.clear();
      _snack(AppLocalizations.of(context).saved);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _phoneSaving = false);
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
                  SettingsSection(
                    title: l10n.securityChangePassword,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          children: [
                            _PasswordField(
                              controller: _currentPassword,
                              label: l10n.securityCurrentPassword,
                              obscure: !_showCurrentPassword,
                              onToggle: () => setState(() => _showCurrentPassword = !_showCurrentPassword),
                            ),
                            const SizedBox(height: 12),
                            _PasswordField(
                              controller: _newPassword,
                              label: l10n.securityNewPassword,
                              obscure: !_showNewPassword,
                              onToggle: () => setState(() => _showNewPassword = !_showNewPassword),
                            ),
                            const SizedBox(height: 12),
                            _PasswordField(
                              controller: _repeatPassword,
                              label: l10n.securityRepeatPassword,
                              obscure: !_showRepeatPassword,
                              onToggle: () => setState(() => _showRepeatPassword = !_showRepeatPassword),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                                onPressed: _passwordSaving ? null : _changePassword,
                                child: Text(l10n.save),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.securityChangeEmail,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          children: [
                            TextField(controller: _newEmail, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l10n.securityNewEmail)),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                                onPressed: (_emailSaving || _newEmail.text.trim().isEmpty) ? null : _changeEmail,
                                child: Text(l10n.save),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: ProfileMetrics.cardGap),
                  SettingsSection(
                    title: l10n.securityChangePhone,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        child: Column(
                          children: [
                            TextField(
                              controller: _newPhone,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [_PhoneMaskFormatter()],
                              decoration: InputDecoration(labelText: l10n.securityNewPhone),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                                onPressed: (_phoneSaving || _newPhone.text.trim().isEmpty) ? null : _changePhone,
                                child: Text(l10n.save),
                              ),
                            ),
                          ],
                        ),
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({required this.controller, required this.label, required this.obscure, required this.onToggle});

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
          onPressed: onToggle,
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
