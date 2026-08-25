import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/api/api_client.dart';
import '../../domain/builder_domain.dart';

/// Mirrors LessonMediaEditor.tsx — a dumb, reusable video/audio slot. The
/// caller supplies the actual upload/remove/reuse actions since legacy and
/// builder-course lessons hit different endpoints for the same operation
/// (see the migration notes' cross-cutting point on that split).
class MediaEditor extends ConsumerStatefulWidget {
  const MediaEditor({
    super.key,
    required this.kind,
    required this.url,
    required this.libraryLoader,
    required this.onUpload,
    required this.onRemove,
    required this.onReuse,
  });

  final String kind; // "video" | "audio"
  final String? url;
  final Future<List<MediaLibraryEntry>> Function() libraryLoader;
  final Future<void> Function(List<int> bytes, String filename) onUpload;
  final Future<void> Function() onRemove;
  final Future<void> Function(String url) onReuse;

  @override
  ConsumerState<MediaEditor> createState() => _MediaEditorState();
}

class _MediaEditorState extends ConsumerState<MediaEditor> {
  bool _busy = false;
  bool _showLibrary = false;
  List<MediaLibraryEntry>? _library;

  Future<void> _pick() async {
    final file = await FilePicker.pickFile(type: widget.kind == 'video' ? FileType.video : FileType.audio);
    if (file == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      await widget.onUpload(bytes, file.name);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleLibrary() async {
    if (_showLibrary) {
      setState(() => _showLibrary = false);
      return;
    }
    setState(() => _showLibrary = true);
    _library ??= (await widget.libraryLoader()).where((e) => e.url != widget.url).toList();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final assetUrl = ref.read(apiClientProvider).assetUrl(widget.url);
    final isVideo = widget.kind == 'video';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assetUrl.isNotEmpty)
          Text(isVideo ? 'Видео загружено' : 'Аудио загружено', style: Theme.of(context).textTheme.bodyMedium)
        else
          const Text('Файл ещё не загружен.'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: _busy ? null : _pick, child: Text(assetUrl.isNotEmpty ? 'Заменить файл' : 'Загрузить файл')),
            OutlinedButton(onPressed: _toggleLibrary, child: Text(_showLibrary ? 'Скрыть библиотеку' : 'Выбрать уже загруженный')),
            if (assetUrl.isNotEmpty)
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await widget.onRemove();
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('Удалить файл'),
              ),
          ],
        ),
        if (_showLibrary) ...[
          const SizedBox(height: 8),
          if (_library == null)
            const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())
          else if (_library!.isEmpty)
            Text('Других ${isVideo ? "видео" : "аудио"} файлов пока нет.')
          else
            Card(
              child: Column(
                children: [
                  for (final entry in _library!)
                    ListTile(
                      dense: true,
                      title: Text(entry.label),
                      onTap: () async {
                        setState(() => _showLibrary = false);
                        await widget.onReuse(entry.url);
                      },
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
