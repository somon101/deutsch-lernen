import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/back_guard.dart';
import '../../../../core/widgets/word_audio_button.dart';
import '../../../profile/presentation/profile_tokens.dart';
import '../../admin_tokens.dart';
import '../../admin_widgets.dart';
import '../../widgets/used_filter_chips.dart';
import '../../widgets/admin_feedback.dart';
import '../../widgets/json_file_button.dart';
import '../../course_builder/data/builder_repository.dart';
import '../../course_builder/domain/builder_domain.dart';
import '../../course_builder/domain/taxonomy_domain.dart';
import '../../course_builder/domain/vocabulary_import.dart';

const _pageSize = 30;

/// The admin "Словарь" screen (§ shared dictionary, 2026-09-14) — a single
/// browsable/searchable view over every VocabularyItem in the system,
/// regardless of which lesson it happens to live in. This is a NEW screen,
/// but not a new storage or authoring mechanism: creating a word here
/// still calls BuilderRepository.addWord (the same endpoint the lesson
/// editor's own "+ Добавить" row already used), and editing/deleting a
/// word still calls the same lesson-scoped update/delete endpoints,
/// pointed at the word's own native course/lesson (reported by the list
/// itself). The one genuinely new capability this screen exposes is
/// DELETE /api/builder/vocabulary/{id} — removing a word from the
/// dictionary entirely, which the per-lesson editor deliberately can't do
/// once a word is reused elsewhere.
class AdminVocabularyScreen extends ConsumerStatefulWidget {
  const AdminVocabularyScreen({super.key, this.languageId});

  /// When set, the screen is embedded in a language workspace: this
  /// language is fixed (no language picker anywhere) and there is no back
  /// arrow of its own.
  final String? languageId;

  @override
  ConsumerState<AdminVocabularyScreen> createState() => _AdminVocabularyScreenState();
}

