import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import '../../../../core/api/api_client.dart';
import '../lesson_runner_controller.dart';
import '../widgets/playback_time_tracker.dart';

String _basename(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final parts = path.split('/');
  return parts.isEmpty ? url : parts.last;
}

String _formatTime(Duration d) {
  if (d.isNegative) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds.remainder(60);
  return '$m:${s.toString().padLeft(2, '0')}';
}

const _rates = [0.75, 1.0, 1.25];

/// Mirrors AudioStage.tsx: play/pause, seek, playback rate, "Далее" gated
/// on reaching the end of the recording.
class AudioStage extends ConsumerStatefulWidget {
  const AudioStage({super.key, required this.runnerKey, required this.onComplete, this.graphNodeMediaUrl = false, this.mediaUrlOverride, this.nextLabel});

  final LessonRunnerKey runnerKey;
  final VoidCallback onComplete;
  // See VideoStage's identical fields (§ lesson graph, 2026-09-03).
  final bool graphNodeMediaUrl;
  final String? mediaUrlOverride;
  final String? nextLabel;

  @override
  ConsumerState<AudioStage> createState() => _AudioStageState();
}

class _AudioStageState extends ConsumerState<AudioStage> {
  // Lazily created, only once there's actually audio to play — see
  // video_stage.dart's identical fix for why: constructing a media_kit
  // Player touches the native library immediately, which is both wasted
  // work for the (common, for legacy lessons) no-audio case and a real
  // crash risk in some run harnesses when never actually needed.
  Player? _player;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _rate = 1.0;
  bool _finished = false;
  String? _error;
  String? _openedUrl;
  late final _timeTracker = PlaybackTimeTracker(
    onFlush: (seconds) => ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).recordActivityTime('audio', seconds),
  );

  Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final player = Player();
    _player = player;
    _subscriptions.addAll([
      player.stream.playing.listen((v) {
        _timeTracker.setPlaying(v);
        if (mounted) setState(() => _playing = v);
      }),
      player.stream.position.listen((v) => mounted ? setState(() => _position = v) : null),
      player.stream.duration.listen((v) => mounted ? setState(() => _duration = v) : null),
      player.stream.completed.listen((v) {
        if (v && mounted) setState(() => _finished = true);
      }),
      player.stream.error.listen((e) {
        if (mounted) setState(() => _error = 'Не удалось загрузить аудиофайл. Проверьте, что файл существует и доступен, и попробуйте ещё раз.');
      }),
    ]);
    return player;
  }

  @override
  void dispose() {
    _timeTracker.dispose();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    setState(() => _error = null);
    try {
      if (_playing) {
        await _player?.pause();
      } else {
        await _player?.play();
      }
    } catch (_) {
      setState(() => _error = 'Не удалось запустить воспроизведение аудио. Проверьте, не отключён звук, и попробуйте ещё раз.');
    }
  }

  Future<void> _setRate(double r) async {
    setState(() => _rate = r);
    await _player?.setRate(r);
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    final rawUrl = widget.graphNodeMediaUrl ? widget.mediaUrlOverride : data.content.audioUrl;

    if (rawUrl == null || rawUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Аудио не найдено', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Для этого урока не загружена аудиозапись.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: widget.onComplete, child: const Text('Пропустить и продолжить')),
          ],
        ),
      );
    }

    final player = _ensurePlayer();
    final url = ref.read(apiClientProvider).assetUrl(rawUrl);
    if (_openedUrl != url) {
      _openedUrl = url;
      player.open(Media(url), play: false);
    }

    final maxMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds.toDouble() : 1.0;
    final posMs = _position.inMilliseconds.toDouble().clamp(0, maxMs).toDouble();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Прослушайте аудио', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          const Text('Послушайте запись и закрепите произношение фраз из урока.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🎧', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 8),
                  Text(_basename(rawUrl), style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      IconButton.filled(
                        icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        onPressed: _toggle,
                      ),
                      Expanded(
                        child: Slider(
                          value: posMs,
                          max: maxMs,
                          onChanged: (v) => player.seek(Duration(milliseconds: v.round())),
                        ),
                      ),
                      Text('${_formatTime(_position)} / ${_formatTime(_duration)}'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final r in _rates)
                        ChoiceChip(label: Text('$r×'), selected: _rate == r, onSelected: (_) => _setRate(r)),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            _finished ? '✓ Запись прослушана' : 'Прослушайте запись до конца, чтобы продолжить',
            style: TextStyle(
              color: _finished ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _finished ? widget.onComplete : null,
            child: Text(widget.nextLabel ?? 'Перейти к практике →'),
          ),
        ],
      ),
    );
  }
}
