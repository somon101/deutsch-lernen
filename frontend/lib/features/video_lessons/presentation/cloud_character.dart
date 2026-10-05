import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/performance.dart';

/// The cloud character, built from the reference as a rigged vector model
/// (not the picture): a skeleton (body → head, shoulder → elbow → wrist →
/// hand on each side, hips → legs) and a face rig (eyes with moving pupils
/// and lids, cheeks, a mouth driven by viseme parameters). Everything is
/// drawn from [pose] in a 1000×1300 design space, scaled to fit.
class CloudCharacter extends StatelessWidget {
  const CloudCharacter({super.key, required this.pose});
  final CharacterPose pose;

  static const designSize = Size(1000, 1300);

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: designSize.width / designSize.height,
      child: CustomPaint(painter: _CloudPainter(pose)),
    );
  }
}

// Palette taken from the reference render.
const _skyLight = Color(0xFFB9E3FB);
const _skyMid = Color(0xFF8CCBF4);
const _lavender = Color(0xFFCFC6F2);
const _pink = Color(0xFFF6B2D2);
const _shade = Color(0xFF6C78C4);
const _hoodTop = Color(0xFFEEECFD);
const _hoodMid = Color(0xFFDCD7F6);
const _hoodDark = Color(0xFFB9B2E8);
const _pants = Color(0xFFB7C5F1);
const _pantsDark = Color(0xFF97A6E2);
const _glove = Color(0xFFC6D3F7);
const _gloveDark = Color(0xFFA2B2EC);
const _shoe = Color(0xFFF4F2FD);
const _shoeDark = Color(0xFFCFCBEF);
const _ink = Color(0xFF141418);

class _CloudPainter extends CustomPainter {
  _CloudPainter(this.p);
  final CharacterPose p;

  static const _neck = Offset(500, 668);
  static const _shoulderL = Offset(322, 748);
  static const _shoulderR = Offset(678, 748);
  static const _upperLen = 118.0;
  static const _foreLen = 108.0;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / CloudCharacter.designSize.width;
    canvas.save();
    canvas.scale(scale);

    _groundShadow(canvas);

    // Whole body sways around the feet and breathes.
    canvas.save();
    canvas.translate(500, 1240);
    canvas.rotate(p.bodyRot);
    canvas.translate(-500, -1240 + p.bodyDy);

    _legs(canvas);
    _torso(canvas);
    final left = _armJoints(_shoulderL, p.leftArm, -1);
    final right = _armJoints(_shoulderR, p.rightArm, 1);
    _upperArm(canvas, left, -1);
    _upperArm(canvas, right, 1);
    _hood(canvas);

    // Head hangs from the neck joint.
    canvas.save();
    canvas.translate(_neck.dx + p.headDx, _neck.dy + p.headDy);
    canvas.rotate(p.headRot);
    canvas.translate(-_neck.dx, -_neck.dy);
    _head(canvas);
    _face(canvas);
    canvas.restore();

