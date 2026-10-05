import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/back_guard.dart';
import '../../admin/admin_tokens.dart';
import '../../admin/widgets/admin_feedback.dart';
import '../../profile/presentation/profile_tokens.dart';
import '../data/video_lessons_repository.dart';
import '../domain/characters.dart';
import '../domain/performance.dart';
import '../domain/speech_timeline.dart';

/// Video constructor for one video lesson: speech source on the left
/// (audio upload, or text voiced on the server), a live phone-shaped
/// preview on the right where the character's mouth follows the speech
/// timeline in sync with the audio — no export needed.
class VideoLessonEditorScreen extends ConsumerStatefulWidget {
  const VideoLessonEditorScreen({super.key, required this.courseId, required this.videoId});
  final String courseId;
  final String videoId;

  @override
  ConsumerState<VideoLessonEditorScreen> createState() => _VideoLessonEditorScreenState();
}

class _VideoLessonEditorScreenState extends ConsumerState<VideoLessonEditorScreen> with SingleTickerProviderStateMixin {
  VideoLessonData? _lesson;
  String? _loadError;
  bool _busy = false;
  String _mode = 'audio';
  final _title = TextEditingController();
  final _text = TextEditingController();
  List<TtsVoice> _voices = const [];
  String? _voice;

  Player? _player;
  final _subs = <StreamSubscription<dynamic>>[];
  String? _openedUrl;
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _lastPosition = Duration.zero;
  final _sinceLastPosition = Stopwatch();
  int _positionMs = 0;
  CharacterPose _pose = CharacterPose.rest;
  Performance? _performance;
  AnimationSettings _settings = const AnimationSettings();
  Timer? _settingsSave;
  String? _playerError;
  late final Ticker _ticker;

  VideoLessonsRepository get _repo => ref.read(videoLessonsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _load();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _settingsSave?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    _title.dispose();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([_repo.get(widget.courseId, widget.videoId), _repo.voices()]);
      final lesson = results[0] as VideoLessonData;
      final voices = results[1] as List<TtsVoice>;
      if (!mounted) return;
      setState(() {
        _voices = voices;
        _apply(lesson, resetInputs: true);
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = adminErrorMessage(e, 'Не удалось открыть видеоурок'));
    }
  }

  void _apply(VideoLessonData lesson, {bool resetInputs = false}) {
    _lesson = lesson;
    if (resetInputs) {
      _title.text = lesson.title;
      _text.text = lesson.text ?? '';
      _mode = lesson.sourceType;
      _voice = lesson.voice ?? (_voices.isNotEmpty ? _voices.first.id : null);
      _settings = lesson.animationSettings;
    }
    _rebuildPerformance();
    _openAudio(lesson.audioUrl);
  }

  /// One performance per (timeline, settings): rebuilt only when either
  /// changes, then evaluated every frame at the audio position.
  void _rebuildPerformance() {
    _performance = Performance(_lesson?.timeline, _settings, seed: widget.videoId.hashCode);
    _pose = _performance!.poseAt(_positionMs);
  }

