import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/api/api_client.dart';
import '../lesson_runner_controller.dart';
import '../widgets/playback_time_tracker.dart';

String _basename(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final parts = path.split('/');
  return parts.isEmpty ? url : parts.last;
}

/// Mirrors VideoStage.tsx: "Далее" stays disabled until the learner either
/// watches to the end or reaches 90% of the duration (same threshold as the
/// React version's onTimeUpdate check).
class VideoStage extends ConsumerStatefulWidget {
  const VideoStage({super.key, required this.runnerKey, required this.onComplete});

  final LessonRunnerKey runnerKey;
  final VoidCallback onComplete;

  @override
  ConsumerState<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends ConsumerState<VideoStage> {
  // Created lazily, only once we know there's actually a video to play —
  // constructing media_kit's Player touches the native libmpv library
  // immediately, which both wastes it for the (common, for legacy lessons)
  // no-video case and — as a real integration-test failure caught — can
  // throw outright in some Windows run harnesses if never actually needed.
  Player? _player;
  VideoController? _controller;
  bool _watched = false;
  String? _openedUrl;
  StreamSubscription<bool>? _playingSubscription;
  late final _timeTracker = PlaybackTimeTracker(
    onFlush: (seconds) => ref.read(lessonRunnerControllerProvider(widget.runnerKey).notifier).recordActivityTime('video', seconds),
  );

  @override
  void dispose() {
    _timeTracker.dispose();
    _playingSubscription?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(lessonRunnerControllerProvider(widget.runnerKey)).value!;
    final rawUrl = data.content.videoUrl;

    if (rawUrl == null || rawUrl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Видео не найдено', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Для этого урока не загружено видео.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: widget.onComplete, child: const Text('Пропустить и продолжить')),
          ],
        ),
      );
    }

    if (_player == null) {
      final player = Player();
      _player = player;
      _controller = VideoController(player);
      _playingSubscription = player.stream.playing.listen(_timeTracker.setPlaying);
      player.stream.completed.listen((completed) {
        if (completed && mounted) setState(() => _watched = true);
      });
      player.stream.position.listen((position) {
        final duration = player.state.duration;
        if (duration.inMilliseconds > 0 && position.inMilliseconds / duration.inMilliseconds >= 0.9) {
          if (!_watched && mounted) setState(() => _watched = true);
        }
      });
    }

    final url = ref.read(apiClientProvider).assetUrl(rawUrl);
    if (_openedUrl != url) {
      _openedUrl = url;
      _player!.open(Media(url));
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Посмотрите видео', style: Theme.of(context).textTheme.headlineSmall),
          Text(_basename(rawUrl), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          Expanded(
            child: Center(
              child: AspectRatio(aspectRatio: 16 / 9, child: Video(controller: _controller!)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _watched ? '✓ Видео просмотрено' : 'Досмотрите видео до конца, чтобы продолжить',
            style: TextStyle(
              color: _watched ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: _watched ? widget.onComplete : null,
              child: const Text('Перейти к мини-тесту →'),
            ),
          ),
        ],
      ),
    );
  }
}
