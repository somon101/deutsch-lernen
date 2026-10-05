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
import '../data/topics_repository.dart';

const _pageSize = 30;

/// The «Темы» tab of a language: the topics lessons are tagged with (the
/// same list the lesson editor's topic picker shows) — create, rename,
/// delete, search and a
/// JSON import (pasted or loaded from a file).
class AdminTopicsScreen extends ConsumerStatefulWidget {
  const AdminTopicsScreen({super.key, this.languageId});

  /// When set, the screen is embedded in a language workspace: this
  /// language is fixed (no language picker anywhere) and there is no back
  /// arrow of its own.
  final String? languageId;

  @override
  ConsumerState<AdminTopicsScreen> createState() => _AdminTopicsScreenState();
}

class _AdminTopicsScreenState extends ConsumerState<AdminTopicsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AdminLanguage> _languages = const [];
  String? _languageId;
  List<AdminTopicEntry> _topics = const [];
  int _total = 0;
  int _usedCount = 0;
  int _unusedCount = 0;
  // null = all, true = used, false = unused.
  bool? _used;
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
      final page = await ref.read(topicsRepositoryProvider).listTopics(
            languageId: _languageId,
            query: _searchController.text,
            used: _used,
            limit: _pageSize,
            offset: reset ? 0 : _topics.length,
          );
      if (!mounted) return;
      setState(() {
        _topics = reset ? page.topics : [..._topics, ...page.topics];
        _total = page.total;
        _usedCount = page.usedCount;
        _unusedCount = page.unusedCount;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось загрузить темы'));
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

  Future<void> _openEditor([AdminTopicEntry? topic]) async {
    final languageId = _languageId;
    if (languageId == null) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => Theme(data: lightTheme, child: _TopicDialog(languages: _languages, languageId: languageId, topic: topic)),
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

  Future<void> _delete(AdminTopicEntry topic) async {
    final ok = await confirmDialog(context, title: 'Удалить тему «${topic.name}»?', message: topic.usage > 0 ? 'Тема снимется с ${topic.usage} материалов/вопросов/фраз, сами они останутся.' : 'Тема не используется.', confirmLabel: 'Удалить');
    if (!ok) return;
    try {
      await ref.read(topicsRepositoryProvider).deleteTopic(topic.id);
      await _load(reset: true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить тему');
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
            title: Text('Темы', style: AdminTypography.pageTitle),
            automaticallyImplyLeading: false,
            leading: widget.languageId != null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
            actions: [
              TextButton.icon(onPressed: _openImport, style: AdminButtonStyles.text(), icon: const Icon(Icons.upload_file, size: 18), label: const Text('Импорт JSON')),
              TextButton.icon(onPressed: () => _openEditor(), style: AdminButtonStyles.text(), icon: const Icon(Icons.add, size: 18), label: const Text('Новая тема')),
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
                          decoration: adminInputDecoration(hint: 'Поиск по теме…').copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final (value, label) in [
                          (null, 'Все · ${_usedCount + _unusedCount}'),
                          (true, 'Используются · $_usedCount'),
                          (false, 'Не используются · $_unusedCount'),
                        ])
                          ChoiceChip(
                            label: Text(label),
                            selected: _used == value,
                            onSelected: (_) {
                              if (_used == value) return;
                              setState(() => _used = value);
                              _load(reset: true);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Показано тем: $_total', style: AdminTypography.caption)),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: AdminTypography.body))
                          : _languageId == null
                              ? Center(child: Text('Сначала создайте язык курса в конструкторе.', style: AdminTypography.body))
                              : _topics.isEmpty
                                  ? Center(child: Text('Тем пока нет. Добавьте вручную или через «Импорт JSON».', style: AdminTypography.body))
                                  : ListView.builder(
                                      padding: EdgeInsets.fromLTRB(16, 4, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
                                      itemCount: _topics.length + 1,
                                      itemBuilder: (context, index) {
                                        if (index == _topics.length) {
                                          if (_topics.length >= _total) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            child: Center(
                                              child: _loadingMore
                                                  ? const CircularProgressIndicator()
                                                  : OutlinedButton(onPressed: () => _load(), style: AdminButtonStyles.secondary(), child: const Text('Показать ещё')),
                                            ),
                                          );
                                        }
                                        final r = _topics[index];
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: AdminCard(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(r.name, style: AdminTypography.body),
                                                      Text(r.usage > 0 ? 'используется: ${r.usage}' : 'пока не используется', style: AdminTypography.caption),
                                                    ],
                                                  ),
                                                ),
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

class _TopicDialog extends ConsumerStatefulWidget {
  const _TopicDialog({required this.languages, required this.languageId, this.topic});
  final List<AdminLanguage> languages;
  final String languageId;
  final AdminTopicEntry? topic;

  @override
  ConsumerState<_TopicDialog> createState() => _TopicDialogState();
}

class _TopicDialogState extends ConsumerState<_TopicDialog> {
  late final _text = TextEditingController(text: widget.topic?.name ?? '');
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
      final repo = ref.read(topicsRepositoryProvider);
      final topic = widget.topic;
      if (topic == null) {
        await repo.createTopic(languageId: _languageId, name: text);
      } else {
        await repo.renameTopic(topic.id, text);
      }
      if (mounted) Navigator.of(context).pop(topic?.languageId ?? _languageId);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить тему');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.topic == null ? 'Новая тема' : 'Тема'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.topic == null && widget.languages.length > 1) ...[
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
              maxLines: 1,
              onChanged: (_) => setState(() {}),
              decoration: adminInputDecoration(label: 'Название темы (например, Präteritum, Артикли)'),
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

/// Accepts a JSON list of strings or of {"name": ...} objects.
({List<String> names, String? error}) parseTopicsImport(String source) {
  if (source.trim().isEmpty) return (names: const [], error: 'Вставьте JSON или загрузите файл .json');
  dynamic decoded;
  try {
    decoded = jsonDecode(source);
  } catch (_) {
    return (names: const [], error: 'Некорректный JSON: не удалось разобрать текст. Проверьте синтаксис.');
  }
  if (decoded is! List) return (names: const [], error: 'Корневой элемент должен быть списком: [ ... ]');
  if (decoded.isEmpty) return (names: const [], error: 'Список пуст — добавьте хотя бы одну тему.');
  final names = <String>[];
  final problems = <String>[];
  for (var i = 0; i < decoded.length; i++) {
    final item = decoded[i];
    final text = (item is Map ? (item['name'] ?? item['text']) : item is String ? item : null)?.toString().trim() ?? '';
    if (text.isEmpty) {
      problems.add('Тема №${i + 1}: пустая или без поля "name"');
    } else {
      names.add(text);
    }
  }
  if (problems.isNotEmpty) {
    final rest = problems.length - 5;
    return (names: const [], error: problems.take(5).join('\n') + (rest > 0 ? '\n…и ещё $rest' : ''));
  }
  return (names: names, error: null);
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

  static const _example = '[\n  {"name": "Präteritum"},\n  {"name": "Артикли"},\n  "Числа"\n]';

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final parse = parseTopicsImport(_json.text);
    if (parse.error != null) {
      setState(() => _error = parse.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(topicsRepositoryProvider).importTopics(_languageId, parse.names);
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
      title: const Text('Импорт тем'),
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
                'Список тем в JSON: объекты с полем "name" или просто строки. Темы, которые уже есть в этом языке, будут пропущены.',
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
