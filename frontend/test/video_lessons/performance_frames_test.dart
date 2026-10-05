import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/video_lessons/domain/performance.dart';
import 'package:payroha/features/video_lessons/domain/speech_timeline.dart';
import 'package:payroha/features/video_lessons/presentation/cloud_character.dart';

// Renders frames of a real performance (fixture "long") to PNGs when
// FRAMES_OUT is set; always checks the frames paint without errors.
void main() {
  testWidgets('кадры выступления рисуются', (tester) async {
    final tl = SpeechTimeline.fromJson(jsonDecode(File('test/video_lessons/fixtures/long.json').readAsStringSync()) as Map<String, dynamic>);
    final perf = Performance(tl, const AnimationSettings(), seed: 42);
    final out = Platform.environment['FRAMES_OUT'];
    for (var i = 0; i < 12; i++) {
      final ms = 300 + i * 600;
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 240, height: 312, child: ColoredBox(color: const Color(0xFF2A2350), child: CloudCharacter(pose: perf.poseAt(ms)))),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/frame_${i.toString().padLeft(2, '0')}_${ms}ms.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
  });
}
