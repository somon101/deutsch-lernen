import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/word_audio_button.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';

/// Mirrors BuilderVocabularyEditor.tsx — per-word rows (edit/delete/audio),
/// a new-word row with cross-lesson library suggestions, and a JSON bulk
/// import section (preview → import, mirroring the two-step backend
/// contract exactly).
class VocabularyEditor extends ConsumerStatefulWidget {
  const VocabularyEditor({super.key, required this.courseId, required this.lessonId, required this.words, required this.onChanged});

  final String courseId;
  final String lessonId;
  final List<AdminVocabWord> words;
  final VoidCallback onChanged;

  @override
  ConsumerState<VocabularyEditor> createState() => _VocabularyEditorState();
}

class _VocabularyEditorState extends ConsumerState<VocabularyEditor> {
  bool _importOpen = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.words.isEmpty) const Text('Слов пока нет — добавьте первое ниже.'),
        for (final w in widget.words) _WordRow(courseId: widget.courseId, lessonId: widget.lessonId, word: w, onChanged: widget.onChanged),
        const Divider(),
        _NewWordRow(courseId: widget.courseId, lessonId: widget.lessonId, onChanged: widget.onChanged),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _importOpen = !_importOpen),
          child: Text(_importOpen ? '▾ Импортировать JSON' : '▸ Импортировать JSON'),
        ),
        if (_importOpen) _JsonImportPanel(courseId: widget.courseId, lessonId: widget.lessonId, onChanged: widget.onChanged),
      ],
    );
  }
}

class _WordRow extends ConsumerStatefulWidget {
  const _WordRow({required this.courseId, required this.lessonId, required this.word, required this.onChanged});
  final String courseId;
  final String lessonId;
  final AdminVocabWord word;
  final VoidCallback onChanged;

  @override
  ConsumerState<_WordRow> createState() => _WordRowState();
}

class _WordRowState extends ConsumerState<_WordRow> {
  late final _german = TextEditingController(text: widget.word.german);
  late final _translation = TextEditingController(text: widget.word.translation);
  late final _pronunciation = TextEditingController(text: widget.word.pronunciation);
  bool _busy = false;
  bool _saved = false;

  @override
  void dispose() {
    _german.dispose();
    _translation.dispose();
    _pronunciation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_german.text.trim().isEmpty || _translation.text.trim().isEmpty || _pronunciation.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _saved = false;
    });
    try {
      await ref.read(builderRepositoryProvider).updateWord(
            widget.courseId,
            widget.lessonId,
            widget.word.id,
            german: _german.text.trim(),
            translation: _translation.text.trim(),
            pronunciation: _pronunciation.text.trim(),
          );
      widget.onChanged();
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить слово');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Удалить слово «${widget.word.german}» из словаря курса?');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).removeWord(widget.courseId, widget.lessonId, widget.word.id);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить слово');
    }
  }

  Future<void> _uploadAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(builderRepositoryProvider).uploadWordAudio(widget.courseId, widget.lessonId, widget.word.id, bytes: bytes, filename: file.name);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить аудио');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAudio() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).removeWordAudio(widget.courseId, widget.lessonId, widget.word.id);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WordAudioButton(word: widget.word.german, audioUrl: widget.word.audioUrl),
          Expanded(child: TextField(controller: _german, decoration: const InputDecoration(labelText: 'Немецкий'), enabled: !_busy)),
          const SizedBox(width: 6),
          Expanded(child: TextField(controller: _translation, decoration: const InputDecoration(labelText: 'Перевод'), enabled: !_busy)),
          const SizedBox(width: 6),
          Expanded(child: TextField(controller: _pronunciation, decoration: const InputDecoration(labelText: 'Транскрипция'), enabled: !_busy)),
          const SizedBox(width: 6),
          IconButton(
            tooltip: widget.word.audioUrl != null ? 'Удалить запись' : 'Загрузить запись',
            icon: Icon(widget.word.audioUrl != null ? Icons.mic_off : Icons.mic, size: 18),
            onPressed: _busy ? null : (widget.word.audioUrl != null ? _removeAudio : _uploadAudio),
          ),
          TextButton(onPressed: _busy ? null : _save, child: Text(_saved ? 'Сохранено' : 'Сохранить')),
          IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: _delete),
        ],
      ),
    );
  }
}

class _NewWordRow extends ConsumerStatefulWidget {
  const _NewWordRow({required this.courseId, required this.lessonId, required this.onChanged});
  final String courseId;
  final String lessonId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_NewWordRow> createState() => _NewWordRowState();
}

class _NewWordRowState extends ConsumerState<_NewWordRow> {
  final _german = TextEditingController();
  final _translation = TextEditingController();
  final _pronunciation = TextEditingController();
  bool _busy = false;
  List<WordLibraryEntry>? _suggestions;
  Timer? _debounce;

  bool get _canSubmit => _german.text.trim().isNotEmpty && _translation.text.trim().isNotEmpty && _pronunciation.text.trim().isNotEmpty;