class _AdminVocabularyScreenState extends ConsumerState<AdminVocabularyScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<DictionaryWord> _words = const [];
  int _total = 0;
  int _usedCount = 0;
  int _unusedCount = 0;
  // null = all, true = used in lessons, false = not used.
  bool? _used;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<AdminLanguage> _languages = const [];
  String? _languageId;

  @override
  void initState() {
    super.initState();
    _init();
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
    } catch (_) {
      // Without the language list the dictionary still loads, just unfiltered.
    }
    await _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      if (reset) {
        _loading = true;
        _error = null;
      } else {
        _loadingMore = true;
      }
    });
    try {
      final page = await ref.read(builderRepositoryProvider).listDictionaryWords(
            query: _query.isEmpty ? null : _query,
            languageId: _languageId,
            used: _used,
            limit: _pageSize,
            offset: reset ? 0 : _words.length,
          );
      if (!mounted) return;
      setState(() {
        _words = reset ? page.words : [..._words, ...page.words];
        _total = page.total;
        _usedCount = page.usedCount;
        _unusedCount = page.unusedCount;
      });
    } catch (e) {
      if (mounted && reset) setState(() => _error = adminErrorMessage(e, 'Не удалось загрузить словарь'));
    } finally {
      if (mounted) setState(() => reset ? _loading = false : _loadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = value.trim();
      _load(reset: true);
    });
  }

  Future<void> _openCreateSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => Theme(
        data: lightTheme,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: _CreateWordSheet(languages: _languages, initialLanguageId: _languageId),
        ),
      ),
    );
    if (created == true) _load(reset: true);
  }

  Future<void> _openImportSheet() async {
    final languageId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => Theme(
        data: lightTheme,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: _ImportWordsSheet(languages: _languages, initialLanguageId: _languageId),
        ),
      ),
    );
    if (languageId == null) return;
    if (languageId != _languageId) setState(() => _languageId = languageId);
    _load(reset: true);
  }

  Future<void> _openEditSheet(DictionaryWord word) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) => Theme(
        data: lightTheme,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
          child: _EditWordSheet(word: word),
        ),
      ),
    );
    if (changed == true) _load(reset: true);
  }

  Future<void> _delete(DictionaryWord word) async {
    final ok = await confirmDialog(context, title: 'Удалить слово «${word.word}» из словаря?');
    if (!ok) return;
    try {
      await ref.read(builderRepositoryProvider).deleteWordGlobally(word.wordId);
      _load(reset: true);
      return;
    } catch (e) {
      if (e is ApiException && e.statusCode == 409) {
        if (!mounted) return;
        final forceOk = await confirmDialog(context, title: 'Слово используется', message: e.message, confirmLabel: 'Удалить всё равно');
        if (!forceOk) return;
        try {
          await ref.read(builderRepositoryProvider).deleteWordGlobally(word.wordId, force: true);
          _load(reset: true);
        } catch (e2) {
          if (mounted) showErrorSnack(context, e2, 'Не удалось удалить слово');
        }
        return;
      }
      if (mounted) showErrorSnack(context, e, 'Не удалось удалить слово');
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
            title: Text('Словарь', style: AdminTypography.pageTitle),
            automaticallyImplyLeading: false,
            leading: widget.languageId != null ? null : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go('/')),
            actions: [
              TextButton.icon(
                onPressed: _openImportSheet,
                style: AdminButtonStyles.text(),
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Импорт JSON'),
              ),
              TextButton.icon(
                onPressed: _openCreateSheet,
                style: AdminButtonStyles.text(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Новое слово'),
              ),
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
                          width: 170,
                          child: DropdownButtonFormField<String>(
                            key: ValueKey(_languageId),
                            initialValue: _languageId,
                            isExpanded: true,
                            decoration: adminInputDecoration(label: 'Изучаемый язык'),
                            items: [for (final l in _languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
                            onChanged: (v) {
                              if (v == null || v == _languageId) return;
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
                          decoration: adminInputDecoration(hint: 'Поиск по слову или переводу…').copyWith(
                            prefixIcon: const Icon(Icons.search, size: 18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: UsedFilterChips(
                    value: _used,
                    usedCount: _usedCount,
                    unusedCount: _unusedCount,
                    onChanged: (v) {
                      setState(() => _used = v);
                      _load(reset: true);
                    },
                  ),
                ),
                if (!_loading && _error == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Показано слов: $_total', style: AdminTypography.caption),
                    ),
                  ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(child: Text(_error!, style: AdminTypography.body))
                          : _words.isEmpty
                              ? Center(
                                  child: Text(
                                    _query.isEmpty ? 'Слов пока нет.' : 'Ничего не найдено по запросу «$_query».',
                                    style: AdminTypography.body,
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.fromLTRB(16, 4, 16, AdminMetrics.cardGap + bottomBarClearance(context)),
                                  itemCount: _words.length + 1,
                                  itemBuilder: (context, index) {
                                    if (index == _words.length) {
                                      if (_words.length >= _total) return const SizedBox.shrink();
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                        child: Center(
                                          child: _loadingMore
                                              ? const CircularProgressIndicator()
                                              : OutlinedButton(
                                                  onPressed: () => _load(),
                                                  style: AdminButtonStyles.secondary(),
                                                  child: const Text('Показать ещё'),
                                                ),
                                        ),
                                      );
                                    }
                                    final w = _words[index];
                                    return _WordCard(
                                      word: w,
                                      onEdit: () => _openEditSheet(w),
                                      onDelete: () => _delete(w),
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

class _WordCard extends ConsumerWidget {
  const _WordCard({required this.word, required this.onEdit, required this.onDelete});
  final DictionaryWord word;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageUrl = ref.read(apiClientProvider).assetUrl(word.imageUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: AdminCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(imageUrl, width: 44, height: 44, fit: BoxFit.cover, errorBuilder: (c, e, s) => const _ImagePlaceholder()),
              )
            else
              const _ImagePlaceholder(),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: word.word, style: AdminTypography.cardTitle),
                              TextSpan(text: '  —  ${word.translation}', style: AdminTypography.body),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      WordAudioButton(word: word.word, audioUrl: word.audioUrl, size: 18),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      if (word.pronunciation != null && word.pronunciation!.isNotEmpty)
                        Text('[${word.pronunciation}]', style: AdminTypography.caption),
                      if (word.categoryName != null) Text(word.categoryName!, style: AdminTypography.caption),
                      Text(
                        word.usedInLessonsCount > 1 ? 'используется в ${word.usedInLessonsCount} уроках' : 'используется в 1 уроке',
                        style: AdminTypography.caption.copyWith(
                          color: word.usedInLessonsCount > 1 ? AdminColors.accent : AdminColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(tooltip: 'Редактировать', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
            AdminDeleteLink(onPressed: onDelete),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: AdminColors.blockBg, borderRadius: BorderRadius.circular(6)),
        child: const Icon(Icons.image_not_supported_outlined, size: 16, color: AdminColors.textMuted),
      );
}

/// Shared category picker: a horizontal chip list of existing categories
/// (§ word cards, 2026-08-31 — get_or_create_category already reuses an
/// existing category by name, this is just the first UI that offers one
/// to pick from) plus free-text entry for a brand new category name.
class _CategoryField extends ConsumerStatefulWidget {
  const _CategoryField({required this.controller});
  final TextEditingController controller;

  @override
  ConsumerState<_CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends ConsumerState<_CategoryField> {
  List<AdminCategory>? _categories;

  @override
  void initState() {
    super.initState();
    ref.read(builderRepositoryProvider).listCategories().then((c) {
      if (mounted) setState(() => _categories = c);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: widget.controller, decoration: adminInputDecoration(label: 'Категория (необязательно)')),
        if (categories != null && categories.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in categories)
                ActionChip(
                  label: Text(c.name, style: AdminTypography.caption),
                  onPressed: () => setState(() => widget.controller.text = c.name),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// "Создать новое слово" (§ shared dictionary, 2026-09-14) — collects the
/// same fields the lesson editor's own new-word row already collects
/// (german/translation/pronunciation/category), plus which course+lesson
/// to anchor it to (every VocabularyItem still needs one native lesson —
/// this screen doesn't change that, it just lets the admin pick it here
/// instead of having to first open that lesson). Submits through the
/// EXACT SAME addWord call the lesson editor uses; the word becomes
/// immediately reusable elsewhere via the constructor's "выбрать
/// существующее слово" search once created.
class _CreateWordSheet extends ConsumerStatefulWidget {
  const _CreateWordSheet({required this.languages, this.initialLanguageId});
  final List<AdminLanguage> languages;
  final String? initialLanguageId;
  @override
  ConsumerState<_CreateWordSheet> createState() => _CreateWordSheetState();
}

class _CreateWordSheetState extends ConsumerState<_CreateWordSheet> {
  final _german = TextEditingController();
  final _translation = TextEditingController();
  final _translationTg = TextEditingController();
  final _pronunciation = TextEditingController();
  final _category = TextEditingController();
  String? _languageId;
  Uint8List? _imageBytes;
  String? _imageFilename;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _languageId = widget.initialLanguageId;
  }

  @override
  void dispose() {
    _german.dispose();
    _translation.dispose();
    _translationTg.dispose();
    _pronunciation.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFilename = file.name;
    });
  }

  bool get _canSubmit =>
      _german.text.trim().isNotEmpty &&
      _translation.text.trim().isNotEmpty &&
      _translationTg.text.trim().isNotEmpty &&
      _languageId != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = ref.read(builderRepositoryProvider);
      final created = await repo.addDictionaryWord(
        languageId: _languageId!,
        german: _german.text.trim(),
        translation: _translation.text.trim(),
        translationTg: _translationTg.text.trim(),
        pronunciation: _pronunciation.text.trim(),
        categoryName: _category.text.trim().isEmpty ? null : _category.text.trim(),
      );
      if (_imageBytes != null && _imageFilename != null) {
        await repo.uploadWordImage(created.courseId, created.lessonId, created.id, bytes: _imageBytes!, filename: _imageFilename!);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось создать слово'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Новое слово', style: AdminTypography.cardTitle),
          const SizedBox(height: 4),
          Text('Слово попадёт в словарь выбранного языка. В урок его можно добавить потом из конструктора.', style: AdminTypography.caption),
          const SizedBox(height: AdminMetrics.fieldGap),
          if (widget.languages.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _languageId,
              decoration: adminInputDecoration(label: 'Изучаемый язык'),
              items: [for (final l in widget.languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) setState(() => _languageId = v);
                    },
            ),
            const SizedBox(height: AdminMetrics.fieldGap),
          ],
          TextField(controller: _german, decoration: adminInputDecoration(label: 'Слово'), onChanged: (_) => setState(() {})),
          const SizedBox(height: AdminMetrics.fieldGap),
          Row(
            children: [
              Expanded(child: TextField(controller: _translation, decoration: adminInputDecoration(label: 'Перевод (русский)'), onChanged: (_) => setState(() {}))),
              const SizedBox(width: 6),
              Expanded(child: TextField(controller: _translationTg, decoration: adminInputDecoration(label: 'Перевод (тоҷикӣ)'), onChanged: (_) => setState(() {}))),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _pronunciation, decoration: adminInputDecoration(label: 'Транскрипция (необязательно)'), onChanged: (_) => setState(() {})),
          const SizedBox(height: AdminMetrics.fieldGap),
          _CategoryField(controller: _category),
          const SizedBox(height: AdminMetrics.fieldGap),
          Row(
            children: [
              if (_imageBytes != null) ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.memory(_imageBytes!, width: 40, height: 40, fit: BoxFit.cover)),
              if (_imageBytes != null) const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                style: AdminButtonStyles.secondary(),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(_imageBytes == null ? 'Добавить фото (необязательно)' : 'Заменить фото'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy || !_canSubmit ? null : _submit,
              style: AdminButtonStyles.primary(),
              child: Text(_busy ? 'Создаём…' : 'Создать слово'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editing an existing word (§ shared dictionary, 2026-09-14) — same
/// fields/actions as the lesson editor's own word row
/// (course_builder/presentation/widgets/vocabulary_editor.dart's _WordRow),
/// just in a standalone sheet reached from the dictionary list instead of
/// from inside one specific lesson. Calls the exact same updateWord/
/// uploadWordImage/uploadWordAudio endpoints, addressed at the word's own
/// native course/lesson (word.courseId/word.lessonId) — editing here
/// never creates a new word or a new link.
class _EditWordSheet extends ConsumerStatefulWidget {
  const _EditWordSheet({required this.word});
  final DictionaryWord word;

  @override
  ConsumerState<_EditWordSheet> createState() => _EditWordSheetState();
}

class _EditWordSheetState extends ConsumerState<_EditWordSheet> {
  late final _german = TextEditingController(text: widget.word.word);
  late final _translation = TextEditingController(text: widget.word.translation);
  late final _translationTg = TextEditingController(text: widget.word.translationTg ?? '');
  late final _pronunciation = TextEditingController(text: widget.word.pronunciation ?? '');
  late final _category = TextEditingController(text: widget.word.categoryName ?? '');
  bool _busy = false;
  String? _error;
  String? _imageUrl;
  String? _audioUrl;

  @override
  void initState() {
    super.initState();
    _imageUrl = widget.word.imageUrl;
    _audioUrl = widget.word.audioUrl;
  }

  @override
  void dispose() {
    _german.dispose();
    _translation.dispose();
    _translationTg.dispose();
    _pronunciation.dispose();
    _category.dispose();
    super.dispose();
  }

  String get _courseId => widget.word.courseId;
  String get _lessonId => widget.word.lessonId;
  String get _wordId => widget.word.wordId;

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(builderRepositoryProvider).updateWord(
            _courseId,
            _lessonId,
            _wordId,
            german: _german.text.trim(),
            translation: _translation.text.trim(),
            pronunciation: _pronunciation.text.trim(),
            categoryName: _category.text.trim().isEmpty ? null : _category.text.trim(),
          );
      final tg = _translationTg.text.trim();
      if (tg.isNotEmpty && tg != (widget.word.translationTg ?? '')) {
        await ref.read(builderRepositoryProvider).setVocabularyTranslation(_courseId, _lessonId, _wordId, 'tg', tg);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _error = adminErrorMessage(e, 'Не удалось сохранить слово'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(builderRepositoryProvider).uploadWordImage(_courseId, _lessonId, _wordId, bytes: bytes, filename: file.name);
      final res = await ref.read(builderRepositoryProvider).listDictionaryWords(query: _german.text.trim());
      final matches = res.words.where((w) => w.wordId == _wordId);
      final fresh = matches.isEmpty ? null : matches.first;
      if (mounted) setState(() => _imageUrl = fresh?.imageUrl);
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить фото');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeImage() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).removeWordImage(_courseId, _lessonId, _wordId);
      if (mounted) setState(() => _imageUrl = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadAudio() async {
    final file = await FilePicker.pickFile(type: FileType.audio);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await ref.read(builderRepositoryProvider).uploadWordAudio(_courseId, _lessonId, _wordId, bytes: bytes, filename: file.name);
      if (mounted) setState(() => _audioUrl = 'uploaded');
    } catch (e) {
      if (mounted) showErrorSnack(context, e, 'Не удалось загрузить запись');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeAudio() async {
    setState(() => _busy = true);
    try {
      await ref.read(builderRepositoryProvider).removeWordAudio(_courseId, _lessonId, _wordId);
      if (mounted) setState(() => _audioUrl = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = ref.read(apiClientProvider).assetUrl(_imageUrl);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Редактировать слово', style: AdminTypography.cardTitle)),
              if (widget.word.usedInLessonsCount > 1)
                Text('в ${widget.word.usedInLessonsCount} уроках', style: AdminTypography.caption.copyWith(color: AdminColors.accent)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Изменения сразу видны везде, где переиспользуется это слово.',
            style: AdminTypography.caption,
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _german, decoration: adminInputDecoration(label: 'Слово'), enabled: !_busy),
          const SizedBox(height: AdminMetrics.fieldGap),
          Row(
            children: [
              Expanded(child: TextField(controller: _translation, decoration: adminInputDecoration(label: 'Перевод (русский)'), enabled: !_busy)),
              const SizedBox(width: 6),
              Expanded(child: TextField(controller: _translationTg, decoration: adminInputDecoration(label: 'Перевод (тоҷикӣ)'), enabled: !_busy)),
            ],
          ),
          const SizedBox(height: AdminMetrics.fieldGap),
          TextField(controller: _pronunciation, decoration: adminInputDecoration(label: 'Транскрипция'), enabled: !_busy),
          const SizedBox(height: AdminMetrics.fieldGap),
          _CategoryField(controller: _category),
          const SizedBox(height: AdminMetrics.fieldGap),
          Row(
            children: [
              if (imageUrl.isNotEmpty) ...[
                ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(imageUrl, width: 40, height: 40, fit: BoxFit.cover)),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickImage,
                style: AdminButtonStyles.secondary(),
                icon: const Icon(Icons.image_outlined, size: 16),
                label: Text(_imageUrl == null ? 'Загрузить фото' : 'Заменить фото'),
              ),
              if (_imageUrl != null) IconButton(tooltip: 'Удалить фото', icon: const Icon(Icons.close, size: 16), onPressed: _busy ? null : _removeImage),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : (_audioUrl != null ? _removeAudio : _uploadAudio),
                style: AdminButtonStyles.secondary(),
                icon: Icon(_audioUrl != null ? Icons.mic_off : Icons.mic, size: 16),
                label: Text(_audioUrl != null ? 'Удалить запись' : 'Загрузить запись'),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: AdminButtonStyles.primary(),
              child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}


/// "Импорт JSON" on the dictionary screen: pick the studied language, paste
/// or load a .json file. Words go straight into that language's dictionary
/// (no course or lesson); ones already there are skipped. Pops the
/// language id on success.
class _ImportWordsSheet extends ConsumerStatefulWidget {
  const _ImportWordsSheet({required this.languages, this.initialLanguageId});
  final List<AdminLanguage> languages;
  final String? initialLanguageId;

  @override
  ConsumerState<_ImportWordsSheet> createState() => _ImportWordsSheetState();
}

class _ImportWordsSheetState extends ConsumerState<_ImportWordsSheet> {
  final _json = TextEditingController();
  String? _languageId;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _languageId = widget.initialLanguageId;
  }

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    if (_json.text.trim().isEmpty) {
      setState(() => _error = 'Вставьте JSON или загрузите файл .json');
      return;
    }
    final parse = parseVocabularyImport(_json.text);
    if (parse.error != null) {
      setState(() => _error = parse.error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(builderRepositoryProvider).importDictionaryWords(_languageId!, parse.words);
      if (!mounted) return;
      showSuccessSnack(context, 'Добавлено: ${result.addedCount}, пропущено (уже есть): ${result.skipped.length}');
      Navigator.pop(context, _languageId);
    } catch (e) {
      if (mounted) setState(() => _error = adminErrorMessage(e, 'Не удалось импортировать слова'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Импорт слов из JSON', style: AdminTypography.cardTitle),
          const SizedBox(height: AdminMetrics.fieldGap),
          if (widget.languages.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _languageId,
              decoration: adminInputDecoration(label: 'Для какого языка импортируем'),
              items: [for (final l in widget.languages) DropdownMenuItem(value: l.id, child: Text(l.name))],
              onChanged: _busy ? null : (v) => setState(() => _languageId = v ?? _languageId),
            ),
            const SizedBox(height: AdminMetrics.fieldGap),
          ],
          Text(
            'Обязательны "original", "translation" (русский) и "translation_tg" (тоҷикӣ); "transcription" — по желанию. '
            'Слова, которые уже есть в словаре этого языка, будут пропущены.',
            style: AdminTypography.caption,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: JsonFileButton(
              enabled: !_busy,
              onLoaded: (text) => setState(() {
                _json.text = text;
                _error = null;
              }),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _json,
            minLines: 6,
            maxLines: 14,
            style: AdminTypography.mono,
            onChanged: (_) => setState(() {}),
            decoration: adminInputDecoration(hint: vocabularyImportExample),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: AdminColors.danger, fontSize: 12)),
            ),
          const SizedBox(height: AdminMetrics.fieldGap),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _busy || _languageId == null ? null : _import,
              style: AdminButtonStyles.primary(),
              child: Text(_busy ? 'Импортируем…' : 'Импортировать'),
            ),
          ),
        ],
      ),
    );
  }
}