  // ---------------------------------------------------------------- player

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = Player();
    _player = p;
    _subs.addAll([
      p.stream.playing.listen((v) {
        if (!mounted) return;
        setState(() => _playing = v);
        _markPosition(p.state.position);
      }),
      p.stream.position.listen(_markPosition),
      p.stream.duration.listen((d) => mounted ? setState(() => _duration = d) : null),
      p.stream.completed.listen((done) {
        if (done && mounted) setState(() => _playing = false);
      }),
      p.stream.error.listen((e) {
        if (mounted) setState(() => _playerError = 'Не удалось воспроизвести аудио: $e');
      }),
    ]);
    return p;
  }

  void _markPosition(Duration d) {
    _lastPosition = d;
    _sinceLastPosition
      ..reset()
      ..start();
  }

  void _openAudio(String? path) {
    final url = _repo.audioUrl(path);
    if (url.isEmpty || url == _openedUrl) return;
    _openedUrl = url;
    _playerError = null;
    _ensurePlayer().open(Media(url), play: false);
    _markPosition(Duration.zero);
  }

  /// Every frame: where in the audio are we (last reported position plus
  /// the time since it was reported, so motion doesn't step at the
  /// position stream's rate), and the character's pose at that moment.
  /// The pose depends only on the position, so Pause freezes everything
  /// and Replay starts the same performance from the beginning.
  void _onTick(Duration _) {
    final timeline = _lesson?.timeline;
    var ms = _lastPosition.inMilliseconds;
    if (_playing) ms += _sinceLastPosition.elapsedMilliseconds;
    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : (timeline?.durationMs ?? 0);
    if (maxMs > 0) ms = ms.clamp(0, maxMs);
    if (ms == _positionMs && _performance != null) return;
    setState(() {
      _positionMs = ms;
      _pose = _performance?.poseAt(ms) ?? CharacterPose.rest;
    });
  }

  Future<void> _play() async {
    final p = _player;
    if (p == null) return;
    final total = _duration.inMilliseconds;
    if (total > 0 && _lastPosition.inMilliseconds >= total - 50) await p.seek(Duration.zero);
    await p.play();
  }

  Future<void> _pause() async => _player?.pause();

  Future<void> _replay() async {
    final p = _player;
    if (p == null) return;
    await p.seek(Duration.zero);
    _markPosition(Duration.zero);
    await p.play();
  }

  void _changeSettings(AnimationSettings next) {
    setState(() {
      _settings = next;
      _rebuildPerformance();
    });
    _settingsSave?.cancel();
    _settingsSave = Timer(const Duration(milliseconds: 600), () async {
      try {
        await _repo.update(widget.courseId, widget.videoId, {'animationSettings': next.toJson()});
      } catch (e) {
        if (mounted) showErrorSnack(context, e, 'Не удалось сохранить настройки анимации');
      }
    });
  }

  Future<void> _reanalyze() async {
    _openedUrl = null;
    await _run(() => _repo.reanalyze(widget.courseId, widget.videoId), 'Не удалось пересчитать', success: 'Lip-sync пересчитан');
  }

  // --------------------------------------------------------------- actions

  Future<void> _run(Future<VideoLessonData> Function() action, String fallback, {String? success}) async {
    setState(() => _busy = true);
    try {
      await _player?.pause();
      final lesson = await action();
      if (!mounted) return;
      setState(() => _apply(lesson));
      if (success != null) showSuccessSnack(context, success);
    } catch (e) {
      if (mounted) {
        showErrorSnack(context, e, fallback);
        try {
          final fresh = await _repo.get(widget.courseId, widget.videoId);
          if (mounted) setState(() => _apply(fresh));
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveTitle() async {
    final t = _title.text.trim();
    if (t.isEmpty || t == _lesson?.title) return;
    await _run(() => _repo.update(widget.courseId, widget.videoId, {'title': t}), 'Не удалось сохранить название');
  }

  Future<void> _setMode(String mode) async {
    setState(() => _mode = mode);
    await _run(() => _repo.update(widget.courseId, widget.videoId, {'sourceType': mode}), 'Не удалось сохранить режим');
  }

  Future<void> _pickAudio() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['mp3', 'wav', 'ogg', 'm4a', 'webm']);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    _openedUrl = null;
    await _run(
      () => _repo.uploadAudio(widget.courseId, widget.videoId, bytes: bytes, filename: file.name),
      'Не удалось обработать аудио',
      success: 'Аудио загружено и проанализировано',
    );
  }

  Future<void> _synthesize() async {
    final text = _text.text.trim();
    final voice = _voice;
    if (text.isEmpty || voice == null) return;
    _openedUrl = null;
    await _run(
      () => _repo.synthesize(widget.courseId, widget.videoId, text: text, voice: voice),
      'Не удалось озвучить текст',
      success: 'Текст озвучен',
    );
  }

  // ------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    final back = '/admin/builder/${Uri.encodeComponent(widget.courseId)}/videos';
    return BackGuard(
      fallbackPath: back,
      child: Theme(
        data: lightTheme,
        child: Scaffold(
          backgroundColor: AdminColors.bg,
          appBar: AppBar(
            backgroundColor: AdminColors.card,
            foregroundColor: AdminColors.text,
            elevation: 0,
            title: Text(_lesson?.title ?? 'Видеоурок', style: AdminTypography.pageTitle),
            leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.go(back)),
          ),
          body: _loadError != null
              ? Center(child: Text(_loadError!, style: AdminTypography.body))
              : _lesson == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, box) {
                        final wide = box.maxWidth >= 900;
                        final controls = _buildControls();
                        final preview = _buildPreview(maxHeight: wide ? box.maxHeight - 32 : 640);
                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 420, child: ListView(padding: const EdgeInsets.all(16), children: [controls])),
                              Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(16), child: preview))),
                            ],
                          );
                        }
                        return ListView(
                          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomBarClearance(context)),
                          children: [preview, const SizedBox(height: 16), controls],
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final lesson = _lesson!;
    final timeline = lesson.timeline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCard(
          child: TextField(
            controller: _title,
            enabled: !_busy,
            decoration: adminInputDecoration(label: 'Название видеоурока'),
            onSubmitted: (_) => _saveTitle(),
            onTapOutside: (_) => _saveTitle(),
          ),
        ),
        const SizedBox(height: AdminMetrics.cardGap),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Источник речи', style: AdminTypography.cardTitle),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'audio', icon: Icon(Icons.audio_file_outlined), label: Text('Аудио')),
                  ButtonSegment(value: 'text', icon: Icon(Icons.notes), label: Text('Текст')),
                ],
                selected: {_mode},
                onSelectionChanged: _busy ? null : (s) => _setMode(s.first),
              ),
              const SizedBox(height: AdminMetrics.fieldGap),
              if (_mode == 'audio') ...[
                Text('Загрузите запись речи (MP3, WAV, OGG, M4A, WebM). Система найдёт, где идёт речь, а где паузы.', style: AdminTypography.caption),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _pickAudio,
                  style: AdminButtonStyles.primary(),
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(lesson.sourceType == 'audio' && lesson.audioUrl != null ? 'Заменить аудио' : 'Загрузить аудио'),
                ),
              ] else ...[
                TextField(
                  controller: _text,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 12,
                  maxLength: 5000,
                  decoration: adminInputDecoration(label: 'Текст, который скажет персонаж'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                if (_voices.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _voice,
                    isExpanded: true,
                    decoration: adminInputDecoration(label: 'Голос'),
                    items: [for (final v in _voices) DropdownMenuItem(value: v.id, child: Text(v.label))],
                    onChanged: _busy ? null : (v) => setState(() => _voice = v),
                  ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy || _text.text.trim().isEmpty || _voice == null ? null : _synthesize,
                  style: AdminButtonStyles.primary(),
                  icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                  label: Text(lesson.sourceType == 'text' && lesson.audioUrl != null ? 'Озвучить заново' : 'Озвучить'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text('Обрабатываем речь…', style: AdminTypography.caption),
              ],
            ],
          ),
        ),
        const SizedBox(height: AdminMetrics.cardGap),
        AdminCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Шкала речи', style: AdminTypography.cardTitle),
              const SizedBox(height: 6),
              Text(_statusText(lesson), style: AdminTypography.caption.copyWith(color: lesson.status == 'error' ? AdminColors.danger : null)),
              if (timeline != null && timeline.durationMs > 0) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 28,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _TimelinePainter(timeline: timeline, positionMs: _positionMs, totalMs: _duration.inMilliseconds > 0 ? _duration.inMilliseconds : timeline.durationMs),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Синим — речь (рот двигается), серым — паузы (рот закрыт).', style: AdminTypography.caption),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        timeline.visemeSource == 'rhubarb' ? 'Формы рта: по звукам речи (Rhubarb)' : 'Формы рта: только по громкости',
                        style: AdminTypography.caption,
                      ),
                    ),
                    TextButton(onPressed: _busy || lesson.audioUrl == null ? null : _reanalyze, style: AdminButtonStyles.text(), child: const Text('Пересчитать')),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AdminMetrics.cardGap),
        _AnimationSettingsCard(settings: _settings, onChanged: _changeSettings),
      ],
    );
  }

  String _statusText(VideoLessonData l) {
    final t = l.timeline;
    if (l.status == 'error') return l.error ?? 'Ошибка обработки';
    if (t == null || l.audioUrl == null) return 'Пока нет речи. Загрузите аудио или озвучьте текст.';
    final speech = t.segments.fold<int>(0, (sum, s) => sum + (s.end - s.start));
    return 'Длительность ${(t.durationMs / 1000).toStringAsFixed(1)} с · фраз: ${t.segments.length} · речь ${(speech / 1000).toStringAsFixed(1)} с';
  }

  Widget _buildPreview({required double maxHeight}) {
    final lesson = _lesson!;
    final character = characterFor(lesson.characterId);
    final word = lesson.timeline?.wordAt(_positionMs);
    final canPlay = lesson.audioUrl != null && _playerError == null;
    final phoneHeight = maxHeight.clamp(420.0, 760.0) - 72;
    final phoneWidth = phoneHeight * 9 / 19.5;
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : (lesson.timeline?.durationMs ?? 0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: phoneWidth,
          height: phoneHeight,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF111114),
            borderRadius: BorderRadius.circular(phoneWidth * 0.14),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 24, offset: Offset(0, 10))],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(phoneWidth * 0.11),
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1B1F3B), Color(0xFF2A2350), Color(0xFF3B2A5C)],
                ),
              ),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: phoneWidth * 0.32,
                      height: 18,
                      decoration: BoxDecoration(color: const Color(0xFF111114), borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  Positioned.fill(
                    top: phoneHeight * 0.12,
                    bottom: phoneHeight * 0.16,
                    child: Center(
                      child: character.builder(_pose),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: phoneHeight * 0.05,
                    child: AnimatedOpacity(
                      opacity: word == null ? 0 : 1,
                      duration: const Duration(milliseconds: 120),
                      child: Text(
                        word?.text ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_playerError != null) Text(_playerError!, style: AdminTypography.caption.copyWith(color: AdminColors.danger)),
        SizedBox(
          width: phoneWidth,
          child: Row(
            children: [
              IconButton.filled(
                tooltip: _playing ? 'Пауза' : 'Воспроизвести',
                onPressed: !canPlay ? null : (_playing ? _pause : _play),
                icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              ),
              IconButton(tooltip: 'С начала', onPressed: !canPlay ? null : _replay, icon: const Icon(Icons.replay)),
              const SizedBox(width: 8),
              Expanded(
                child: LinearProgressIndicator(value: totalMs > 0 ? (_positionMs / totalMs).clamp(0.0, 1.0) : 0),
              ),
              const SizedBox(width: 8),
              Text(_fmt(_positionMs), style: AdminTypography.caption),
            ],
          ),
        ),
        if (!canPlay && _playerError == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Добавьте аудио или текст, чтобы запустить предпросмотр.', style: AdminTypography.caption),
          ),
      ],
    );
  }
}

