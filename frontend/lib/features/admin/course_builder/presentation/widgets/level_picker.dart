import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/theme/app_theme.dart';
import '../../../admin_tokens.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/taxonomy_domain.dart';

/// Standard CEFR levels, offered as one-tap quick-create options — not an
/// enforced/validated set server-side (Level.code is free text, same as
/// every other "kind" string in this app), just a convenience shortlist so
/// a teacher isn't forced to type "A0" from scratch for a brand-new language.
const _cefrSuggestions = ['A0', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

const _createNewSentinel = '__create_new__';

/// Language → Level picker, reused by both the "new course" card and the
/// course-settings card in the builder — reads/writes only `levelId`
/// (Course's actual persisted field); the language step exists purely to
/// filter/create levels, since a course has no languageId of its own
/// (Language is only reachable through Level.languageId).
class LevelPickerField extends ConsumerStatefulWidget {
  const LevelPickerField({super.key, required this.initialLevelId, required this.onChanged});

  final String? initialLevelId;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<LevelPickerField> createState() => _LevelPickerFieldState();
}

class _LevelPickerFieldState extends ConsumerState<LevelPickerField> {
  List<AdminLanguage> _languages = [];
  List<AdminLevel> _allLevels = [];
  String? _languageId;
  String? _levelId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _levelId = widget.initialLevelId;
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(builderRepositoryProvider);
      final languages = await repo.listLanguages();
      final levels = await repo.listLevels();
      String? languageId;
      if (widget.initialLevelId != null) {
        final match = levels.where((l) => l.id == widget.initialLevelId);
        languageId = match.isEmpty ? null : match.first.languageId;
      }
      if (mounted) {
        setState(() {
          _languages = languages;
          _allLevels = levels;
          _languageId = languageId;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showErrorSnack(context, e, 'Не удалось загрузить языки и уровни');
      }
    }
  }

  List<AdminLevel> get _levelsForLanguage =>
      _allLevels.where((l) => l.languageId == _languageId).toList()..sort((a, b) => a.position.compareTo(b.position));

  Future<void> _createLanguage() async {
    final name = await _promptText(context, title: 'Новый язык', label: 'Например, «Английский»');
    if (name == null || name.trim().isEmpty) return;
    try {
      final (language, existing) = await ref.read(builderRepositoryProvider).createLanguage(name.trim());
      if (!mounted) return;
      setState(() {
        if (!_languages.any((l) => l.id == language.id)) _languages = [..._languages, language];
        _languageId = language.id;
        _levelId = null;
      });
      widget.onChanged(null);
      if (existing) showSuccessSnack(context, 'Такой язык уже есть — выбран существующий.');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось создать язык');
    }
  }

  Future<void> _createLevel() async {
    final languageId = _languageId;
    if (languageId == null) return;
    final existingCodes = _levelsForLanguage.map((l) => l.code.toUpperCase()).toSet();
    final code = await _promptLevelCode(context, existingCodes: existingCodes);
    if (code == null || code.trim().isEmpty) return;
    try {
      final position = _levelsForLanguage.length;
      final level = await ref.read(builderRepositoryProvider).createLevel(languageId, code.trim(), code.trim(), position: position);
      if (!mounted) return;
      setState(() {
        _allLevels = [..._allLevels, level];
        _levelId = level.id;
      });
      widget.onChanged(level.id);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось создать уровень');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox(height: 48, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String?>(
          initialValue: _languageId,
          decoration: adminInputDecoration(label: 'Язык курса'),
          items: [
            for (final l in _languages) DropdownMenuItem(value: l.id, child: Text(l.name)),
            const DropdownMenuItem(value: _createNewSentinel, child: Text('+ Добавить новый язык…')),
          ],
          onChanged: (value) {
            if (value == _createNewSentinel) {
              _createLanguage();
              return;
            }
            setState(() {
              _languageId = value;
              _levelId = null;
            });
            widget.onChanged(null);
          },
          hint: const Text('Не выбран'),
        ),
        if (_languageId != null) ...[
          const SizedBox(height: AdminMetrics.fieldGap),
          DropdownButtonFormField<String?>(
            initialValue: _levelId,
            decoration: adminInputDecoration(label: 'Уровень'),
            items: [
              for (final l in _levelsForLanguage) DropdownMenuItem(value: l.id, child: Text('${l.code} — ${l.name}')),
              const DropdownMenuItem(value: _createNewSentinel, child: Text('+ Добавить уровень…')),
            ],
            onChanged: (value) {
              if (value == _createNewSentinel) {
                _createLevel();
                return;
              }
              setState(() => _levelId = value);
              widget.onChanged(value);
            },
            hint: const Text('Без уровня'),
          ),
        ],
      ],
    );
  }
}

// Both dialogs below force lightTheme (§ admin light-theme fix, 2026-09-01)
// — showDialog attaches to the Navigator's Overlay, outside any ancestor
// `Theme(data: lightTheme, ...)` wrapper (a screen's own, or even the
// bottom sheet this picker is often opened from), so without this the
// dialog falls back to the app's actual ambient theme.

Future<String?> _promptText(BuildContext context, {required String title, required String label}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Theme(
      data: lightTheme,
      child: AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, decoration: adminInputDecoration(label: label)),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Создать')),
        ],
      ),
    ),
  );
}

Future<String?> _promptLevelCode(BuildContext context, {required Set<String> existingCodes}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => Theme(
      data: lightTheme,
      child: AlertDialog(
        title: const Text('Новый уровень'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final code in _cefrSuggestions)
                  if (!existingCodes.contains(code))
                    ActionChip(label: Text(code), onPressed: () => Navigator.of(dialogContext).pop(code)),
              ],
            ),
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: controller, autofocus: true, decoration: adminInputDecoration(label: 'Или свой код, например «A0»')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Создать')),
        ],
      ),
    ),
  );
}