    _foreArm(canvas, left, -1, p.leftArm);
    _foreArm(canvas, right, 1, p.rightArm);
    canvas.restore();
    canvas.restore();
  }

  // ---------------------------------------------------------------- body

  void _groundShadow(Canvas canvas) {
    final rect = Rect.fromCenter(center: const Offset(500, 1262), width: 470, height: 54);
    canvas.drawOval(
      rect,
      Paint()..shader = const RadialGradient(colors: [Color(0x55000000), Color(0x00000000)]).createShader(rect),
    );
  }

  void _legs(Canvas canvas) {
    for (final x in [434.0, 566.0]) {
      final top = Offset(x, 945);
      final bottom = Offset(x + (x < 500 ? -4 : 4), 1110);
      _limb(canvas, top, bottom, 124, _pants, _pantsDark);
      canvas.save();
      canvas.translate(bottom.dx + (x < 500 ? -10 : 10), 1172);
      canvas.scale(1.45);
      _drawShoe(canvas, Offset.zero, mirror: x > 500);
      canvas.restore();
    }
  }

  void _drawShoe(Canvas canvas, Offset c, {required bool mirror}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (mirror) canvas.scale(-1, 1);
    final upper = Path()
      ..moveTo(-62, 10)
      ..quadraticBezierTo(-70, -46, -14, -52)
      ..quadraticBezierTo(30, -54, 52, -24)
      ..quadraticBezierTo(78, -4, 74, 18)
      ..lineTo(-62, 18)
      ..close();
    canvas.drawPath(
      upper,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_shoe, _shoeDark]).createShader(const Rect.fromLTWH(-70, -54, 150, 74)),
    );
    final sole = RRect.fromRectAndRadius(const Rect.fromLTWH(-68, 10, 148, 26), const Radius.circular(13));
    canvas.drawRRect(sole, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawRRect(sole, Paint()
      ..color = const Color(0x22303060)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    final lace = Paint()
      ..color = const Color(0xFFB3ACE6)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (final dx in [-18.0, 0.0, 18.0]) {
      canvas.drawLine(Offset(dx - 10, -34 + dx * 0.2), Offset(dx + 10, -40 + dx * 0.2), lace);
    }
    canvas.restore();
  }

  void _torso(Canvas canvas) {
    final body = Path()
      ..moveTo(330, 712)
      ..cubicTo(278, 770, 268, 880, 282, 952)
      ..quadraticBezierTo(288, 980, 330, 982)
      ..lineTo(670, 982)
      ..quadraticBezierTo(712, 980, 718, 952)
      ..cubicTo(732, 880, 722, 770, 670, 712)
      ..quadraticBezierTo(500, 680, 330, 712)
      ..close();
    const bounds = Rect.fromLTWH(268, 680, 464, 305);
    canvas.drawPath(body, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_hoodTop, _hoodMid, _hoodDark]).createShader(bounds));
    // Side shading for volume.
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(colors: [Color(0x40525AB8), Color(0x00525AB8), Color(0x00525AB8), Color(0x40525AB8)], stops: [0, 0.28, 0.72, 1]).createShader(bounds),
    );
    // Ribbed hem.
    final hem = RRect.fromRectAndRadius(const Rect.fromLTWH(286, 930, 428, 58), const Radius.circular(26));
    canvas.drawRRect(hem, Paint()..color = const Color(0xFFD3CEF4));
    canvas.drawRRect(hem, Paint()
      ..color = const Color(0x26404090)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    _bolt(canvas, const Offset(500, 848));
  }

  void _bolt(Canvas canvas, Offset c) {
    final bolt = Path()
      ..moveTo(c.dx + 14, c.dy - 64)
      ..lineTo(c.dx - 34, c.dy + 6)
      ..lineTo(c.dx - 4, c.dy + 6)
      ..lineTo(c.dx - 18, c.dy + 64)
      ..lineTo(c.dx + 36, c.dy - 12)
      ..lineTo(c.dx + 6, c.dy - 12)
      ..lineTo(c.dx + 22, c.dy - 64)
      ..close();
    canvas.drawPath(bolt, Paint()
      ..color = const Color(0xAAFFE27A)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawPath(bolt, Paint()..color = const Color(0xFFFFF4B0));
    canvas.drawPath(bolt, Paint()
      ..color = const Color(0xFFFFD95A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round);
  }

  void _hood(Canvas canvas) {
    // Hood folds around the neck under the head, with drawstrings.
    final hood = Path()
      ..moveTo(388, 700)
      ..quadraticBezierTo(500, 640, 612, 700)
      ..quadraticBezierTo(600, 742, 560, 752)
      ..quadraticBezierTo(500, 786, 440, 752)
      ..quadraticBezierTo(400, 742, 388, 700)
      ..close();
    canvas.drawPath(hood, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF4F2FE), Color(0xFFD9D4F6)]).createShader(const Rect.fromLTWH(388, 650, 224, 140)));
    canvas.drawPath(hood, Paint()
      ..color = const Color(0x30404090)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    final string = Paint()
      ..color = const Color(0xFFF7F6FF)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final sway = math.sin(p.bodyRot * 30) * 4;
    for (final x in [470.0, 530.0]) {
      canvas.drawLine(Offset(x, 748), Offset(x + (x < 500 ? -4 : 4) + sway, 830), string);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(x + (x < 500 ? -4 : 4) + sway, 838), width: 13, height: 24), const Radius.circular(6)),
        Paint()..color = const Color(0xFFE2DEF8),
      );
    }
  }

  // ---------------------------------------------------------------- arms

  ({Offset shoulder, Offset elbow, Offset wrist, double foreAngle}) _armJoints(Offset shoulder, ArmPose arm, int side) {
    Offset dir(double a) => Offset(side * math.sin(a), math.cos(a));
    final elbow = shoulder + dir(arm.upper) * _upperLen;
    final wrist = elbow + dir(arm.fore) * _foreLen;
    return (shoulder: shoulder, elbow: elbow, wrist: wrist, foreAngle: math.atan2(wrist.dy - elbow.dy, wrist.dx - elbow.dx));
  }

  void _upperArm(Canvas canvas, ({Offset shoulder, Offset elbow, Offset wrist, double foreAngle}) j, int side) {
    _limb(canvas, j.shoulder, j.elbow, 120, _hoodMid, _hoodDark);
  }

  void _foreArm(Canvas canvas, ({Offset shoulder, Offset elbow, Offset wrist, double foreAngle}) j, int side, ArmPose arm) {
    _limb(canvas, j.elbow, j.wrist, 112, _hoodMid, _hoodDark);
    // Ribbed cuff.
    final dir = Offset(math.cos(j.foreAngle), math.sin(j.foreAngle));
    _limb(canvas, j.wrist - dir * 14, j.wrist + dir * 10, 108, const Color(0xFFE6E2FB), const Color(0xFFC3BCEC));
    _hand(canvas, j.wrist + dir * 26, j.foreAngle, side, arm);
  }

  void _hand(Canvas canvas, Offset at, double angle, int side, ArmPose arm) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(angle - math.pi / 2); // local +y points along the forearm, away from the wrist
    if (side < 0) canvas.scale(-1, 1);
    final spread = arm.handOpen.clamp(0.0, 1.0);
    final finger = Paint()
      ..strokeWidth = 34
      ..strokeCap = StrokeCap.round;
    // Four soft, chunky fingers (glove-like, as in the reference).
    for (var i = 0; i < 4; i++) {
      final isIndex = i == 3;
      final curl = arm.point > 0.5 ? (isIndex ? 0.0 : 0.75) : 0.35 * (1 - spread);
      final a = (-0.36 + i * 0.24) * (0.35 + 0.65 * spread);
      final len = (i == 0 ? 34.0 : isIndex ? 44 : 42) * (1 - curl) + 6;
      final base = Offset(-30 + i * 20.0, 56);
      final tip = base + Offset(-math.sin(a) * len, math.cos(a) * len);
      finger.color = i.isEven ? _glove : const Color(0xFFBDCBF5);
      canvas.drawLine(base, tip, finger);
    }
    final palm = RRect.fromRectAndRadius(const Rect.fromLTWH(-48, -6, 96, 88), const Radius.circular(42));
    canvas.drawRRect(palm, Paint()..shader = const LinearGradient(colors: [_glove, _gloveDark]).createShader(const Rect.fromLTWH(-48, -6, 96, 88)));
    canvas.drawRRect(palm, Paint()
      ..color = const Color(0x22303080)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    final thumbA = 0.75 + 0.45 * spread;
    canvas.drawLine(const Offset(40, 30), Offset(40 + math.sin(thumbA) * 30, 30 + math.cos(thumbA) * 24), Paint()
      ..color = _glove
      ..strokeWidth = 32
      ..strokeCap = StrokeCap.round);
    canvas.restore();
  }

  void _limb(Canvas canvas, Offset a, Offset b, double width, Color light, Color dark) {
    final d = b - a;
    final len = d.distance;
    if (len < 1) return;
    final n = Offset(-d.dy / len, d.dx / len) * (width / 2);
    final shader = LinearGradient(colors: [dark, light, light, dark], stops: const [0, 0.35, 0.6, 1]).createShader(Rect.fromPoints(a + n, a - n));
    canvas.drawLine(a, b, Paint()
      ..shader = shader
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round);
  }

  // ---------------------------------------------------------------- head

  static final Path _cloud = () {
    final circles = <(double, double, double)>[
      (500, 255, 200),
      (318, 345, 155),
      (690, 330, 168),
      (205, 482, 135),
      (800, 470, 140),
      (330, 560, 160),
      (670, 560, 165),
      (500, 470, 245),
      (500, 600, 120),
    ];
    var path = Path();
    for (final (x, y, r) in circles) {
      path = Path.combine(PathOperation.union, path, Path()..addOval(Rect.fromCircle(center: Offset(x, y), radius: r)));
    }
    return path;
  }();

  void _head(Canvas canvas) {
    final b = _cloud.getBounds();
    canvas.drawPath(_cloud, Paint()..shader = const LinearGradient(begin: Alignment(-0.9, -0.9), end: Alignment(0.9, 0.9), colors: [_skyLight, _skyMid, _lavender]).createShader(b));
    // Pink glow on the lower half, like the reference.
    canvas.drawPath(
      _cloud,
      Paint()..shader = const RadialGradient(center: Alignment(0.15, 0.6), radius: 0.62, colors: [Color(0xCCF6B2D2), Color(0x00F6B2D2)]).createShader(b),
    );
    // Soft top-left highlight and bottom shading for volume.
    canvas.drawPath(
      _cloud,
      Paint()..shader = const RadialGradient(center: Alignment(-0.45, -0.75), radius: 0.55, colors: [Color(0x99FFFFFF), Color(0x00FFFFFF)]).createShader(b),
    );
    canvas.drawPath(
      _cloud,
      Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x00000000), Color(0x336C78C4)], stops: [0, 0.6, 1]).createShader(b),
    );
    canvas.drawPath(_cloud, Paint()
      ..color = _shade.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4);
  }

  void _face(Canvas canvas) {
    // Cheeks.
    for (final x in [362.0, 638.0]) {
      final r = Rect.fromCenter(center: Offset(x, 548 - p.smile * 6), width: 120, height: 64);
      canvas.drawOval(r, Paint()..shader = RadialGradient(colors: [_pink.withValues(alpha: 0.55 * p.blush), _pink.withValues(alpha: 0)]).createShader(r));
    }
    _eye(canvas, const Offset(398, 446), const Color(0xFFA9D8F7));
    _eye(canvas, const Offset(602, 448), const Color(0xFFC1D9F8));
    _mouth(canvas, const Offset(500, 556));
  }

  void _eye(Canvas canvas, Offset c, Color lid) {
    final rx = 56.0, ry = 76.0 * p.eyeOpen;
    final white = Rect.fromCenter(center: c, width: rx * 2, height: ry * 2);
    canvas.drawOval(white.shift(const Offset(0, 6)), Paint()
      ..color = const Color(0x30303080)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawOval(white, Paint()..color = const Color(0xFFFDFDFF));
    canvas.drawOval(white.deflate(6), Paint()
      ..color = const Color(0x18303080)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    canvas.save();
    canvas.clipPath(Path()..addOval(white));
    final pupil = c + Offset(p.gazeX * 13, p.gazeY * 12);
    canvas.drawOval(Rect.fromCenter(center: pupil, width: 82, height: 112 * p.eyeOpen), Paint()..color = _ink);
    canvas.drawCircle(pupil + const Offset(-13, -24), 14, Paint()..color = Colors.white);
    canvas.drawCircle(pupil + const Offset(16, 20), 6.5, Paint()..color = Colors.white);
    // Lower lid lifts when smiling (happy eyes); upper lid blinks.
    final lower = (p.smile - 0.55).clamp(0.0, 0.45) * 0.35;
    if (lower > 0) {
      canvas.drawRect(Rect.fromLTRB(white.left, white.bottom - white.height * lower, white.right, white.bottom), Paint()..color = lid);
    }
    if (p.blink > 0) {
      final y = white.top + white.height * p.blink;
      canvas.drawRect(Rect.fromLTRB(white.left - 2, white.top - 2, white.right + 2, y), Paint()..color = lid);
    }
    canvas.restore();
    if (p.blink > 0.7) {
      // Closed eye: a soft lash curve like a sleeping smile.
      final y = c.dy + 10;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx - rx * 0.8, y - 6)
          ..quadraticBezierTo(c.dx, y + 22, c.dx + rx * 0.8, y - 6),
        Paint()
          ..color = _ink.withValues(alpha: (p.blink - 0.7) / 0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _mouth(Canvas canvas, Offset c) {
    final m = p.mouth;
    final baseW = 92.0;
    final w = baseW * m.width;
    final open = m.open;
    final ink = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12;

    if (open < 0.05) {
      // Closed: a smile whose curve follows the expression; pressed lips
      // (M, B, P) flatten it.
      final curve = (8 + 26 * p.smile) * (1 - 0.7 * m.press);
      final path = Path()
        ..moveTo(c.dx - w / 2, c.dy - curve * 0.35)
        ..quadraticBezierTo(c.dx, c.dy + curve, c.dx + w / 2, c.dy - curve * 0.35);
      canvas.drawPath(path, ink..strokeWidth = 12 + 3 * m.press);
      return;
    }

    final h = 18 + 92 * open;
    final ow = w * (1 - 0.35 * m.round);
    final top = c.dy - 10 - h * 0.15;
    final rect = Rect.fromLTWH(c.dx - ow / 2, top, ow, h);
    final corner = Radius.elliptical(ow * (0.32 + 0.18 * m.round), h * 0.5);
    final lift = 10 * p.smile * (1 - m.round);
    final shape = Path()
      ..moveTo(rect.left, rect.top + corner.y * 0.4 - lift)
      ..quadraticBezierTo(rect.center.dx, rect.top - 4, rect.right, rect.top + corner.y * 0.4 - lift)
      ..quadraticBezierTo(rect.right + 2, rect.bottom, rect.center.dx, rect.bottom)
      ..quadraticBezierTo(rect.left - 2, rect.bottom, rect.left, rect.top + corner.y * 0.4 - lift)
      ..close();
    canvas.drawPath(shape, Paint()..color = const Color(0xFF3D1424));
    canvas.save();
    canvas.clipPath(shape);
    if (m.teeth > 0.05) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(rect.left, rect.top - 6, rect.width, 10 + 16 * m.teeth), const Radius.circular(6)),
        Paint()..color = const Color(0xFFFBF9FF),
      );
    }
    final tongueY = rect.bottom - h * (0.18 + 0.45 * m.tongueUp);
    canvas.drawOval(Rect.fromCenter(center: Offset(rect.center.dx, tongueY + h * 0.22), width: ow * 0.72, height: h * 0.6), Paint()..color = const Color(0xFFE8789E));
    canvas.restore();
    canvas.drawPath(shape, ink..strokeWidth = 8);
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) => true;
}