String _fmt(int ms) {
  final s = ms ~/ 1000;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _TimelinePainter extends CustomPainter {
  _TimelinePainter({required this.timeline, required this.positionMs, required this.totalMs});
  final SpeechTimeline timeline;
  final int positionMs;
  final int totalMs;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalMs <= 0) return;
    final bg = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFFE6E8EF));
    final speech = Paint()..color = const Color(0xFF3B82F6);
    for (final s in timeline.segments) {
      final x0 = size.width * s.start / totalMs;
      final x1 = size.width * s.end / totalMs;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x0, 3, x1.clamp(x0 + 1, size.width), size.height - 3), const Radius.circular(4)), speech);
    }
    final x = (size.width * positionMs / totalMs).clamp(0.0, size.width);
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), Paint()..color = const Color(0xFF111827));
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter old) => old.positionMs != positionMs || old.timeline != timeline || old.totalMs != totalMs;
}


class _AnimationSettingsCard extends StatelessWidget {
  const _AnimationSettingsCard({required this.settings, required this.onChanged});
  final AnimationSettings settings;
  final ValueChanged<AnimationSettings> onChanged;

  Widget _slider(String label, double value, ValueChanged<double> set) => Row(
        children: [
          SizedBox(width: 150, child: Text(label, style: AdminTypography.body)),
          Expanded(child: Slider(value: value.clamp(0.0, 2.0), max: 2, divisions: 20, label: value.toStringAsFixed(1), onChanged: set)),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Анимация персонажа', style: AdminTypography.cardTitle),
          const SizedBox(height: 4),
          Text('Сохраняется автоматически. 1.0 — естественно, 0 — выключено, 2.0 — максимум.', style: AdminTypography.caption),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Жесты руками', style: AdminTypography.body),
            value: settings.gestures,
            onChanged: (v) => onChanged(settings.copyWith(gestures: v)),
          ),
          if (settings.gestures) _slider('Сила жестов', settings.gestureIntensity, (v) => onChanged(settings.copyWith(gestureIntensity: v))),
          _slider('Движения головы', settings.headMotion, (v) => onChanged(settings.copyWith(headMotion: v))),
          _slider('Мимика', settings.expressiveness, (v) => onChanged(settings.copyWith(expressiveness: v))),
          _slider('Частота моргания', settings.blinkRate, (v) => onChanged(settings.copyWith(blinkRate: v))),
        ],
      ),
    );
  }
}