  @override
  void dispose() {
    _german.dispose();
    _translation.dispose();
    _pronunciation.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onGermanChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _suggestions = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await ref.read(builderRepositoryProvider).searchWordLibrary(value.trim());
      if (mounted) setState(() => _suggestions = results);
    });
  }

  void _pickSuggestion(WordLibraryEntry entry) {
    _german.text = entry.german;
    _translation.text = entry.translation;
    _pronunciation.text = entry.pronunciation;
    setState(() => _suggestions = null);
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).addWord(
            widget.courseId,
            widget.lessonId,
            german: _german.text.trim(),
            translation: _translation.text.trim(),
            pronunciation: _pronunciation.text.trim(),
          );
      _german.clear();
      _translation.clear();
      _pronunciation.clear();
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось добавить слово');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(controller: _german, decoration: const InputDecoration(labelText: 'Немецкий'), onChanged: _onGermanChanged),
            ),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _translation, decoration: const InputDecoration(labelText: 'Перевод'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 6),
            Expanded(child: TextField(controller: _pronunciation, decoration: const InputDecoration(labelText: 'Транскрипция'), onChanged: (_) => setState(() {}))),
            const SizedBox(width: 6),
            ElevatedButton(onPressed: _busy || !_canSubmit ? null : _submit, child: const Text('+ Добавить')),
          ],
        ),
        if (_suggestions != null && _suggestions!.isNotEmpty)
          Card(
            child: Column(
              children: [
                for (final s in _suggestions!)
                  ListTile(
                    dense: true,
                    title: Text('${s.german} — ${s.translation}'),
                    subtitle: const Text('Уже есть в другом уроке — использовать?'),
                    onTap: () => _pickSuggestion(s),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _JsonImportPanel extends ConsumerStatefulWidget {
  const _JsonImportPanel({required this.courseId, required this.lessonId, required this.onChanged});
  final String courseId;
  final String lessonId;
  final VoidCallback onChanged;

  @override
  ConsumerState<_JsonImportPanel> createState() => _JsonImportPanelState();
}

class _JsonImportPanelState extends ConsumerState<_JsonImportPanel> {
  final _text = TextEditingController();
  bool _busy = false;
  String? _error;
  ImportPreview? _preview;
  List<Map<String, String>>? _parsedWords;
  ({int addedCount, List<ImportPreviewItem> skipped})? _result;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _error = null;
      _preview = null;
      _result = null;
    });
    dynamic parsed;
    try {
      parsed = jsonDecode(_text.text);
    } catch (_) {
      setState(() => _error = 'Некорректный JSON: не удалось разобрать текст. Проверьте синтаксис.');
      return;
    }
    if (parsed is! List) {
      setState(() => _error = 'Корневой элемент JSON должен быть массивом.');
      return;
    }
    final words = <Map<String, String>>[];
    for (final item in parsed) {
      if (item is Map) {
        words.add({
          'original': (item['original'] ?? '').toString(),
          'transcription': (item['transcription'] ?? '').toString(),
          'translation': (item['translation'] ?? '').toString(),
        });
      }
    }
    setState(() => _busy = true);
    try {
      final preview = await ref.read(builderRepositoryProvider).previewVocabularyImport(widget.courseId, widget.lessonId, words);
      setState(() {
        _preview = preview;
        _parsedWords = words;
      });
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось проверить JSON'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _newWordsLabel(int n) {
    final mod10 = n % 10;
    final mod100 = n % 100;
    String word;
    if (mod10 == 1 && mod100 != 11) {
      word = 'новое слово';
    } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      word = 'новых слова';
    } else {
      word = 'новых слов';
    }
    return 'Импортировать $n $word';
  }

  Future<void> _import() async {
    if (_parsedWords == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(builderRepositoryProvider).importVocabulary(widget.courseId, widget.lessonId, _parsedWords!);
      setState(() {
        _result = result;
        _preview = null;
        _text.clear();
      });
      widget.onChanged();
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось импортировать слова'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '[{"original":"Hallo","transcription":"халло","translation":"привет"}]',
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(onPressed: _busy || _text.text.trim().isEmpty ? null : _check, child: const Text('Проверить JSON')),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (preview != null) ...[
            const SizedBox(height: 8),
            Text('Всего: ${preview.total} · новых: ${preview.newCount} · дублей: ${preview.duplicateCount}'),
            for (final item in preview.items.where((i) => i.status != 'new'))
              Text('«${item.original}» — ${item.message ?? item.status}', style: Theme.of(context).textTheme.bodySmall),
            if (preview.duplicateCount > 0 && preview.newCount > 0)
              const Text('Дубликаты будут пропущены автоматически — импортируются только новые слова.', style: TextStyle(fontSize: 12)),
            if (preview.newCount > 0) ...[
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _busy ? null : _import, child: Text(_newWordsLabel(preview.newCount))),
            ],
          ],
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text('Добавлено слов: ${_result!.addedCount}.', style: const TextStyle(color: Colors.green)),
            for (final s in _result!.skipped)
              Text('«${s.original}» — ${s.message ?? s.status}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
