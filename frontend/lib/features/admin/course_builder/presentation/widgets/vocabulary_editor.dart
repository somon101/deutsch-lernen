import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/widgets/word_audio_button.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
import '../../../widgets/admin_feedback.dart';
import '../../data/builder_repository.dart';
import '../../domain/builder_domain.dart';
import '../../domain/vocabulary_import.dart';

/// Mirrors BuilderVocabularyEditor.tsx — per-word rows (edit/delete/audio),
/// a new-word row with cross-lesson library suggestions, and a JSON bulk
/// import section (preview → import, mirroring the two-step backend
/// contract exactly).
class VocabularyEditor extends ConsumerStatefulWidget {
  const VocabularyEditor({
    super.key,
    required this.courseId,
    required this.lessonId,
    required this.words,
    required this.onChanged,
  });

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
        if (widget.words.isEmpty)
          Text(
            'Слов пока нет — добавьте первое ниже.',
            style: AdminTypography.caption,
          ),
        for (final w in widget.words)
          _WordRow(
            courseId: widget.courseId,
            lessonId: widget.lessonId,
            word: w,
            onChanged: widget.onChanged,
          ),
        const Divider(height: 20, color: AdminColors.border),
        _NewWordRow(
          courseId: widget.courseId,
          lessonId: widget.lessonId,
          onChanged: widget.onChanged,
        ),
        const SizedBox(height: AdminMetrics.fieldGap),
        TextButton(
          onPressed: () => setState(() => _importOpen = !_importOpen),
          style: AdminButtonStyles.text(),
          child: Text(
            _importOpen ? '▾ Импортировать JSON' : '▸ Импортировать JSON',
          ),
        ),
        if (_importOpen)
          _JsonImportPanel(
            courseId: widget.courseId,
            lessonId: widget.lessonId,
            onChanged: widget.onChanged,
          ),
      ],
    );
  }
}

class _WordRow extends ConsumerStatefulWidget {
  const _WordRow({
    required this.courseId,
    required this.lessonId,
    required this.word,
    required this.onChanged,
  });
  final String courseId;
  final String lessonId;
  final AdminVocabWord word;
  final VoidCallback onChanged;

  @override
  ConsumerState<_WordRow> createState() => _WordRowState();
}

