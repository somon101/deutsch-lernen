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
import '../../ai/data/ai_repository.dart';
import '../../course_builder/data/builder_repository.dart';
import '../../course_builder/domain/taxonomy_domain.dart';
import '../../widgets/admin_feedback.dart';

const _pageSize = 30;

/// The admin «Фразы» screen (§ phrase base, 2026-10-03) — the phrase
/// counterpart of «Словарь»: one searchable list per language, plus a JSON
/// import for bulk loading. The AI lesson generator draws only from here
/// and from the word dictionary.
class AdminPhrasesScreen extends ConsumerStatefulWidget {
  const AdminPhrasesScreen({super.key});

  @override
  ConsumerState<AdminPhrasesScreen> createState() => _AdminPhrasesScreenState();
}

class _AdminPhrasesScreenState extends ConsumerState<AdminPhrasesScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  List<AdminLanguage> _languages = const [];
  String? _languageId;
  List<AdminPhrase> _phrases = const [];
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
        _languages = languages;
        _languageId = languages.isNotEmpty ? languages.first.id : null;
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
    setState(() {
      if (reset) {
        _loading = true;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await ref.read(aiRepositoryProvider).listPhrases(
            languageId: _languageId,
            query: _searchController.text,
            limit: _pageSize,
            offset: reset ? 0 : _phrases.length,
          );
      if (!mounted) return;
      setState(() {
        _phrases = reset ? page.phrases : [..._phrases, ...page.phrases];
        _total = page.total;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось загрузить фразы'));
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

  Future<void> _openEditor([AdminPhrase? phrase]) async {
    final languageId = _languageId;
    if (languageId == null) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(data: lightTheme, child: _PhraseDialog(languageId: languageId, phrase: phrase)),
    );
    if (saved == true) await _load(reset: true);
  }

  Future<void> _delete(AdminPhrase phrase) async {
    final ok = await confirmDialog(context, title: 'Удалить фразу?', message: '«${phrase.text}» будет удалена из базы.', confirmLabel: 'Удалить');
    if (!ok) return;
    try {
      await ref.read(aiRepositoryProvider).deletePhrase(phrase.id);
      await _load(reset: true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить фразу');
    }
  }

  Future<void> _openImport() async {
    final languageId = _languageId;
    if (languageId == null) return;
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => Theme(data: lightTheme, child: _ImportDialog(languageId: languageId)),
    );
    if (imported == true) await _load(reset: true);
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
            title: Text('Фразы', style: AdminTypography.pageTitle),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
            actions: [
              TextButton.icon(onPressed: _openImport, style: AdminButtonStyles.text(), icon: const Icon(Icons.upload_file, size: 18), label: const Text('Импорт JSON')),
              TextButton.icon(onPressed: () => _openEditor(), style: AdminButtonStyles.text(), icon: const Icon(Icons.add, size: 18), label: const Text('Новая фраза')),
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
                      if (_languages.length > 1) ...[
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            initialValue: _languageId,
                            decoration: adminInputDecoration(label: 'Язык'),
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
                          decoration: adminInputDecoration(hint: 'Поиск по фразе или переводу…').copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(alignment: Alignment.centerLeft, child: Text('Всего фраз: $_total', style: AdminTypography.caption)),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: AdminTypography.body))
                          : _languageId == null
                              ? Center(child: Text('Сначала создайте язык курса в конструкторе.', style: AdminTypography.body))
                              : _phrases.isEmpty
                                  ? Center(child: Text('Фраз пока нет. Добавьте вручную или через «Импорт JSON».', style: AdminTypography.body))
                                  : ListView.builder(
                                      padding: EdgeInsets.fromLTRB(16, 4, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
                                      itemCount: _phrases.length + 1,
                                      itemBuilder: (context, index) {
                                        if (index == _phrases.length) {
                                          if (_phrases.length >= _total) return const SizedBox.shrink();
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 12),
                                            child: Center(
                                              child: _loadingMore
                                                  ? const CircularProgressIndicator()
                                                  : OutlinedButton(onPressed: () => _load(), style: AdminButtonStyles.secondary(), child: const Text('Показать ещё')),
                                            ),
                                          );
                                        }
                                        final p = _phrases[index];
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
                                                      Text(p.text, style: AdminTypography.cardTitle),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        [p.translation, if (p.translationTg != null) p.translationTg!].where((t) => t.isNotEmpty).join('  ·  '),
                                                        style: AdminTypography.body,
                                                      ),
                                                      if (p.topicName != null) Text(p.topicName!, style: AdminTypography.caption),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => _openEditor(p)),
                                                AdminDeleteLink(onPressed: () => _delete(p)),
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

class _PhraseDialog extends ConsumerStatefulWidget {
  const _PhraseDialog({required this.languageId, this.phrase});
  final String languageId;
  final AdminPhrase? phrase;

  @override
  ConsumerState<_PhraseDialog> createState() => _PhraseDialogState();
}

class _PhraseDialogState extends ConsumerState<_PhraseDialog> {
  late final _text = TextEditingController(text: widget.phrase?.text ?? '');
  late final _ru = TextEditingController(text: widget.phrase?.translation ?? '');
  late final _tg = TextEditingController(text: widget.phrase?.translationTg ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _ru.dispose();
    _tg.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_text.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(aiRepositoryProvider);
      final phrase = widget.phrase;
      if (phrase == null) {
        await repo.createPhrase(languageId: widget.languageId, text: _text.text.trim(), translation: _ru.text.trim(), translationTg: _tg.text.trim());
      } else {
        await repo.updatePhrase(phrase.id, text: _text.text.trim(), translation: _ru.text.trim(), translationTg: _tg.text.trim());
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить фразу');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.phrase == null ? 'Новая фраза' : 'Фраза'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _text, autofocus: true, decoration: adminInputDecoration(label: 'Фраза (на изучаемом языке)')),
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: _ru, decoration: adminInputDecoration(label: 'Перевод (русский)')),
            const SizedBox(height: AdminMetrics.fieldGap),
            TextField(controller: _tg, decoration: adminInputDecoration(label: 'Перевод (тоҷикӣ)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _save, style: AdminButtonStyles.primary(), child: const Text('Сохранить')),
      ],
    );
  }
}

class _ImportDialog extends ConsumerStatefulWidget {
  const _ImportDialog({required this.languageId});
  final String languageId;

  @override
  ConsumerState<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends ConsumerState<_ImportDialog> {
  final _json = TextEditingController();
  String? _error;
  bool _busy = false;

  static const _example = '[\n  {"text": "Nice to meet you", "translation": "Приятно познакомиться", "translation_tg": "Аз шиносоӣ шодам", "topic": "Знакомство"}\n]';

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    List<Map<String, dynamic>> items;
    try {
      final decoded = jsonDecode(_json.text);
      if (decoded is! List) throw const FormatException('ожидается список [...]');
      items = [for (final e in decoded) Map<String, dynamic>.from(e as Map)];
    } catch (e) {
      setState(() => _error = 'Неверный JSON: $e');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(aiRepositoryProvider).importPhrases(widget.languageId, items);
      if (!mounted) return;
      showSuccessSnack(context, 'Добавлено: ${result.added}, пропущено (уже есть): ${result.skipped}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось импортировать'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Импорт фраз'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Вставьте список фраз в формате JSON. Фразы, которые уже есть, будут пропущены.', style: AdminTypography.caption),
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
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _import, style: AdminButtonStyles.primary(), child: const Text('Импортировать')),
      ],
    );
  }
}
