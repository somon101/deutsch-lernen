import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/api/api_client.dart';
import '../../../admin_tokens.dart';
import '../../../admin_widgets.dart';
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
    final file = await FilePicker.pickFile(
      type: widget.kind == 'video' ? FileType.video : FileType.audio,
    );
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
    _library ??= (await widget.libraryLoader())
        .where((e) => e.url != widget.url)
        .toList();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final assetUrl = ref.read(apiClientProvider).assetUrl(widget.url);
    final isVideo = widget.kind == 'video';
    final hasFile = assetUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasFile && !isVideo)
          _InlineAudioPlayer(url: assetUrl)
        else if (hasFile)
          Text('Видео загружено', style: AdminTypography.body),
        if (!hasFile)
          Text('Файл ещё не загружен.', style: AdminTypography.body),
        const SizedBox(height: AdminMetrics.fieldGap),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : _pick,
              style: AdminButtonStyles.secondary(),
              child: Text(hasFile ? 'Заменить файл' : 'Загрузить файл'),
            ),
            OutlinedButton(
              onPressed: _toggleLibrary,
              style: AdminButtonStyles.secondary(),
              child: Text(
                _showLibrary ? 'Скрыть библиотеку' : 'Выбрать уже загруженный',
              ),
            ),
            if (hasFile)
              AdminDeleteLink(
                label: 'Удалить файл',
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
              ),
          ],
        ),
        if (_showLibrary) ...[
          const SizedBox(height: AdminMetrics.fieldGap),
          if (_library == null)
            const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(),
            )
          else if (_library!.isEmpty)
            Text(
              'Других ${isVideo ? "видео" : "аудио"} файлов пока нет.',
              style: AdminTypography.caption,
            )
          else
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AdminColors.border),
                borderRadius: BorderRadius.circular(AdminMetrics.blockRadius),
              ),
              child: Column(
                children: [
                  for (final entry in _library!)
                    ListTile(
                      dense: true,
                      title: Text(entry.label, style: AdminTypography.body),
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

/// A compact play/pause + scrubber, mirroring the reference's native
/// `<audio controls>` element (Screenshot 6).
class _InlineAudioPlayer extends StatefulWidget {
  const _InlineAudioPlayer({required this.url});
  final String url;

  @override
  State<_InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<_InlineAudioPlayer> {
  final _player = AudioPlayer();
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onDurationChanged.listen(
      (d) => mounted ? setState(() => _duration = d) : null,
    );
    _player.onPositionChanged.listen(
      (p) => mounted ? setState(() => _position = p) : null,
    );
    _player.onPlayerStateChanged.listen(
      (s) =>
          mounted ? setState(() => _playing = s == PlayerState.playing) : null,
    );
    _player.onPlayerComplete.listen(
      (_) => mounted ? setState(() => _position = Duration.zero) : null,
    );
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
    } else {
      await _player.play(UrlSource(widget.url));
    }
  }

  String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final total = _duration.inMilliseconds > 0
        ? _duration.inMilliseconds.toDouble()
        : 1.0;
    final pos = _position.inMilliseconds.toDouble().clamp(0, total);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AdminColors.blockBg,
        borderRadius: BorderRadius.circular(AdminMetrics.buttonRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: AdminColors.accent,
            ),
            visualDensity: VisualDensity.compact,
            onPressed: _toggle,
          ),
          SizedBox(
            width: 180,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              ),
              child: Slider(
                value: pos.toDouble(),
                max: total,
                activeColor: AdminColors.accent,
                inactiveColor: AdminColors.border,
                onChanged: (v) =>
                    _player.seek(Duration(milliseconds: v.round())),
              ),
            ),
          ),
          Text(
            '${_fmt(_position)} / ${_fmt(_duration)}',
            style: AdminTypography.caption,
          ),
        ],
      ),
    );
  }
}
