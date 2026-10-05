import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroha/features/video_lessons/domain/characters.dart';
import 'package:payroha/features/video_lessons/presentation/character_rig.dart';

// Renders the rig at several mouth openings to PNGs (path from RIG_OUT) so
// the mouth can be checked by eye; also asserts it renders without errors.
void main() {
  testWidgets('персонаж рисуется с закрытым и открытым ртом', (tester) async {
    final spec = CharacterDefinition.fromJson(jsonDecode(File('assets/characters/cloud/character.json').readAsStringSync()) as Map<String, dynamic>);
    final out = Platform.environment['RIG_OUT'];
    for (final open in [0.0, 0.35, 0.7, 1.0]) {
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 356, height: 450, child: ColoredBox(color: const Color(0xFF2A2350), child: CharacterRig(character: spec, mouthOpen: open, animateIdle: false))),
          ),
        ),
      ));
      await tester.runAsync(() async {
        await precacheImage(AssetImage(spec.image), tester.element(find.byKey(key)));
      });
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/rig_${(open * 100).round()}.png').writeAsBytesSync(data!.buffer.asUint8List());
        });
      }
    }
  });
}
