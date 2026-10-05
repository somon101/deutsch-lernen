import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/video_lessons/domain/performance.dart';
import 'package:payroha/features/video_lessons/presentation/cloud_character.dart';

CharacterPose _pose({String viseme = 'X', double blink = 0, ArmPose? left, ArmPose? right, double smile = 0.7, double gx = 0, double headRot = 0}) => CharacterPose(
      mouth: visemeShapes[viseme]!,
      smile: smile,
      blink: blink,
      gazeX: gx,
      gazeY: 0,
      eyeOpen: 1,
      headRot: headRot,
      headDx: 0,
      headDy: 0,
      bodyDy: 0,
      bodyRot: 0,
      leftArm: left ?? Performance.restLeft,
      rightArm: right ?? Performance.restRight,
      blush: 0.6,
    );

double _r(double d) => d * math.pi / 180;

// Renders named poses to PNG (dir from RIG_OUT) for visual review, and
// checks that every pose paints without throwing.
void main() {
  testWidgets('облако рисуется во всех позах', (tester) async {
    final out = Platform.environment['RIG_OUT'];
    final poses = <String, CharacterPose>{
      'rest': _pose(),
      'D': _pose(viseme: 'D', smile: 0.4),
      'F': _pose(viseme: 'F', smile: 0.4),
      'B': _pose(viseme: 'B', smile: 0.4),
      'blink': _pose(blink: 1),
      'wave': _pose(left: ArmPose(upper: _r(105), fore: _r(160), handOpen: 1), viseme: 'C', headRot: _r(-3)),
      'explain': _pose(right: ArmPose(upper: _r(30), fore: _r(100), handOpen: 0.9), viseme: 'E', gx: 0.5),
      'openBoth': _pose(left: ArmPose(upper: _r(34), fore: _r(92), handOpen: 1), right: ArmPose(upper: _r(34), fore: _r(92), handOpen: 1), viseme: 'H'),
      'point': _pose(right: ArmPose(upper: _r(22), fore: _r(150), handOpen: 0.2, point: 1), viseme: 'G'),
    };
    for (final entry in poses.entries) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 300, height: 390, child: ColoredBox(color: const Color(0xFF2A2350), child: CloudCharacter(pose: entry.value))),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/cloud_${entry.key}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
  });
}