class _WordRowState extends ConsumerState<_WordRow> {
  late final _german = TextEditingController(text: widget.word.german);
  late final _translation = TextEditingController(
    text: widget.word.translation,
  );
  late final _pronunciation = TextEditingController(
    text: widget.word.pronunciation,
  );
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
    if (_german.text.trim().isEmpty ||
        _translation.text.trim().isEmpty ||
        _pronunciation.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _saved = false;
    });
    try {
      await ref
          .read(builderRepositoryProvider)
          .updateWord(
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
    final ok = await confirmDialog(
      context,
      title: 'Удалить слово «${widget.word.german}» из словаря курса?',
    );
    if (!ok) return;
    try {
      await ref
          .read(builderRepositoryProvider)
          .removeWord(widget.courseId, widget.lessonId, widget.word.id);
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
      await ref
          .read(builderRepositoryProvider)
          .uploadWordAudio(
            widget.courseId,
            widget.lessonId,
            widget.word.id,
            bytes: bytes,
            filename: file.name,
          );
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
      await ref
          .read(builderRepositoryProvider)
          .removeWordAudio(widget.courseId, widget.lessonId, widget.word.id);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref
          .read(builderRepositoryProvider)
          .uploadWordImage(
            widget.courseId,
            widget.lessonId,
            widget.word.id,
            bytes: bytes,
            filename: file.name,
          );
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить фото');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(builderRepositoryProvider)
          .removeWordImage(widget.courseId, widget.lessonId, widget.word.id);
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The base `translation` field above IS the Russian text (§ course
  /// content language, 2026-09-04) — this only ever edits the Tajik
  /// variant, kept as a small dialog rather than a permanent 4th field so
  /// the row's existing layout is untouched for the common case.
  Future<void> _editTajikTranslation() async {
    final controller = TextEditingController(text: widget.word.translations['tg'] ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Тоҷикӣ: ${widget.word.german}'),
        content: TextField(controller: controller, autofocus: true, decoration: adminInputDecoration(label: 'Перевод (тоҷикӣ)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (result == null || result.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).setVocabularyTranslation(widget.courseId, widget.lessonId, widget.word.id, 'tg', result);
      widget.onChanged();
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось сохранить перевод');
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
          WordAudioButton(
            word: widget.word.german,
            audioUrl: widget.word.audioUrl,
          ),
          Expanded(
            child: TextField(
              controller: _german,
              decoration: adminInputDecoration(label: 'Немецкий'),
              enabled: !_busy,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _translation,
              decoration: adminInputDecoration(label: 'Перевод'),
              enabled: !_busy,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _pronunciation,
              decoration: adminInputDecoration(label: 'Транскрипция'),
              enabled: !_busy,
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: widget.word.audioUrl != null
                ? 'Удалить запись'
                : 'Загрузить запись',
            icon: Icon(
              widget.word.audioUrl != null ? Icons.mic_off : Icons.mic,
              size: 18,
            ),
            color: AdminColors.textSecondary,
            onPressed: _busy
                ? null
                : (widget.word.audioUrl != null ? _removeAudio : _uploadAudio),
          ),
          IconButton(
            tooltip: widget.word.imageUrl != null
                ? 'Удалить фото'
                : 'Загрузить фото',
            icon: Icon(
              widget.word.imageUrl != null
                  ? Icons.image_not_supported_outlined
                  : Icons.image_outlined,
              size: 18,
            ),
            color: AdminColors.textSecondary,
            onPressed: _busy
                ? null
                : (widget.word.imageUrl != null ? _removeImage : _uploadImage),
          ),
          IconButton(
            tooltip: widget.word.translations.containsKey('tg') ? 'Тоҷикӣ: есть перевод' : 'Тоҷикӣ: нет перевода',
            icon: Icon(
              Icons.translate,
              size: 18,
              color: widget.word.translations.containsKey('tg') ? AdminColors.success : AdminColors.textSecondary,
            ),
            onPressed: _busy ? null : _editTajikTranslation,
          ),
          TextButton(
            onPressed: _busy ? null : _save,
            style: AdminButtonStyles.text(),
            child: Text(_saved ? 'Сохранено' : 'Сохранить'),
          ),
          AdminDeleteLink(onPressed: _delete),
        ],
      ),
    );
  }
}

class _NewWordRow extends ConsumerStatefulWidget {
  const _NewWordRow({
    required this.courseId,
    required this.lessonId,
    required this.onChanged,
  });
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

  bool get _canSubmit =>
      _german.text.trim().isNotEmpty &&
      _translation.text.trim().isNotEmpty &&
      _pronunciation.text.trim().isNotEmpty;

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
      final results = await ref
          .read(builderRepositoryProvider)
          .searchWordLibrary(value.trim());
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
      await ref
          .read(builderRepositoryProvider)
          .addWord(
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
              child: TextField(
                controller: _german,
                decoration: adminInputDecoration(label: 'Немецкий'),
                onChanged: _onGermanChanged,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _translation,
                decoration: adminInputDecoration(label: 'Перевод'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _pronunciation,
                decoration: adminInputDecoration(label: 'Транскрипция'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _busy || !_canSubmit ? null : _submit,
              style: AdminButtonStyles.primary(),
              child: const Text('+ Добавить'),
            ),
          ],
        ),
        if (_suggestions != null && _suggestions!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            decoration: BoxDecoration(
              border: Border.all(color: AdminColors.border),
              borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
            ),
            child: Column(
              children: [
                for (final s in _suggestions!)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${s.german} — ${s.translation}',
                      style: AdminTypography.body,
                    ),
                    subtitle: Text(
                      'Уже есть в другом уроке — использовать?',
                      style: AdminTypography.caption,
                    ),
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
  const _JsonImportPanel({
    required this.courseId,
    required this.lessonId,
    required this.onChanged,
  });
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
    final parse = parseVocabularyImport(_text.text);
    if (parse.error != null) {
      setState(() => _error = parse.error);
      return;
    }
    final words = parse.words;

    setState(() => _busy = true);
    try {
      final preview = await ref
          .read(builderRepositoryProvider)
          .previewVocabularyImport(widget.courseId, widget.lessonId, words);
      setState(() {
        _preview = preview;
        _parsedWords = words;
      });
    } catch (e) {
      setState(
        () => _error = adminErrorMessage(e, 'Не удалось проверить JSON'),
      );
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
      final result = await ref
          .read(builderRepositoryProvider)
          .importVocabulary(widget.courseId, widget.lessonId, _parsedWords!);
      setState(() {
        _result = result;
        _preview = null;
        _text.clear();
      });
      widget.onChanged();
    } catch (e) {
      setState(
        () => _error = adminErrorMessage(e, 'Не удалось импортировать слова'),
      );
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
          // Stays on screen while the teacher types. The hint inside the
          // field vanished at the first keystroke — exactly when the format
          // is needed most.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AdminColors.blockBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AdminColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Все три поля обязательны:', style: AdminTypography.fieldLabel),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(vocabularyImportExample, style: AdminTypography.mono),
                ),
              ],
            ),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(
            controller: _text,
            maxLines: 8,
            style: AdminTypography.mono,
            decoration: adminInputDecoration(
              hint: '[{"original":"Hallo","transcription":"халло","translation":"привет"}]',
            ),
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              onPressed: _busy || _text.text.trim().isEmpty ? null : _check,
              style: AdminButtonStyles.secondary(),
              child: const Text('Проверить JSON'),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: const TextStyle(color: AdminColors.danger, fontSize: 12),
              ),
            ),
          if (preview != null) ...[
            const SizedBox(height: 8),
            Text(
              'Всего: ${preview.total} · новых: ${preview.newCount} · дублей: ${preview.duplicateCount}',
              style: AdminTypography.body,
            ),
            for (final item in preview.items.where((i) => i.status != 'new'))
              Text(
                '«${item.original}» — ${item.message ?? item.status}',
                style: AdminTypography.caption,
              ),
            if (preview.duplicateCount > 0 && preview.newCount > 0)
              Text(
                'Дубликаты будут пропущены автоматически — импортируются только новые слова.',
                style: AdminTypography.caption,
              ),
            if (preview.newCount > 0) ...[
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _import,
                style: AdminButtonStyles.primary(),
                child: Text(_newWordsLabel(preview.newCount)),
              ),
            ],
          ],
          if (_result != null) ...[
            const SizedBox(height: 8),
            Text(
              'Добавлено слов: ${_result!.addedCount}.',
              style: const TextStyle(color: AdminColors.success, fontSize: 14),
            ),
            for (final s in _result!.skipped)
              Text(
                '«${s.original}» — ${s.message ?? s.status}',
                style: const TextStyle(color: AdminColors.danger, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }
}
