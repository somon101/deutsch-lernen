import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/auth/user.dart';
import '../../../core/widgets/back_guard.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/data/profile_repository.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../../profile/presentation/widgets/profile_card.dart';

const _usernamePattern = r'^[A-Za-z0-9_]{3,32}$';

/// Falls back to "ru" when the app's locale has no `intl` date-symbol data
/// of its own — the same gap as flutter_localizations (see
/// core/locale/framework_locale_fallback.dart's docstring), just in a
/// separate package with its own separate locale data, so it needed its own
/// separate check: `intl` bundles zero symbol data for "tg" either,
/// and DateFormat throws for a locale it has no data for.
String _dateFormatLocale(BuildContext context) {
  final locale = Localizations.localeOf(context).toString();
  return DateFormat.localeExists(locale) ? locale : 'ru';
}

class PersonalDetailsScreen extends ConsumerStatefulWidget {
  const PersonalDetailsScreen({super.key});

  @override
  ConsumerState<PersonalDetailsScreen> createState() => _PersonalDetailsScreenState();
}

class _PersonalDetailsScreenState extends ConsumerState<PersonalDetailsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  DateTime? _birthDate;
  bool _initialized = false;

  bool _saving = false;
  String? _saveError;
  bool _idCopied = false;

  late String _initialFirstName;
  late String _initialLastName;
  late String _initialUsername;
  late String _initialBio;
  DateTime? _initialBirthDate;

  void _initFromUser(AppUser user) {
    if (_initialized) return;
    _initialized = true;
    _firstName.text = user.firstName;
    _lastName.text = user.lastName;
    _username.text = user.username;
    _bio.text = user.bio ?? '';
    _birthDate = user.birthDate != null ? DateTime.tryParse(user.birthDate!) : null;
    _initialFirstName = _firstName.text;
    _initialLastName = _lastName.text;
    _initialUsername = _username.text;
    _initialBio = _bio.text;
    _initialBirthDate = _birthDate;
    for (final c in [_firstName, _lastName, _username, _bio]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _username.dispose();
    _bio.dispose();
    super.dispose();
  }

  bool get _hasChanges =>
      _firstName.text != _initialFirstName ||
      _lastName.text != _initialLastName ||
      _username.text != _initialUsername ||
      _bio.text != _initialBio ||
      _birthDate != _initialBirthDate;

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _copyUserId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    setState(() => _idCopied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _idCopied = false);
    });
  }

  Future<void> _save(AppUser user) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final updated = await ref.read(profileRepositoryProvider).updateProfile(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: user.email,
            username: _username.text.trim(),
            bio: _bio.text.trim(),
            birthDate: _birthDate,
          );
      await ref.read(authProvider.notifier).updateLocalUser(updated);
      if (!mounted) return;
      setState(() {
        _initialFirstName = _firstName.text;
        _initialLastName = _lastName.text;
        _initialUsername = _username.text;
        _initialBio = _bio.text;
        _initialBirthDate = _birthDate;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).saved)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _saveError = e.message);
    } catch (e) {
      if (mounted) setState(() => _saveError = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).value;
    if (user == null) return const SizedBox.shrink();
    _initFromUser(user);

    final l10n = AppLocalizations.of(context);
    final c = context.profileColors;
    final isWide = MediaQuery.sizeOf(context).width >= ProfileMetrics.wideBreakpoint;

    return BackGuard(
      fallbackPath: '/settings',
      child: Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        // Align(topCenter), not Center — Center also centers vertically,
        // which floats a short form (like this one) in the middle of the
        // screen instead of starting it at the top. Only matters on
        // screens whose content doesn't already fill the viewport.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? ProfileMetrics.desktopContentMaxWidth : double.infinity),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isWide ? ProfileMetrics.pageMarginDesktop : ProfileMetrics.pageMarginMobile,
                vertical: ProfileMetrics.pageMarginMobile,
              ),
              child: Form(
                key: _formKey,
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
                        Expanded(child: Text(l10n.personalDetails, textAlign: TextAlign.center, style: ProfileTypography.sectionTitle(context))),
                        const SizedBox(width: 40),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ProfileCard(
                      child: Row(
                        children: [
                          Text('ID', style: ProfileTypography.body(context)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(user.publicId, overflow: TextOverflow.ellipsis, style: ProfileTypography.caption(context).copyWith(fontFamily: 'monospace')),
                          ),
                          TextButton(onPressed: () => _copyUserId(user.publicId), child: Text(_idCopied ? l10n.copied : l10n.copy)),
                        ],
                      ),
                    ),
                    const SizedBox(height: ProfileMetrics.cardGap),
                    if (!user.canEditProfile)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(l10n.profileEditDisabled, style: ProfileTypography.caption(context)),
                      ),
                    TextFormField(
                      controller: _firstName,
                      enabled: user.canEditProfile,
                      decoration: InputDecoration(labelText: l10n.personalDetailsFirstName),
                      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.personalDetailsFirstNameRequired : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _lastName,
                      enabled: user.canEditProfile,
                      decoration: InputDecoration(labelText: l10n.personalDetailsLastName),
                      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.personalDetailsLastNameRequired : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _username,
                      enabled: user.canEditProfile,
                      decoration: InputDecoration(
                        labelText: l10n.personalDetailsUsername,
                        helperText: l10n.personalDetailsUsernameHint,
                        helperMaxLines: 2,
                        prefixText: '@',
                      ),
                      validator: (v) => (v == null || !RegExp(_usernamePattern).hasMatch(v.trim())) ? l10n.personalDetailsUsernameInvalid : null,
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: user.canEditProfile ? _pickBirthDate : null,
                      child: InputDecorator(
                        decoration: InputDecoration(labelText: l10n.personalDetailsBirthDate),
                        child: Text(
                          _birthDate != null
                              ? DateFormat.yMMMMd(_dateFormatLocale(context)).format(_birthDate!)
                              : l10n.personalDetailsSelectDate,
                          style: ProfileTypography.body(context).copyWith(color: _birthDate != null ? c.text : c.textMuted),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _bio,
                      enabled: user.canEditProfile,
                      maxLength: 150,
                      maxLines: 3,
                      decoration: InputDecoration(labelText: l10n.personalDetailsBio, hintText: l10n.personalDetailsBioPlaceholder),
                    ),
                    const SizedBox(height: 8),
                    if (_saveError != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_saveError!, style: TextStyle(color: c.danger))),
                    if (user.canEditProfile)
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: Colors.white),
                        onPressed: (_hasChanges && !_saving) ? () => _save(user) : null,
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text(l10n.save),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
