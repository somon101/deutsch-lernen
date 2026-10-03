import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../course_builder/data/builder_repository.dart';
import '../../course_builder/domain/taxonomy_domain.dart';
import '../../widgets/admin_feedback.dart';
import '../../widgets/json_file_button.dart';
import '../data/rules_repository.dart';

const _pageSize = 30;

/// The admin «Правила» screen — like «Фразы», but each entry is a single
/// rule sentence. One list per studied language, manual add/edit and a
/// JSON import (pasted or loaded from a file).
class AdminRulesScreen extends ConsumerStatefulWidget {
  const AdminRulesScreen({super.key, this.languageId});

  /// When set, the screen is embedded in a language workspace: this
  /// language is fixed (no language picker anywhere) and there is no back
  /// arrow of its own.
  final String? languageId;

  @override
  ConsumerState<AdminRulesScreen> createState() => _AdminRulesScreenState();
}

class _AdminRulesScreenState extends ConsumerState<AdminRulesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AdminLanguage> _languages = const [];
  String? _languageId;
  List<AdminRule> _rules = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final languages = await ref.read(builderRepositoryProvider).listLanguages();
      if (!mounted) return;
      setState(() {
        final fixed = widget.languageId;
        _languages = fixed == null ? languages : [for (final l in languages) if (l.id == fixed) l];
        _languageId = fixed ?? (languages.isNotEmpty ? languages.first.id : null);
      });
      await _load(reset: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = adminErrorMessage(e, 'Не удалось загрузить языки');
          _loading = false;
        });
      }
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_languageId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => reset ? _loading = true : _loadingMore = true);
    try {
      final page = await ref.read(rulesRepositoryProvider).listRules(
            languageId: _languageId,
            query: _searchController.text,
            limit: _pageSize,
            offset: reset ? 0 : _rules.length,
          );
      if (!mounted) return;
      setState(() {
        _rules = reset ? page.rules : [..._rules, ...page.rules];
        _total = page.total;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось загрузить правила'));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(reset: true));
  }

  Future<void> _afterSave(String? languageId) async {
    if (languageId == null) return;
    if (languageId != _languageId) setState(() => _languageId = languageId);
    await _load(reset: true);
  }

  Future<void> _openEditor([AdminRule? rule]) async {
    final languageId = _languageId;
    if (languageId == null) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => Theme(data: lightTheme, child: _RuleDialog(languages: _languages, languageId: languageId, rule: rule)),
    );
    await _afterSave(saved);
  }

  Future<void> _openImport() async {
    final languageId = _languageId;
    if (languageId == null) return;
    final imported = await showDialog<String>(
      context: context,
      builder: (_) => Theme(data: lightTheme, child: _ImportDialog(languages: _languages, languageId: languageId)),
    );
    await _afterSave(imported);
  }

  Future<void> _delete(AdminRule rule) async {
    final ok = await confirmDialog(context, title: 'Удалить правило?', message: '«${rule.text}» будет удалено.', confirmLabel: 'Удалить');
    if (!ok) return;
    try {
      await ref.read(rulesRepositoryProvider).deleteRule(rule.id);
      await _load(reset: true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить правило');
    }
  }

  @override
  Widget build(BuildContext context) {
    return BackGuard(
      fallbackPath: '/',
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text('Правила', style: AdminTypography.pageTitle),
            automaticallyImplyLeading: false,
            leading: widget.languageId != null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
            actions: [
              TextButton.icon(onPressed: _openImport, style: AdminButtonStyles.text(), icon: const Icon(Icons.upload_file, size: 18), label: const Text('Импорт JSON')),
              TextButton.icon(onPressed: () => _openEditor(), style: AdminButtonStyles.text(), icon: const Icon(Icons.add, size: 18), label: const Text('Новое правило')),
              const SizedBox(width: 4),
            ],
          ),
          body: AdminMaxWidth(
            maxWidth: AdminMetrics.maxListWidth,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, AdminMetrics.cardGap, 16, 8),
                  child: Row(
                    children: [
                      if (widget.languageId == null && _languages.isNotEmpty) ...[
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_languageId),
                            initialValue: _languageId,
                            decoration: adminInputDecoration(label: 'Изучаемый язык'),
                            items: [for (final l in _languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
                            onChanged: (v) {
                              setState(() => _languageId = v);
                              _load(reset: true);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: adminInputDecoration(hint: 'Поиск по правилу…').copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Всего правил: $_total', style: AdminTypography.caption)),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: AdminTypography.body))
                          : _languageId == null
                              ? Center(child: Text('Сначала создайте язык курса в конструкторе.', style: AdminTypography.body))
                              : _rules.isEmpty
                                  ? Center(child: Text('Правил пока нет. Добавьте вручную или через «Импорт JSON».', style: AdminTypography.body))
                                  : ListView.builder(
                                      padding: EdgeInsets.fromLTRB(16, 4, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
                                      itemCount: _rules.length + 1,
                                      itemBuilder: (context, index) {
                                        if (index == _rules.length) {
                                          if (_rules.length >= _total) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            child: Center(
                                              child: _loadingMore
                                                  ? const CircularProgressIndicator()
                                                  : OutlinedButton(onPressed: () => _load(), style: AdminButtonStyles.secondary(), child: const Text('Показать ещё')),
                                            ),
                                          );
                                        }
                                        final r = _rules[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: AdminCard(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Expanded(child: Text(r.text, style: AdminTypography.body)),
                                                IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openEditor(r)),
                                                AdminDeleteLink(onPressed: () => _delete(r)),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleDialog extends ConsumerStatefulWidget {
  const _RuleDialog({required this.languages, required this.languageId, this.rule});
  final List<AdminLanguage> languages;
  final String languageId;
  final AdminRule? rule;

  @override
  ConsumerState<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends ConsumerState<_RuleDialog> {
  late final _text = TextEditingController(text: widget.rule?.text ?? '');
  late String _languageId = widget.languageId;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _text.text.trim();
    if (text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(rulesRepositoryProvider);
      final rule = widget.rule;
      if (rule == null) {
        await repo.createRule(languageId: _languageId, text: text);
      } else {
        await repo.updateRule(rule.id, text);
      }
      if (mounted) Navigator.of(context).pop(rule?.languageId ?? _languageId);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить правило');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.rule == null ? 'Новое правило' : 'Правило'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.rule == null && widget.languages.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _languageId,
                decoration: adminInputDecoration(label: 'Изучаемый язык'),
                items: [for (final l in widget.languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
                onChanged: _busy ? null : (v) => setState(() => _languageId = v ?? _languageId),
              ),
              const SizedBox(height: AdminMetrics.fieldGap),
            ],
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 2,
              maxLines: 5,
              onChanged: (_) => setState(() {}),
              decoration: adminInputDecoration(label: 'Правило (одной фразой)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(
          onPressed: _busy || _text.text.trim().isEmpty ? null : _save,
          style: AdminButtonStyles.primary(),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

/// Accepts a JSON list of strings or of {"text": ...} objects.
({List<String> rules, String? error}) parseRulesImport(String source) {
  if (source.trim().isEmpty) return (rules: const [], error: 'Вставьте JSON или загрузите файл .json');
  dynamic decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return (rules: const [], error: 'Некорректный JSON: не удалось разобрать текст. Проверьте синтаксис.');
  }
  if (decoded is! List) return (rules: const [], error: 'Корневой элемент должен быть списком: [ ... ]');
  if (decoded.isEmpty) return (rules: const [], error: 'Список пуст — добавьте хотя бы одно правило.');
  final rules = <String>[];
  final problems = <String>[];
  for (var i = 0; i < decoded.length; i++) {
    final item = decoded[i];
    final text = (item is Map ? item['text'] : item is String ? item : null)?.toString().trim() ?? '';
    if (text.isEmpty) {
      problems.add('Правило №${i + 1}: пустое или без поля "text"');
    } else {
      rules.add(text);
    }
  }
  if (problems.isNotEmpty) {
    final rest = problems.length - 5;
    return (rules: const [], error: problems.take(5).join('\n') + (rest > 0 ? '\n…и ещё $rest' : ''));
  }
  return (rules: rules, error: null);
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.languages, required this.languageId});
  final List<AdminLanguage> languages;
  final String languageId;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _json = TextEditingController();
  late String _languageId = widget.languageId;
  String? _error;
  bool _busy = false;

  static const _example = '[\n  {"text": "Существительные в немецком пишутся с большой буквы."},\n  {"text": "Глагол в утвердительном предложении стоит на втором месте."}\n]';

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final parse = parseRulesImport(_json.text);
    if (parse.error != null) {
      setState(() => _error = parse.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(rulesRepositoryProvider).importRules(_languageId, parse.rules);
      if (!mounted) return;
      showSuccessSnack(context, 'Добавлено: ${result.added}, пропущено (уже есть): ${result.skipped}');
      Navigator.of(context).pop(_languageId);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось импортировать'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт правил'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.languages.length > 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: _languageId,
                  decoration: adminInputDecoration(label: 'Для какого языка импортируем'),
                  items: [for (final l in widget.languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
                  onChanged: _busy ? null : (v) => setState(() => _languageId = v ?? _languageId),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Список правил в JSON: объекты с полем "text" или просто строки. Правила, которые уже есть, будут пропущены.',
                style: AdminTypography.caption,
              ),
              const SizedBox(height: 8),
              JsonFileButton(
                enabled: !_busy,
                onLoaded: (text) => setState(() {
                  _json.text = text;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _json,
                minLines: 8,
                maxLines: 16,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: adminInputDecoration(hint: _example),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AdminTypography.caption.copyWith(color: AdminColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _import, style: AdminButtonStyles.primary(), child: const Text('Импортировать')),
      ],
    );
  }
}
