import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/characters.dart';

/// 2.5D rig over a character's body image: an animated mouth drawn where
/// the original mouth was, eyelids that blink, and a gentle breathing /
/// head bob. The only external input today is [mouthOpen] (0 = closed);
/// expression, head turns and gestures are meant to become further inputs
/// of this same widget.
class CharacterRig extends StatefulWidget {
  const CharacterRig({super.key, required this.character, required this.mouthOpen, this.animateIdle = true});

  final CharacterDefinition character;
  final double mouthOpen;
  final bool animateIdle;

  @override
  State<CharacterRig> createState() => _CharacterRigState();
}

class _CharacterRigState extends State<CharacterRig> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  final _random = math.Random(7);
  double _nextBlinkAt = 2.2;
  double _blinkStart = -10;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final t = elapsed.inMicroseconds / 1e6;
      if (t >= _nextBlinkAt) {
        _blinkStart = t;
        _nextBlinkAt = t + 2.5 + _random.nextDouble() * 3.0;
      }
      setState(() => _elapsed = elapsed);
    });
    if (widget.animateIdle) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  double get _blink {
    final t = _elapsed.inMicroseconds / 1e6 - _blinkStart;
    const closeTime = 0.07, holdTime = 0.04, openTime = 0.09;
    if (t < 0 || t > closeTime + holdTime + openTime) return 0;
    if (t < closeTime) return t / closeTime;
    if (t < closeTime + holdTime) return 1;
    return 1 - (t - closeTime - holdTime) / openTime;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.character;
    final t = _elapsed.inMicroseconds / 1e6;
    final open = widget.mouthOpen.clamp(0.0, 1.0);
    return AspectRatio(
      aspectRatio: c.aspect,
      child: LayoutBuilder(
        builder: (context, box) {
          final h = box.maxHeight;
          final breath = math.sin(t * 2 * math.pi / 3.6);
          final dy = -breath * h * 0.006 - open * h * 0.006;
          final tilt = (math.sin(t * 1.3) * 0.006) + open * 0.01 * math.sin(t * 9);
          return Transform.translate(
            offset: Offset(0, dy),
            child: Transform.rotate(
              angle: tilt,
              alignment: const Alignment(0, 0.9),
              child: Transform.scale(
                scale: 1 + breath * 0.004,
                alignment: Alignment.bottomCenter,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(c.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    CustomPaint(painter: _FacePainter(character: c, mouthOpen: open, blink: _blink)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.character, required this.mouthOpen, required this.blink});

  final CharacterDefinition character;
  final double mouthOpen;
  final double blink;

  @override
  void paint(Canvas canvas, Size size) {
    _paintLids(canvas, size);
    _paintMouth(canvas, size);
  }

  void _paintLids(Canvas canvas, Size size) {
    if (blink <= 0) return;
    for (final e in character.eyes) {
      final rect = Rect.fromCenter(center: Offset(e.cx * size.width, e.cy * size.height), width: e.rx * 2 * size.width * 1.06, height: e.ry * 2 * size.height * 1.06);
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      final lid = Rect.fromLTWH(rect.left, rect.top, rect.width, rect.height * blink);
      canvas.drawRect(lid, Paint()..color = e.lidColor);
      if (blink > 0.85) {
        final y = rect.top + rect.height * blink;
        canvas.drawArc(
          Rect.fromCenter(center: Offset(rect.center.dx, y - rect.height * 0.08), width: rect.width * 0.8, height: rect.height * 0.16),
          0.1,
          math.pi - 0.2,
          false,
          Paint()
            ..color = const Color(0x55203050)
            ..style = PaintingStyle.stroke
            ..strokeWidth = rect.width * 0.05
            ..strokeCap = StrokeCap.round,
        );
      }
      canvas.restore();
    }
  }

  void _paintMouth(Canvas canvas, Size size) {
    final m = character.mouth;
    final cx = m.cx * size.width;
    final cy = m.cy * size.height;
    final w = m.width * size.width;
    final h = m.height * size.height;
    final stroke = h * 0.42;

    if (mouthOpen < 0.06) {
      // Closed: the same soft smile the original drawing had.
      final arc = Rect.fromCenter(center: Offset(cx, cy - h * 0.55), width: w * 0.86, height: h * 1.7);
      canvas.drawArc(
        arc,
        math.pi * 0.12,
        math.pi * 0.76,
        false,
        Paint()
          ..color = m.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round,
      );
      return;
    }

    // Open: a rounded mouth that grows with loudness — wider and taller,
    // slightly narrower at full open, like a real "ah".
    final o = Curves.easeOut.transform(mouthOpen);
    final mw = w * (0.62 + 0.28 * (1 - o * 0.4));
    final mh = h * (0.7 + 2.4 * o);
    final top = cy - h * 0.25;
    final rect = Rect.fromLTWH(cx - mw / 2, top, mw, mh);
    final path = Path()
      ..moveTo(rect.left, rect.top + mh * 0.18)
      ..quadraticBezierTo(rect.center.dx, rect.top - mh * 0.05, rect.right, rect.top + mh * 0.18)
      ..quadraticBezierTo(rect.right + mw * 0.02, rect.bottom, rect.center.dx, rect.bottom)
      ..quadraticBezierTo(rect.left - mw * 0.02, rect.bottom, rect.left, rect.top + mh * 0.18)
      ..close();
    canvas.drawPath(path, Paint()..color = m.inner);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(rect.center.dx, rect.bottom + mh * 0.08), width: mw * 0.78, height: mh * 0.62),
      Paint()..color = m.tongue,
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = m.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke * 0.55
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.mouthOpen != mouthOpen || old.blink != blink || old.character != character;
}
